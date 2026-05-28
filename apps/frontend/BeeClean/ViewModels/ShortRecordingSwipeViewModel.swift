import Foundation

@MainActor
final class ShortRecordingSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.shortVideoScanResult.screenshots,
            startIndex: startIndex,
            mediaLabel: "recordings",
            accentColor: "categoryPurple",
            sourceCategory: .shortRecordings
        ) { [weak store] _ in
            await store?.refreshShortVideoScanResult()
        }
    }

    /// Month-scoped swipe deck. Mirrors BlurryPhotoSwipeViewModel.init(items:).
    init(store: SimilarPhotosStore, items: [ScreenshotAsset]) {
        super.init(
            items: items,
            startIndex: 0,
            mediaLabel: "recordings",
            accentColor: "categoryPurple",
            sourceCategory: .shortRecordings
        ) { [weak store] _ in
            await store?.refreshShortVideoScanResult()
        }
    }

    // Backwards-compatible property aliases
    var recordings: [ScreenshotAsset] { items }
    var currentRecording: ScreenshotAsset? { currentItem }
}
