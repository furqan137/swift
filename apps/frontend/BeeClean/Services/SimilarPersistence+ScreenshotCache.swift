import Foundation
import SwiftData

extension SimilarPersistence {
    // MARK: - Screenshot Group Cache

    /// Loads cached screenshot groups and converts to SimilarGroupVM array.
    /// **Main-actor version** — for non-main contexts that need to avoid
    /// watchdog timeouts during scene updates, use
    /// `loadCachedScreenshotGroupsBackground()` instead.
    ///
    /// Returns immediately; PHAsset validation runs in the background. See
    /// `loadCachedPhotos` for the launch-perf rationale.
    @MainActor
    static func loadCachedScreenshotGroups() async -> [SimilarGroupVM] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedScreenshotGroup>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        var result: [SimilarGroupVM] = []
        for row in cached {
            let items = row.items.map { cached in
                SimilarGroupItem(
                    assetId: cached.assetId,
                    isBest: cached.isBest,
                    isSelectedForDelete: cached.isSelectedForDelete,
                    score: cached.score,
                    hash: cached.hash,
                    fileSize: cached.fileSize > 0 ? cached.fileSize : row.totalBytes / Int64(max(row.items.count, 1)),
                    sourceApp: cached.sourceAppRaw.flatMap { PhotoSource(rawValue: $0) }
                )
            }
            result.append(SimilarGroupVM(
                id: row.groupId,
                count: row.items.count,
                totalBytes: row.totalBytes,
                confidence: row.confidence,
                createdAt: row.createdAt,
                bestId: row.bestId,
                items: items
            ))
        }

        let allIds = cached.flatMap { $0.items.map(\.assetId) }
        let snapshot = cached.map { ($0.groupId, $0.items.map(\.assetId)) }
        Task.detached(priority: .background) {
            let existing = existingAssetIds(allIds)
            let staleGroupIds: [UUID] = snapshot.compactMap { (groupId, ids) in
                let validCount = ids.filter { existing.contains($0) }.count
                return validCount <= 1 ? groupId : nil
            }
            guard !staleGroupIds.isEmpty else { return }
            await MainActor.run {
                deleteScreenshotGroups(ids: staleGroupIds)
            }
        }

        return result
    }

    /// **Background-safe version** — runs on a background ModelContext to
    /// avoid blocking the main thread during scene updates (which triggers
    /// 0x8BADF00D watchdog timeout). Use this from `Task.detached` blocks.
    nonisolated static func loadCachedScreenshotGroupsBackground() -> [SimilarGroupVM] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CachedScreenshotGroup>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        let allIds = cached.flatMap { $0.items.map(\.assetId) }
        let existing = existingAssetIds(allIds)

        var result: [SimilarGroupVM] = []
        var staleGroupIds: [UUID] = []

        for row in cached {
            let validItems = row.items.filter { existing.contains($0.assetId) }

            if validItems.count <= 1 {
                staleGroupIds.append(row.groupId)
                continue
            }

            let items = validItems.map { cached in
                SimilarGroupItem(
                    assetId: cached.assetId,
                    isBest: cached.isBest,
                    isSelectedForDelete: cached.isSelectedForDelete,
                    score: cached.score,
                    hash: cached.hash,
                    fileSize: cached.fileSize > 0 ? cached.fileSize : row.totalBytes / Int64(max(validItems.count, 1)),
                    sourceApp: cached.sourceAppRaw.flatMap { PhotoSource(rawValue: $0) }
                )
            }

            result.append(SimilarGroupVM(
                id: row.groupId,
                count: validItems.count,
                totalBytes: row.totalBytes,
                confidence: row.confidence,
                createdAt: row.createdAt,
                bestId: row.bestId,
                items: items
            ))
        }

        if !staleGroupIds.isEmpty {
            Task { @MainActor in
                deleteScreenshotGroups(ids: staleGroupIds)
            }
        }

        return result
    }

    /// **Background-safe save** — same replace-all semantics as
    /// `saveScreenshotGroups` on a fresh `ModelContext(container)`.
    nonisolated static func saveScreenshotGroupsBackground(_ groups: [SimilarGroupVM]) {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<CachedScreenshotGroup>()
        if let old = try? context.fetch(descriptor) {
            for row in old { context.delete(row) }
        }

        let now = Date()
        for group in groups {
            let items = group.items.map { item in
                CachedGroupItem(
                    assetId: item.assetId,
                    isBest: item.isBest,
                    isSelectedForDelete: item.isSelectedForDelete,
                    score: item.score,
                    hash: item.hash,
                    fileSize: item.fileSize,
                    sourceAppRaw: item.sourceApp?.rawValue
                )
            }
            context.insert(CachedScreenshotGroup(
                groupId: group.id,
                bestId: group.bestId,
                totalBytes: group.totalBytes,
                createdAt: group.createdAt,
                confidence: group.confidence,
                items: items,
                clusteredAt: now
            ))
        }

        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.ScreenshotCache] background context.save failed: \(error.localizedDescription)")
        }
    }

    /// Saves screenshot groups to the cache. Replaces all existing screenshot groups.
    @MainActor
    static func saveScreenshotGroups(_ groups: [SimilarGroupVM]) {
        let context = container.mainContext

        let descriptor = FetchDescriptor<CachedScreenshotGroup>()
        if let old = try? context.fetch(descriptor) {
            for row in old { context.delete(row) }
        }

        let now = Date()
        for group in groups {
            let items = group.items.map { item in
                CachedGroupItem(
                    assetId: item.assetId,
                    isBest: item.isBest,
                    isSelectedForDelete: item.isSelectedForDelete,
                    score: item.score,
                    hash: item.hash,
                    fileSize: item.fileSize,
                    sourceAppRaw: item.sourceApp?.rawValue
                )
            }

            context.insert(CachedScreenshotGroup(
                groupId: group.id,
                bestId: group.bestId,
                totalBytes: group.totalBytes,
                createdAt: group.createdAt,
                confidence: group.confidence,
                items: items,
                clusteredAt: now
            ))
        }

        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.ScreenshotCache] context.save failed: \(error.localizedDescription)")
        }
    }

    /// Persists selection state changes for a single screenshot group.
    @MainActor
    static func updateScreenshotGroupSelections(groupId: UUID, items: [SimilarGroupItem]) {
        let context = container.mainContext
        let id = groupId
        var descriptor = FetchDescriptor<CachedScreenshotGroup>(
            predicate: #Predicate { $0.groupId == id }
        )
        descriptor.fetchLimit = 1

        guard let row = try? context.fetch(descriptor).first else { return }

        row.items = items.map { item in
            CachedGroupItem(
                assetId: item.assetId,
                isBest: item.isBest,
                isSelectedForDelete: item.isSelectedForDelete,
                score: item.score,
                hash: item.hash,
                fileSize: item.fileSize,
                sourceAppRaw: item.sourceApp?.rawValue
            )
        }

        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.ScreenshotCache] context.save failed: \(error.localizedDescription)")
        }
    }

    /// Removes specific screenshot groups by ID.
    @MainActor
    static func deleteScreenshotGroups(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let context = container.mainContext
        let targets = ids
        let descriptor = FetchDescriptor<CachedScreenshotGroup>(
            predicate: #Predicate { targets.contains($0.groupId) }
        )
        guard let toDelete = try? context.fetch(descriptor) else { return }
        toDelete.forEach { context.delete($0) }
        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.ScreenshotCache] context.save failed: \(error.localizedDescription)")
        }
    }

}
