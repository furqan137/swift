import Foundation

@MainActor
final class ScreenRecordingSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.screenRecordingScanResult.screenshots,
            startIndex: startIndex,
            mediaLabel: "recordings",
            accentColor: "categoryPurple",
            sourceCategory: .screenRecordings
        ) { [weak store] _ in
            await store?.refreshScreenRecordingScanResult()
        }
    }

    /// Month-scoped swipe deck. Mirrors BlurryPhotoSwipeViewModel.init(items:).
    init(store: SimilarPhotosStore, items: [ScreenshotAsset]) {
        super.init(
            items: items,
            startIndex: 0,
            mediaLabel: "recordings",
            accentColor: "categoryPurple",
            sourceCategory: .screenRecordings
        ) { [weak store] _ in
            await store?.refreshScreenRecordingScanResult()
        }
    }

    // Backwards-compatible property aliases
    var recordings: [ScreenshotAsset] { items }
    var currentRecording: ScreenshotAsset? { currentItem }
}
