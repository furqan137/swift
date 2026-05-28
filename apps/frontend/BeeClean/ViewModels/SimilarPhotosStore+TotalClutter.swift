import Foundation
import Photos

// MARK: - Total Clutter
extension SimilarPhotosStore {

    // MARK: Total Clutter

    /// Deduplicated bytes across every clutter category.
    ///
    /// The home cards intentionally overlap by design — a blurry photo can
    /// also be a duplicate, a similar-video clip is *also* a short or long
    /// video, etc. — so the user can delete any asset from whichever flow
    /// they prefer. But the "Space to Clean" headline number must be the
    /// UNION of those buckets, not the sum, or it inflates dramatically:
    ///
    ///   • Blurry photo in a Similar group → group bytes + blurry bytes
    ///   • Blurry photo not in a group     → ungrouped bytes + blurry bytes
    ///   • Short video in a Similar group  → video group bytes + short bytes
    ///   • Long video in a Similar group   → video group bytes + long bytes
    ///   • Screen recording in a Similar group → video group bytes + SR bytes
    ///
    /// All five overlaps were silently double-counted. The fix is to walk
    /// every clutter source once, keyed by asset identifier, and only add
    /// each asset's bytes the first time we see it.
    var totalClutterBytes: Int64 {
        // Single-pass dedup. Previous version called `ungroupedScreenshots`,
        // `ungroupedPhotos`, AND `blurryPhotos` — each rebuilt the
        // `groupedIds` Set from scratch and re-walked `analyzedIndex.values`
        // with its own filter+sort+map. Called from HomeView.body, this
        // re-ran on every render and was the main source of the Similar
        // Photos lag. Now we walk every source ONCE and skip the redundant
        // computed-property recursion entirely.
        var seen = Set<String>()
        var bytes: Int64 = 0

        @inline(__always) func add(_ id: String, _ size: Int64) {
            guard size > 0 else { return }
            if seen.insert(id).inserted { bytes += size }
        }

        // Similar / duplicate photo groups
        for group in groups {
            for item in group.items { add(item.assetId, item.fileSize) }
        }
        // Screenshot groups
        for group in screenshotGroups {
            for item in group.items { add(item.assetId, item.fileSize) }
        }
        // Video groups
        for group in videoGroups {
            for item in group.items { add(item.assetId, item.fileSize) }
        }
        // Ungrouped screenshots — `seen` already contains anything that
        // appeared in the screenshot groups above, so `add` short-circuits.
        for ss in screenshotScanResult.screenshots {
            add(ss.assetId, ss.fileSize)
        }
        // Walk analyzedIndex ONCE — covers BOTH ungrouped photos AND blurry
        // photos. Both previously walked the index independently with their
        // own filter+sort+map; dedup `seen` makes double-counting impossible.
        for photo in analyzedIndex.values {
            if PhotoAnalyzer.isMetadataOnly(photo) { continue }
            add(photo.assetIdentifier, Int64(photo.fileSize ?? 0))
        }
        // Screen recordings (overlaps videoGroups when SRs are similar)
        for sr in screenRecordingScanResult.screenshots {
            add(sr.assetId, sr.fileSize)
        }
        // Short videos
        for sv in shortVideoScanResult.screenshots {
            add(sv.assetId, sv.fileSize)
        }
        // Long videos
        for lv in longVideoScanResult.screenshots {
            add(lv.assetId, lv.fileSize)
        }

        return bytes
    }

    /// Legacy aggregate — true if any scan of any kind is in progress.
    /// Preserved so call sites using the old single flag keep working.
    var isScanning: Bool {
        isRunningFullScan
            || isScanningSimilarPhotos
            || isScanningScreenshots
            || isScanningSimilarVideos
            || isScanningScreenRecordings
            || isScanningShortVideos
            || isScanningLongVideos
    }

}

