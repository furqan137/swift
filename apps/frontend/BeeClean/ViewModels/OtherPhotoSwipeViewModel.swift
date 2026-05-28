import Foundation

@MainActor
final class OtherPhotoSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.ungroupedPhotos,
            startIndex: startIndex,
            mediaLabel: "photos",
            accentColor: "categoryBlue",
            sourceCategory: .otherPhotos
        ) { [weak store] deletedIds in
            await store?.removeFromAnalyzedIndex(deletedIds)
        }
    }

    /// Month-scoped swipe — used when the user taps "Swipe Month" on a
    /// month section in the Other Photos grid. Lets them work through a
    /// single backlog month at a time without losing context to a 6,000-
    /// photo deck. Also reused by the source-app filtered cards
    /// ("Snapchat", "Instagram", etc.) on the Charging tab.
    init(store: SimilarPhotosStore, items: [ScreenshotAsset], startIndex: Int = 0) {
        super.init(
            items: items,
            startIndex: startIndex,
            mediaLabel: "photos",
            accentColor: "categoryBlue",
            sourceCategory: .otherPhotos
        ) { [weak store] deletedIds in
            await store?.removeFromAnalyzedIndex(deletedIds)
        }
    }

    // Backwards-compatible property aliases
    var photos: [ScreenshotAsset] { items }
    var hasMorePhotos: Bool { hasMore }
    var currentPhoto: ScreenshotAsset? { currentItem }
}
