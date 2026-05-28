import Foundation

/// Tinder-style swipe deck scoped to a single similarity group.
///
/// Builds on `MediaSwipeViewModel` (the same engine that powers the
/// Other Photos / Blurry / Screenshots swipe flows) but operates on a
/// fixed snapshot of a group's items. Swipe-left marks the photo for
/// deletion; the existing review-and-delete UX commits the actual
/// PHAssetChangeRequest. After a successful delete, `onDeleted`
/// prunes the assets from the relevant group + analyzedIndex so the
/// list views update without a full rescan.
@MainActor
final class GroupSwipeViewModel: MediaSwipeViewModel {
    init(
        store: SimilarPhotosStore,
        groupId: UUID,
        source: SimilarPhotosStore.GroupSource,
        items: [SimilarGroupItem]
    ) {
        // SimilarGroupItem → ScreenshotAsset adapter. The swipe deck only
        // needs assetId + fileSize; pixel dims and creationDate aren't
        // surfaced by the swipe UI, so zero/nil placeholders are fine.
        let assetItems: [ScreenshotAsset] = items.map { item in
            ScreenshotAsset(
                assetId: item.assetId,
                creationDate: nil,
                pixelWidth: 0,
                pixelHeight: 0,
                fileSize: item.fileSize
            )
        }

        let label: String
        let accent: String
        let category: SavedFindSourceCategory
        switch source {
        case .photos:
            // Ambiguous between .duplicates and .similarPhotos here —
            // the group source alone can't tell us. Default to
            // .similarPhotos since the GroupSwipe surface is reached
            // almost exclusively from Similar (Duplicates uses a
            // bulk-confirm flow, not the per-card swipe deck).
            label = "photos"
            accent = "categoryViolet"
            category = .similarPhotos
        case .screenshots:
            label = "screenshots"
            accent = "categoryTeal"
            category = .similarScreenshots
        case .videos:
            label = "videos"
            accent = "categoryCrimson"
            category = .similarVideos
        }

        super.init(
            items: assetItems,
            startIndex: 0,
            mediaLabel: label,
            accentColor: accent,
            sourceCategory: category
        ) { [weak store] deletedIds in
            // Prune deleted assets from EVERY in-memory group + analyzedIndex.
            // pruneUnloadableAsset already does the right bookkeeping (drops
            // groups < 2 items, persists, refreshes summary).
            //
            // [weak store] is duplicated on the inner MainActor.run closure
            // — without that, Swift 6 strict concurrency reads it as a var
            // capture from the outer closure ferrying across actor hops and
            // warns. Per-closure weak captures decouple the two.
            await MainActor.run { [weak store] in
                guard let store else { return }
                for id in deletedIds {
                    store.pruneUnloadableAsset(id)
                }
                store.removeFromAnalyzedIndex(deletedIds)
            }
        }
    }
}
