import Foundation
import Photos

// MARK: - Deletion
extension SimilarPhotosStore {

    enum GroupSource { case photos, screenshots, videos }

    func deleteSelected(
        limit: Int? = nil,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        var ids = groups.flatMap { $0.items.filter(\.isSelectedForDelete).map(\.assetId) }
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .photos, category: category)
    }

    func deleteSelected(
        inGroup groupId: UUID,
        limit: Int? = nil,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        guard let g = groups.first(where: { $0.id == groupId }) else { return false }
        var ids = g.items.filter(\.isSelectedForDelete).map(\.assetId)
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .photos, category: category)
    }

    func deleteSelectedScreenshotGroup(inGroup groupId: UUID, limit: Int? = nil) async -> Bool {
        guard let g = screenshotGroups.first(where: { $0.id == groupId }) else { return false }
        var ids = g.items.filter(\.isSelectedForDelete).map(\.assetId)
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .screenshots)
    }

    func deleteSelectedVideoGroup(inGroup groupId: UUID, limit: Int? = nil) async -> Bool {
        guard let g = videoGroups.first(where: { $0.id == groupId }) else { return false }
        var ids = g.items.filter(\.isSelectedForDelete).map(\.assetId)
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .videos)
    }

    func deleteAllSelectedScreenshots(limit: Int? = nil) async -> Bool {
        var ids = screenshotGroups.flatMap { $0.items.filter(\.isSelectedForDelete).map(\.assetId) }
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .screenshots)
    }

    func deleteAllSelectedVideos(limit: Int? = nil) async -> Bool {
        var ids = videoGroups.flatMap { $0.items.filter(\.isSelectedForDelete).map(\.assetId) }
        if let limit { ids = Array(ids.prefix(limit)) }
        return await performDelete(assetIds: ids, source: .videos)
    }

    // MARK: - Single-asset delete (used by the full-screen detail pager)
    // Three source-specific entry points mirror the existing
    // `deleteSelected[…]` surface. Each routes through the same `performDelete`
    // pipeline, so the asset lands in iOS Photos' Recently Deleted album
    // (30-day system grace period) and local caches / group bookkeeping stay
    // in sync.

    func deletePhotoSingle(
        assetId: String,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        await performDelete(assetIds: [assetId], source: .photos, category: category)
    }

    func deleteScreenshotSingle(
        assetId: String,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        await performDelete(assetIds: [assetId], source: .screenshots, category: category)
    }

    func deleteVideoSingle(
        assetId: String,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        await performDelete(assetIds: [assetId], source: .videos, category: category)
    }

    func removeFromAnalyzedIndex(_ assetIds: Set<String>) {
        for id in assetIds {
            analyzedIndex.removeValue(forKey: id)
        }
        SimilarPersistence.deletePhotos(assetIds: Array(assetIds))
        persistScanSummary()
    }

    /// Drops an asset from EVERY in-memory list (photo groups, screenshot
    /// groups, video groups, analyzedIndex) and persists the pruned state —
    /// without invoking PHAssetChangeRequest.
    ///
    /// Called from cell views when a thumbnail load truly fails (the
    /// `loadThumbnail` retry chain in `PhotoKitService` already exhausted
    /// `.opportunistic` AND `.highQualityFormat`, so any nil that escapes
    /// is genuinely unrenderable). The cell signalling unloadable means the
    /// asset is either gone from the photo library OR permanently broken;
    /// either way it has no business sitting on screen as a gray skeleton
    /// claiming there's something to clean up.
    ///
    /// Idempotent — calling multiple times for the same id is a no-op after
    /// the first. Mirrors the existing `performDelete` bookkeeping so the
    /// UI re-renders cleanly: groups that drop below 2 items disappear,
    /// the persistence cache is updated, and the scan summary is rewritten.
    func pruneUnloadableAsset(_ assetId: String) {
        let id = assetId
        var touched = false

        // Subtract BEFORE the in-memory mutations below — the helper looks
        // up byte size from groups / analyzedIndex / scan results, which
        // are about to lose the row. If we waited, every lookup would
        // return 0 and the headline wouldn't decrement.
        subtractFromStableClutter(assetIds: [id])

        // Photo groups
        for gi in groups.indices {
            let before = groups[gi].items.count
            groups[gi].items.removeAll { $0.assetId == id }
            if groups[gi].items.count != before { touched = true }
        }
        let removedPhotoGroups = groups.filter { $0.items.count < 2 }.map(\.id)
        groups.removeAll { $0.items.count < 2 }

        // Screenshot groups
        for gi in screenshotGroups.indices {
            let before = screenshotGroups[gi].items.count
            screenshotGroups[gi].items.removeAll { $0.assetId == id }
            if screenshotGroups[gi].items.count != before { touched = true }
        }
        let removedScreenshotGroups = screenshotGroups.filter { $0.items.count < 2 }.map(\.id)
        screenshotGroups.removeAll { $0.items.count < 2 }

        // Video groups
        for gi in videoGroups.indices {
            let before = videoGroups[gi].items.count
            videoGroups[gi].items.removeAll { $0.assetId == id }
            if videoGroups[gi].items.count != before { touched = true }
        }
        let removedVideoGroups = videoGroups.filter { $0.items.count < 2 }.map(\.id)
        videoGroups.removeAll { $0.items.count < 2 }

        // Analyzed index — covers Other/Blurry which read from this map
        if analyzedIndex.removeValue(forKey: id) != nil { touched = true }

        // No work to do — bail before persistence so we don't churn the
        // cache for a no-op.
        guard touched else { return }

        // Persist. Mirror performDelete: drop the asset row, drop empty
        // groups, rewrite the scan summary so badge counts reflect reality
        // immediately on relaunch.
        SimilarPersistence.deletePhotos(assetIds: [id])
        if !removedPhotoGroups.isEmpty {
            SimilarPersistence.deleteGroups(ids: removedPhotoGroups)
        }
        if !removedScreenshotGroups.isEmpty {
            SimilarPersistence.deleteScreenshotGroups(ids: removedScreenshotGroups)
        }
        if !removedVideoGroups.isEmpty {
            SimilarPersistence.deleteVideoGroups(ids: removedVideoGroups)
        }
        persistScanSummary()
        // The dashboard cards bind to derived counts/byte totals/preview
        // IDs in `dashboardSnapshot`. A pruned asset ripples into every
        // bucket it might have appeared in (group preview, ungrouped
        // photos, blurry list), so the snapshot has to refresh whenever
        // any of those mutate — which is here.
        recomputeDashboardSnapshot()
    }

    // MARK: - Flat (ungrouped) multi-select delete
    // Shared entry point for the "flat" cleanup cards (Screenshots, Blurry,
    // Other, Screen Recordings, Short Videos, Long Videos). The caller passes
    // a category-specific `refresh` so the correct store slice is rebuilt
    // after deletion (e.g. `refreshShortVideoScanResult` vs
    // `removeFromAnalyzedIndex`). Progress + isDeleting flip here so the UI
    // can show the same progress bar used by the grouped flow.
    func deleteFlatAssets(
        assetIds: [String],
        category flatCategory: SavedFindSourceCategory? = nil,
        refresh: @MainActor () async -> Void
    ) async -> Bool {
        guard !assetIds.isEmpty else { return false }
        isDeleting = true
        deleteProgress = DeleteProgress(totalToDelete: assetIds.count, totalChunks: 1)

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        guard fetchResult.count > 0 else {
            isDeleting = false
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
        } catch {
            print("[Store] Flat delete failed: \(error)")
            isDeleting = false
            return false
        }

        let deletedSet = Set(assetIds)
        deleteProgress.deleted = deletedSet.count

        // Snapshot bytes BEFORE the subtract — the delta tells us how
        // many bytes the user just freed, which we forward to
        // HiveStatsManager so lifetimeBytesSaved + activity log reflect
        // it. `subtractFromStableClutter` doesn't return the delta, so
        // we read `stableClutterBytes` on either side instead.
        let bytesBefore = stableClutterBytes
        subtractFromStableClutter(assetIds: deletedSet)
        let bytesFreed = max(0, bytesBefore - stableClutterBytes)

        for id in deletedSet { analyzedIndex.removeValue(forKey: id) }
        SimilarPersistence.deletePhotos(assetIds: assetIds)

        await refresh()
        persistScanSummary()
        recomputeDashboardSnapshot()

        BeeViewModel.shared.registerCleanup(count: deletedSet.count, source: .photoDelete)
        // Lifetime stats + streak + backend activity-log entry. The
        // mascot reaction stays on `BeeViewModel`; the source of truth
        // for lifetime numbers lives in HiveStatsManager. Category
        // (when passed) lets the Progress chart's chip row filter the
        // timeline by source (Screenshots vs Other vs Blurred, etc).
        HiveStatsManager.shared.recordCleanup(
            action: "deletion",
            itemCount: deletedSet.count,
            bytesSaved: bytesFreed,
            category: flatCategory
        )

        isDeleting = false
        return true
    }

    private func performDelete(
        assetIds: [String],
        source: GroupSource,
        category: SavedFindSourceCategory? = nil
    ) async -> Bool {
        guard !assetIds.isEmpty else { return false }
        isDeleting = true
        deleteProgress = DeleteProgress(totalToDelete: assetIds.count, totalChunks: 1)

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        guard fetchResult.count > 0 else {
            isDeleting = false
            return false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
        } catch {
            print("[Store] Delete failed: \(error)")
            isDeleting = false
            return false
        }

        let deletedSet = Set(assetIds)
        deleteProgress.deleted = deletedSet.count

        // Stable-clutter bookkeeping — subtract before mutating the
        // source collections (helper reads sizes from them). Snapshot
        // bytes either side so we can pass the freed delta to
        // HiveStatsManager (lifetime + activity log).
        let bytesBefore = stableClutterBytes
        subtractFromStableClutter(assetIds: deletedSet)
        let bytesFreed = max(0, bytesBefore - stableClutterBytes)

        switch source {
        case .photos:
            for gi in groups.indices {
                groups[gi].items.removeAll { deletedSet.contains($0.assetId) }
            }
            groups.removeAll { $0.items.count < 2 }
        case .screenshots:
            for gi in screenshotGroups.indices {
                screenshotGroups[gi].items.removeAll { deletedSet.contains($0.assetId) }
            }
            screenshotGroups.removeAll { $0.items.count < 2 }
        case .videos:
            for gi in videoGroups.indices {
                videoGroups[gi].items.removeAll { deletedSet.contains($0.assetId) }
            }
            videoGroups.removeAll { $0.items.count < 2 }
        }

        for id in deletedSet { analyzedIndex.removeValue(forKey: id) }
        SimilarPersistence.deletePhotos(assetIds: assetIds)
        persistScanSummary()
        recomputeDashboardSnapshot()

        BeeViewModel.shared.registerCleanup(count: deletedSet.count, source: .photoDelete)
        // Tag the activity with the leaf category so the Progress
        // chip row can filter the timeline. When the caller passed an
        // explicit category, use it; otherwise infer from the
        // `GroupSource` — `.screenshots`/`.videos` always mean the
        // grouped Similar variants, but `.photos` is ambiguous
        // (Duplicates vs Similar Photos) so a nil category there just
        // falls into the "All" bucket on the chip row.
        HiveStatsManager.shared.recordCleanup(
            action: "deletion",
            itemCount: deletedSet.count,
            bytesSaved: bytesFreed,
            category: category ?? Self.defaultCategory(for: source)
        )

        isDeleting = false
        return true
    }

    /// Best-guess category from `GroupSource` when the caller didn't
    /// pass one explicitly. `.photos` is ambiguous — used by both
    /// Duplicates and Similar Photos — so we return nil and let it
    /// fall into the All bucket rather than mis-tagging.
    private static func defaultCategory(for source: GroupSource) -> SavedFindSourceCategory? {
        switch source {
        case .photos:      return nil
        case .screenshots: return .similarScreenshots
        case .videos:      return .similarVideos
        }
    }
}
