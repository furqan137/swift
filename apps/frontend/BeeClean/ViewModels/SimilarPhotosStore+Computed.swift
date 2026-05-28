import Foundation
import Photos

// MARK: - Computed Properties
extension SimilarPhotosStore {

    var cacheIsStale: Bool { SimilarPersistence.isCacheStale() }

    /// True if the cache has a completed scan we can safely surface right now
    /// without blocking the user on a fresh scan.
    ///
    /// Why: Previously this also required `scanSummary.lastScanDate != nil`,
    /// which is only written when the *full* scan finishes. Killing the app
    /// mid-scan left analyzedIndex populated (it's flushed every 500 photos)
    /// but lastScanDate nil — so every relaunch retriggered runFullScan and
    /// the user saw "Scanning…" forever even though groups were cached. Now
    /// any persisted analysis is treated as usable cache; a silent
    /// incrementalRefresh runs in the background to top it up.
    var hasUsableCache: Bool {
        !analyzedIndex.isEmpty
    }

    var totalBytesSaved: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.bytesSaved }
    }

    var totalSelectedForDelete: Int {
        groups.reduce(0) { $0 + $1.selectedCount }
    }

    var groupCount: Int { groups.count }

    var duplicateGroups: [SimilarGroupVM] {
        groups.filter { $0.confidence >= 0.85 }
    }

    var screenshotGroupCount: Int { screenshotGroups.count }

    var totalScreenshotSelectedForDelete: Int {
        screenshotGroups.reduce(0) { $0 + $1.selectedCount }
    }

    var totalScreenshotBytesSaved: Int64 {
        screenshotGroups.reduce(Int64(0)) { $0 + $1.bytesSaved }
    }

    var videoGroupCount: Int { videoGroups.count }

    var totalVideoSelectedForDelete: Int {
        videoGroups.reduce(0) { $0 + $1.selectedCount }
    }

    var totalVideoBytesSaved: Int64 {
        videoGroups.reduce(Int64(0)) { $0 + $1.bytesSaved }
    }

    var screenRecordingCount: Int { screenRecordingScanResult.count }
    var screenRecordingTotalBytes: Int64 { screenRecordingScanResult.totalBytes }
    var shortVideoCount: Int { shortVideoScanResult.count }
    var shortVideoTotalBytes: Int64 { shortVideoScanResult.totalBytes }

    /// Cheap passthrough — the actual filter/walk happens once inside
    /// `recomputeDashboardSnapshot()`. Excludes BOTH screenshot groups AND
    /// regular similar/duplicate groups: a screenshot of a photo can end up
    /// in `groups` (because it's visually similar to the source photo), and
    /// without that exclusion it would appear in both Duplicates AND
    /// Ungrouped Screenshots.
    var ungroupedScreenshots: [ScreenshotAsset] { ungroupedScreenshotsCache }

    var ungroupedScreenshotBytes: Int64 {
        ungroupedScreenshotsCache.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    /// Cheap passthrough — populated by `recomputeDashboardSnapshot()`.
    var ungroupedPhotos: [ScreenshotAsset] { ungroupedPhotosCache }

    var ungroupedPhotoBytes: Int64 {
        ungroupedPhotosCache.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    // MARK: Source-App Filtered Photos
    //
    // Returns every analyzed photo tagged with the given source-app, newest
    // first. O(1) — reads from `sourceFilteredCache` which is materialized
    // inside `recomputeDashboardSnapshot()` during the same analyzedIndex
    // walk that builds the dashboard. No per-call filter/sort/map work.
    func assetsFrom(source: PhotoSource) -> [ScreenshotAsset] {
        sourceFilteredCache[source] ?? []
    }


    // MARK: Long Videos


    /// Min duration (exclusive) to qualify as a "long video" (> 60 seconds).
    /// Aligns with fetchLongVideos so short (≤60s) and long (>60s) together
    /// cover every non-screen-recording video with no gap and no overlap.
    static let longVideoMinDuration: TimeInterval = 60

    var longVideoCount: Int { longVideoScanResult.count }
    var longVideoTotalBytes: Int64 { longVideoScanResult.totalBytes }
}

