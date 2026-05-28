import Foundation

@MainActor
final class LongVideoSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.longVideoScanResult.screenshots,
            startIndex: startIndex,
            mediaLabel: "long videos",
            accentColor: "categoryAmber",
            keptNamespace: .longVideos,
            sourceCategory: .longVideos
        ) { [weak store] _ in
            // Kept state persists on-device — no backend reporting.
            await store?.refreshLongVideoScanResult()
        }
    }

    /// Month-scoped swipe deck. Mirrors BlurryPhotoSwipeViewModel.init(items:).
    init(store: SimilarPhotosStore, items: [ScreenshotAsset]) {
        super.init(
            items: items,
            startIndex: 0,
            mediaLabel: "long videos",
            accentColor: "categoryAmber",
            keptNamespace: .longVideos,
            sourceCategory: .longVideos
        ) { [weak store] _ in
            await store?.refreshLongVideoScanResult()
        }
    }

    // Backwards-compatible property aliases
    var recordings: [ScreenshotAsset] { items }
    var currentRecording: ScreenshotAsset? { currentItem }
}
