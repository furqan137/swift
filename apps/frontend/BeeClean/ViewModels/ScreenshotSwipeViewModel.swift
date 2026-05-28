import Foundation

@MainActor
final class ScreenshotSwipeViewModel: MediaSwipeViewModel {
    init(store: SimilarPhotosStore, startIndex: Int = 0) {
        super.init(
            items: store.ungroupedScreenshots,
            startIndex: startIndex,
            mediaLabel: "screenshots",
            accentColor: "categoryOrange",
            sourceCategory: .screenshots
        ) { [weak store] _ in
            await store?.refreshScreenshotScanResult()
        }
    }

    /// Month-scoped swipe — see OtherPhotoSwipeViewModel.init(items:) for
    /// the rationale.
    init(store: SimilarPhotosStore, items: [ScreenshotAsset]) {
        super.init(
            items: items,
            startIndex: 0,
            mediaLabel: "screenshots",
            accentColor: "categoryOrange",
            sourceCategory: .screenshots
        ) { [weak store] _ in
            await store?.refreshScreenshotScanResult()
        }
    }

    // Backwards-compatible property aliases
    var screenshots: [ScreenshotAsset] { items }
    var hasMoreScreenshots: Bool { hasMore }
    var currentScreenshot: ScreenshotAsset? { currentItem }
}
