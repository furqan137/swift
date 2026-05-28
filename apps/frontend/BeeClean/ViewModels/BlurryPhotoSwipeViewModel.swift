import Foundation

@MainActor
final class BlurryPhotoSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.blurryPhotos,
            startIndex: startIndex,
            mediaLabel: "blurry photos",
            accentColor: "categoryRose",
            keptNamespace: .blurryPhotos,
            sourceCategory: .blurredPhotos
        ) { [weak store] deletedIds in
            // Kept state persists on-device — no backend reporting.
            await store?.removeFromAnalyzedIndex(deletedIds)
        }
    }

    /// Month-scoped swipe — see OtherPhotoSwipeViewModel.init(items:) for
    /// the rationale.
    init(store: SimilarPhotosStore, items: [ScreenshotAsset]) {
        super.init(
            items: items,
            startIndex: 0,
            mediaLabel: "blurry photos",
            accentColor: "categoryRose",
            keptNamespace: .blurryPhotos,
            sourceCategory: .blurredPhotos
        ) { [weak store] deletedIds in
            await store?.removeFromAnalyzedIndex(deletedIds)
        }
    }
}
