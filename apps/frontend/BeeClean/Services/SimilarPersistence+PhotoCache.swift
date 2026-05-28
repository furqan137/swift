import Foundation
import SwiftData
import Photos

extension SimilarPersistence {
    // MARK: - Photo Cache

    /// Loads all cached photos into an AnalyzedPhoto array + index.
    /// **Main-actor version** — for non-main contexts that need to avoid
    /// watchdog timeouts during scene updates, use
    /// `loadCachedPhotosBackground()` instead.
    ///
    /// Returns IMMEDIATELY with whatever SwiftData has; PHAsset validation
    /// + stale pruning happens in a fire-and-forget background task. Keeps
    /// app launch instant — rows for assets the user deleted between
    /// sessions linger for a few hundred ms before the background prune
    /// removes them.
    @MainActor
    static func loadCachedPhotos() async -> [AnalyzedPhoto] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedPhoto>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        let photos = cached.map { $0.toAnalyzedPhoto() }
        let cachedIds = cached.map(\.assetId)

        // Background validation pass — does not block the return.
        Task.detached(priority: .background) {
            let existing = existingAssetIds(cachedIds)
            let staleIds = cachedIds.filter { !existing.contains($0) }
            guard !staleIds.isEmpty else { return }
            await MainActor.run {
                deletePhotos(assetIds: staleIds)
            }
        }

        return photos
    }

    /// **Background-safe version** — runs on a background ModelContext to
    /// avoid blocking the main thread during scene updates (which triggers
    /// 0x8BADF00D watchdog timeout). Use this from `Task.detached` blocks.
    nonisolated static func loadCachedPhotosBackground() -> [AnalyzedPhoto] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CachedPhoto>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        // Collect all asset IDs to validate against the photo library
        let cachedIds = cached.map(\.assetId)
        let existing = existingAssetIds(cachedIds)

        var photos: [AnalyzedPhoto] = []
        var staleIds: [String] = []

        for row in cached {
            if existing.contains(row.assetId) {
                photos.append(row.toAnalyzedPhoto())
            } else {
                staleIds.append(row.assetId)
            }
        }

        // Prune stale rows on main actor (deletion must happen on main context)
        if !staleIds.isEmpty {
            Task { @MainActor in
                deletePhotos(assetIds: staleIds)
            }
        }

        return photos
    }

    /// **Background-safe save** — same upsert semantics as `savePhotos`, but
    /// runs on a fresh `ModelContext(container)` so callers in detached scan
    /// tasks can persist without an `await MainActor.run` hop. Used by the
    /// scan-coordinator end-of-phase flushes which can otherwise stall the
    /// main thread for hundreds of milliseconds on large libraries.
    nonisolated static func savePhotosBackground(_ photos: [AnalyzedPhoto]) {
        let context = ModelContext(container)
        let now = Date()

        for photo in photos {
            let id = photo.assetIdentifier
            var descriptor = FetchDescriptor<CachedPhoto>(
                predicate: #Predicate { $0.assetId == id }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                existing.dHash64 = photo.dHash64
                existing.sharpnessScore = photo.sharpnessScore
                existing.creationDate = photo.creationDate
                existing.pixelWidth = photo.pixelWidth
                existing.pixelHeight = photo.pixelHeight
                existing.fileSize = photo.fileSize ?? 0
                existing.analyzedAt = now
                // Only overwrite sourceAppRaw when the new value is non-nil.
                // Tier 2 (EXIF) enrichment may run BEFORE the scan re-writes
                // this row; keeping the previously-detected value prevents
                // the Instagram badge from disappearing on a re-scan that
                // doesn't itself run EXIF.
                if let raw = photo.sourceApp?.rawValue {
                    existing.sourceAppRaw = raw
                }
            } else {
                context.insert(CachedPhoto(
                    assetId: photo.assetIdentifier,
                    dHash64: photo.dHash64,
                    sharpnessScore: photo.sharpnessScore,
                    creationDate: photo.creationDate,
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight,
                    fileSize: photo.fileSize ?? 0,
                    analyzedAt: now,
                    sourceAppRaw: photo.sourceApp?.rawValue
                ))
            }
        }

        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.PhotoCache] background context.save failed: \(error.localizedDescription)")
        }
    }

    /// Saves analyzed photos to the cache. Upserts by assetId.
    @MainActor
    static func savePhotos(_ photos: [AnalyzedPhoto]) {
        let context = container.mainContext
        let now = Date()

        for photo in photos {
            // Upsert: fetch existing or create new
            let id = photo.assetIdentifier
            var descriptor = FetchDescriptor<CachedPhoto>(
                predicate: #Predicate { $0.assetId == id }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                existing.dHash64 = photo.dHash64
                existing.sharpnessScore = photo.sharpnessScore
                existing.creationDate = photo.creationDate
                existing.pixelWidth = photo.pixelWidth
                existing.pixelHeight = photo.pixelHeight
                existing.fileSize = photo.fileSize ?? 0
                existing.analyzedAt = now
                // See savePhotosBackground for the "only overwrite when
                // non-nil" rationale — preserves Tier 2 EXIF results across
                // re-scans that don't re-run EXIF.
                if let raw = photo.sourceApp?.rawValue {
                    existing.sourceAppRaw = raw
                }
            } else {
                context.insert(CachedPhoto(
                    assetId: photo.assetIdentifier,
                    dHash64: photo.dHash64,
                    sharpnessScore: photo.sharpnessScore,
                    creationDate: photo.creationDate,
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight,
                    fileSize: photo.fileSize ?? 0,
                    analyzedAt: now,
                    sourceAppRaw: photo.sourceApp?.rawValue
                ))
            }
        }

        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.PhotoCache] context.save failed: \(error.localizedDescription)")
        }
    }

    /// Removes specific asset IDs from the photo cache.
    @MainActor
    static func deletePhotos(assetIds: [String]) {
        guard !assetIds.isEmpty else { return }
        let context = container.mainContext
        let targets = assetIds
        let descriptor = FetchDescriptor<CachedPhoto>(
            predicate: #Predicate { targets.contains($0.assetId) }
        )
        guard let toDelete = try? context.fetch(descriptor) else { return }
        toDelete.forEach { context.delete($0) }
        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.PhotoCache] context.save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Group Cache

    /// Loads cached groups and converts to SimilarGroupVM array.
    /// **Main-actor version** — for non-main contexts that need to avoid
    /// watchdog timeouts during scene updates, use
    /// `loadCachedGroupsBackground()` instead.
    ///
    /// Returns IMMEDIATELY with every cached group; PHAsset validation +
    /// stale-group pruning runs in a background task. Same launch-perf
    /// rationale as `loadCachedPhotos`.
    @MainActor
    static func loadCachedGroups() async -> [SimilarGroupVM] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedGroup>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        // Build result from every cached row, no PHAsset validation up front.
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

        // Background validation pass — prune groups that lost too many assets.
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
                deleteGroups(ids: staleGroupIds)
            }
        }

        return result
    }

    /// **Background-safe version** — runs on a background ModelContext to
    /// avoid blocking the main thread during scene updates (which triggers
    /// 0x8BADF00D watchdog timeout). Use this from `Task.detached` blocks.
    nonisolated static func loadCachedGroupsBackground() -> [SimilarGroupVM] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CachedGroup>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return [] }

        // Validate all referenced asset IDs still exist
        let allIds = cached.flatMap { $0.items.map(\.assetId) }
        let existing = existingAssetIds(allIds)

        var result: [SimilarGroupVM] = []
        var staleGroupIds: [UUID] = []

        for row in cached {
            // Filter items to only those still in the library
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

        // Remove stale groups on main actor (deletion must happen on main context)
        if !staleGroupIds.isEmpty {
            Task { @MainActor in
                deleteGroups(ids: staleGroupIds)
            }
        }

        return result
    }

    /// **Background-safe save** — same replace-all semantics as `saveGroups`
    /// on a fresh `ModelContext(container)`. Lets scan-coordinator end-of-
    /// phase flushes persist without hopping back to main.
    nonisolated static func saveGroupsBackground(_ groups: [SimilarGroupVM]) {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<CachedGroup>()
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
            context.insert(CachedGroup(
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
            print("[SimilarPersistence.PhotoCache] background context.save failed: \(error.localizedDescription)")
        }
    }

    /// Saves groups to the cache. Replaces all existing groups.
    @MainActor
    static func saveGroups(_ groups: [SimilarGroupVM]) {
        let context = container.mainContext

        // Clear old groups
        let descriptor = FetchDescriptor<CachedGroup>()
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

            context.insert(CachedGroup(
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
            print("[SimilarPersistence.PhotoCache] context.save failed: \(error.localizedDescription)")
        }
    }

    /// Persists just the selection state changes for a single group.
    @MainActor
    static func updateGroupSelections(groupId: UUID, items: [SimilarGroupItem]) {
        let context = container.mainContext
        let id = groupId
        var descriptor = FetchDescriptor<CachedGroup>(
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
            print("[SimilarPersistence.PhotoCache] context.save failed: \(error.localizedDescription)")
        }
    }

    /// Removes specific groups by ID.
    @MainActor
    static func deleteGroups(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let context = container.mainContext
        let targets = ids
        let descriptor = FetchDescriptor<CachedGroup>(
            predicate: #Predicate { targets.contains($0.groupId) }
        )
        guard let toDelete = try? context.fetch(descriptor) else { return }
        toDelete.forEach { context.delete($0) }
        do {
            try context.save()
        } catch {
            print("[SimilarPersistence.PhotoCache] context.save failed: \(error.localizedDescription)")
        }
    }
}
