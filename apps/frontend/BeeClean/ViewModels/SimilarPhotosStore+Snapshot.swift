import Foundation
import Photos


// MARK: - Dashboard Snapshot
//
// Pre-computed bundle of every value the home dashboard's 10 preview
// cards need: split duplicate/similar group counts, byte totals,
// preview asset IDs (first 6 per category), ungrouped photo / blurry
// / screenshot lists, and the deduplicated total clutter bytes.
//
// Why: ChargingView used to read each of these as separate computed
// properties on the store — and several read EACH OTHER (e.g.
// `ungroupedPhotoBytes` re-walked `ungroupedPhotos`, which itself
// walked `analyzedIndex.values` with its own filter+sort+map). With
// 4500+ photos in the index, every body invalidation re-walked the
// whole library 5–10 times across the cards. Compute-once, cache-as-
// snapshot turns each render into an O(1) struct read.
//
// Refresh contract: the snapshot is rebuilt by
// `recomputeDashboardSnapshot()`. Call sites that mutate ANY input
// (groups, screenshotGroups, videoGroups, analyzedIndex,
// realScreenshotIds, screenshotScanResult, screenRecordingScanResult,
// shortVideoScanResult, longVideoScanResult) must trigger a recompute
// — see the `applyScanResult`, `loadFromCache`, `incrementalRefresh`,
// per-category scan, and prune call sites. The snapshot is a pure
// function of those inputs; reading it never triggers work.
struct DashboardSnapshot: Equatable {
    static let empty = DashboardSnapshot()

    // Photos tab — group-level
    var duplicateGroupCount: Int = 0
    var duplicateBytes: Int64 = 0
    var duplicatePreviewIds: [String] = []

    var similarGroupCount: Int = 0
    var similarBytes: Int64 = 0
    var similarPreviewIds: [String] = []

    var screenshotGroupCount: Int = 0
    var screenshotGroupBytes: Int64 = 0
    var screenshotGroupPreviewIds: [String] = []

    // Photos tab — flat
    var ungroupedScreenshotCount: Int = 0
    var ungroupedScreenshotBytes: Int64 = 0
    var ungroupedScreenshotPreviewIds: [String] = []

    var blurryCount: Int = 0
    var blurryBytes: Int64 = 0
    var blurryPreviewIds: [String] = []

    var ungroupedPhotoCount: Int = 0
    var ungroupedPhotoBytes: Int64 = 0
    var ungroupedPhotoPreviewIds: [String] = []

    // Videos tab
    var videoGroupCount: Int = 0
    var videoGroupBytes: Int64 = 0
    var videoGroupPreviewIds: [String] = []

    var screenRecordingCount: Int = 0
    var screenRecordingBytes: Int64 = 0
    var screenRecordingPreviewIds: [String] = []

    var shortVideoCount: Int = 0
    var shortVideoBytes: Int64 = 0
    var shortVideoPreviewIds: [String] = []

    var longVideoCount: Int = 0
    var longVideoBytes: Int64 = 0
    var longVideoPreviewIds: [String] = []

    // Aggregate (replaces store.totalClutterBytes for dashboard reads)
    var totalClutterBytes: Int64 = 0

    // Per-source aggregates — drive the "Cleanup by App" dashboard row.
    // One entry per source the user actually has assets from (no rows for
    // sources with zero hits). Preview IDs cap at 6 to match the existing
    // dashboard card layout.
    var sourceCardCounts: [PhotoSource: Int] = [:]
    var sourceCardBytes: [PhotoSource: Int64] = [:]
    var sourceCardPreviewIds: [PhotoSource: [String]] = [:]
}

// MARK: - Dashboard Snapshot Recomputation
extension SimilarPhotosStore {

    // MARK: - Dashboard Snapshot Recomputation
    //
    // Called from every mutation site that touches the inputs to the
    // home dashboard cards. Walks each input array EXACTLY once and
    // bundles the per-card derived values into a single
    // `DashboardSnapshot`, which the view tree reads in O(1).
    //
    // Previously each preview card on ChargingView read 4-6 separate
    // computed properties — `groups.filter { … }.count`,
    // `groups.filter { … }.reduce(...)`, `prefix(6).map(\.bestId)`,
    // plus `ungroupedPhotos`, `blurryPhotos`, `ungroupedScreenshots`
    // each of which independently re-walked `analyzedIndex.values`
    // (4500+ entries) with its own filter+sort+map. That came out to
    // ~60-80 array walks per body invalidation across the 10 cards.
    // With the snapshot approach the card body is pure read.
    func recomputeDashboardSnapshot() {
        // 1. Walk `groups` ONCE — split by confidence threshold the
        //    canonical way (>= 0.85 → duplicate, < 0.85 → similar).
        //    Accumulate counts, byte sums, and the first 6 best IDs
        //    per bucket as we go, so the previews don't need a second
        //    pass.
        var dupCount = 0
        var simCount = 0
        var dupBytes: Int64 = 0
        var simBytes: Int64 = 0
        var dupPreviews: [String] = []
        var simPreviews: [String] = []
        dupPreviews.reserveCapacity(6)
        simPreviews.reserveCapacity(6)
        for group in groups {
            if group.confidence >= 0.85 {
                dupCount += 1
                dupBytes += group.totalBytes
                if dupPreviews.count < 6 { dupPreviews.append(group.bestId) }
            } else {
                simCount += 1
                simBytes += group.totalBytes
                if simPreviews.count < 6 { simPreviews.append(group.bestId) }
            }
        }

        // 2. Screenshot groups
        var ssGroupBytes: Int64 = 0
        var ssGroupPreviews: [String] = []
        ssGroupPreviews.reserveCapacity(6)
        for group in screenshotGroups {
            ssGroupBytes += group.totalBytes
            if ssGroupPreviews.count < 6 { ssGroupPreviews.append(group.bestId) }
        }

        // 3. Video groups
        var videoGroupBytes: Int64 = 0
        var videoGroupPreviews: [String] = []
        videoGroupPreviews.reserveCapacity(6)
        for group in videoGroups {
            videoGroupBytes += group.totalBytes
            if videoGroupPreviews.count < 6 { videoGroupPreviews.append(group.bestId) }
        }

        // 4. Build the union of every "this asset is already in a
        //    group" id set ONCE so the flat-list walks below can do
        //    O(1) lookups instead of rebuilding the set per category.
        var groupedAssetIds = Set<String>()
        for group in groups {
            for item in group.items { groupedAssetIds.insert(item.assetId) }
        }
        var ssGroupedIds = Set<String>()
        for group in screenshotGroups {
            for item in group.items { ssGroupedIds.insert(item.assetId) }
        }
        let regularGroupedIds = groupedAssetIds  // alias for clarity

        // 5. Ungrouped Screenshots — walk screenshotScanResult.screenshots ONCE.
        //    Excludes anything already in a screenshot group OR a regular
        //    similar/duplicate group (a screenshot of a photo can land in
        //    `groups`, and we don't want it double-listed in the flat
        //    Screenshots card).
        var ungroupedScreenshotCount = 0
        var ungroupedScreenshotBytes: Int64 = 0
        var ungroupedScreenshotPreviews: [String] = []
        ungroupedScreenshotPreviews.reserveCapacity(6)
        var ungroupedScreenshotFull: [ScreenshotAsset] = []
        ungroupedScreenshotFull.reserveCapacity(screenshotScanResult.screenshots.count)
        for ss in screenshotScanResult.screenshots {
            if ssGroupedIds.contains(ss.assetId) { continue }
            if regularGroupedIds.contains(ss.assetId) { continue }
            ungroupedScreenshotCount += 1
            ungroupedScreenshotBytes += ss.fileSize
            if ungroupedScreenshotPreviews.count < 6 {
                ungroupedScreenshotPreviews.append(ss.assetId)
            }
            ungroupedScreenshotFull.append(ss)
        }
        ungroupedScreenshotsCache = ungroupedScreenshotFull

        // 6. analyzedIndex walk — feeds BOTH Blurry and Other Photos in
        //    one pass. Compared with the previous build, where
        //    `blurryPhotos` and `ungroupedPhotos` each walked
        //    `analyzedIndex.values` independently with their own
        //    filter+sort+map, this is the single most valuable
        //    optimization in this whole snapshot. Sorting is deferred:
        //    we collect candidates into per-bucket arrays and sort each
        //    bucket once at the end, then take the first 6 IDs.
        let blurryKeptIds = LocalKeptStore.shared.ids(in: .blurryPhotos)
        var blurryCandidates: [AnalyzedPhoto] = []
        var ungroupedCandidates: [AnalyzedPhoto] = []
        blurryCandidates.reserveCapacity(min(64, analyzedIndex.count))
        ungroupedCandidates.reserveCapacity(min(256, analyzedIndex.count))
        let excludedFromUngrouped = groupedAssetIds.union(ssGroupedIds).union(realScreenshotIds)

        // Per-source aggregates accumulated in the same walk — adds 3
        // cheap dictionary writes per photo, no second pass over the index.
        // Also bucket the full AnalyzedPhoto so the per-source detail grids
        // get an O(1) cache read instead of re-filtering the index on each
        // grid open.
        var sourceCounts: [PhotoSource: Int] = [:]
        var sourceBytes: [PhotoSource: Int64] = [:]
        var sourcePreviewIds: [PhotoSource: [String]] = [:]
        var sourceFiltered: [PhotoSource: [AnalyzedPhoto]] = [:]

        for photo in analyzedIndex.values {
            // Blurry — independent of group membership; the user can
            // still surface a blurry photo from this card even if it's
            // also a duplicate elsewhere.
            if passesBlurryFilter(photo, groupedIds: groupedAssetIds),
               !blurryKeptIds.contains(photo.assetIdentifier) {
                blurryCandidates.append(photo)
            }
            // Ungrouped Other Photos — must NOT be in any group AND
            // must NOT be a real screenshot (those live on the
            // Screenshots card).
            if !excludedFromUngrouped.contains(photo.assetIdentifier) {
                ungroupedCandidates.append(photo)
            }
            // Source-app bucket — only count assets with a detected
            // external source. `.camera` and `nil` (not yet detected)
            // don't contribute to any per-source card.
            if let source = photo.sourceApp, source.isExternal {
                sourceCounts[source, default: 0] += 1
                sourceBytes[source, default: 0] += Int64(photo.fileSize ?? 0)
                if sourcePreviewIds[source, default: []].count < 6 {
                    sourcePreviewIds[source, default: []].append(photo.assetIdentifier)
                }
                sourceFiltered[source, default: []].append(photo)
            }
        }

        // Materialize the per-source cache. Sort each bucket once
        // (newest-first) and map to `ScreenshotAsset` — same shape the
        // detail-grid + swipe deck consume. With ~6 source buckets, this
        // is bounded work even on huge libraries.
        var sourceFilteredAssets: [PhotoSource: [ScreenshotAsset]] = [:]
        for (source, photos) in sourceFiltered {
            sourceFilteredAssets[source] = photos
                .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                .map { photo in
                    ScreenshotAsset(
                        assetId: photo.assetIdentifier,
                        creationDate: photo.creationDate,
                        pixelWidth: photo.pixelWidth,
                        pixelHeight: photo.pixelHeight,
                        fileSize: photo.fileSize ?? 0,
                        sourceApp: source
                    )
                }
        }
        sourceFilteredCache = sourceFilteredAssets

        // Blurry sort — ascending sharpness so worst-first lands at top.
        blurryCandidates.sort { $0.sharpnessScore < $1.sharpnessScore }
        let blurryCount = blurryCandidates.count
        let blurryBytes = blurryCandidates.reduce(Int64(0)) { $0 + Int64($1.fileSize ?? 0) }
        let blurryPreviews = Array(blurryCandidates.prefix(6).map(\.assetIdentifier))
        // Full-list cache — detail grid + swipe deck read this instead of
        // re-walking the candidate list. Matches the legacy `blurryPhotos`
        // computed shape so call sites are drop-in replaced.
        blurryPhotosCache = blurryCandidates.map { photo in
            ScreenshotAsset(
                assetId: photo.assetIdentifier,
                creationDate: photo.creationDate,
                pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight,
                fileSize: photo.fileSize ?? 0
            )
        }

        // Ungrouped sort — descending creationDate so most recent first.
        ungroupedCandidates.sort {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
        let ungroupedPhotoCount = ungroupedCandidates.count
        let ungroupedPhotoBytes = ungroupedCandidates.reduce(Int64(0)) { $0 + Int64($1.fileSize ?? 0) }
        let ungroupedPhotoPreviews = Array(ungroupedCandidates.prefix(6).map(\.assetIdentifier))
        ungroupedPhotosCache = ungroupedCandidates.map { photo in
            ScreenshotAsset(
                assetId: photo.assetIdentifier,
                creationDate: photo.creationDate,
                pixelWidth: photo.pixelWidth,
                pixelHeight: photo.pixelHeight,
                fileSize: photo.fileSize ?? 0
            )
        }

        // 7. Per-category video previews — first 6 IDs from each scan
        //    result. counts + bytes already live on each
        //    `ScreenshotScanResult` so no walk needed.
        let screenRecordingPreviews = Array(screenRecordingScanResult.screenshots.prefix(6).map(\.assetId))
        let shortVideoPreviews = Array(shortVideoScanResult.screenshots.prefix(6).map(\.assetId))
        let longVideoPreviews = Array(longVideoScanResult.screenshots.prefix(6).map(\.assetId))

        // 8. Stable clutter bytes — DELTA tracked, not re-summed.
        //
        // Walk every clutter source once and accumulate bytes ONLY for
        // asset IDs we haven't already counted toward `stableClutterBytes`.
        // This is the contract that makes the "Space to Clean" headline
        // stay static instead of jittering every time clustering finds a
        // different grouping or the user re-enters the home tab. See the
        // comment block on `stableClutterBytes` in SimilarPhotosStore for
        // the full behavior contract.
        //
        // NOTE: subtraction lives in `subtractFromStableClutter`, called
        // from the deletion paths. It MUST NOT happen here — recomputes
        // fire on every refresh tick and we'd undo the user's "static
        // unless cleaned" mental model.
        var addedBytes: Int64 = 0
        var seenForClutter = Set<String>()
        @inline(__always) func considerClutter(_ id: String, _ size: Int64) {
            guard size > 0 else { return }
            // Dedup within this walk — duplicates / similar / blurry can
            // cross-list the same asset.
            guard seenForClutter.insert(id).inserted else { return }
            // Only NEW (never-counted) ids contribute to the headline.
            if !clutterCountedIds.contains(id) {
                clutterCountedIds.insert(id)
                addedBytes += size
            }
        }
        for group in groups {
            for item in group.items { considerClutter(item.assetId, item.fileSize) }
        }
        for group in screenshotGroups {
            for item in group.items { considerClutter(item.assetId, item.fileSize) }
        }
        for group in videoGroups {
            for item in group.items { considerClutter(item.assetId, item.fileSize) }
        }
        for ss in screenshotScanResult.screenshots {
            considerClutter(ss.assetId, ss.fileSize)
        }
        for photo in analyzedIndex.values {
            if PhotoAnalyzer.isMetadataOnly(photo) { continue }
            considerClutter(photo.assetIdentifier, Int64(photo.fileSize ?? 0))
        }
        for sr in screenRecordingScanResult.screenshots {
            considerClutter(sr.assetId, sr.fileSize)
        }
        for sv in shortVideoScanResult.screenshots {
            considerClutter(sv.assetId, sv.fileSize)
        }
        for lv in longVideoScanResult.screenshots {
            considerClutter(lv.assetId, lv.fileSize)
        }
        if addedBytes > 0 {
            stableClutterBytes += addedBytes
            StableClutterPersistence.save(bytes: stableClutterBytes, ids: clutterCountedIds)
        }
        let clutterBytes = stableClutterBytes

        // 9. Assemble the snapshot. Single struct write triggers
        //    @Observable observers exactly once.
        dashboardSnapshot = DashboardSnapshot(
            duplicateGroupCount: dupCount,
            duplicateBytes: dupBytes,
            duplicatePreviewIds: dupPreviews,
            similarGroupCount: simCount,
            similarBytes: simBytes,
            similarPreviewIds: simPreviews,
            screenshotGroupCount: screenshotGroups.count,
            screenshotGroupBytes: ssGroupBytes,
            screenshotGroupPreviewIds: ssGroupPreviews,
            ungroupedScreenshotCount: ungroupedScreenshotCount,
            ungroupedScreenshotBytes: ungroupedScreenshotBytes,
            ungroupedScreenshotPreviewIds: ungroupedScreenshotPreviews,
            blurryCount: blurryCount,
            blurryBytes: blurryBytes,
            blurryPreviewIds: blurryPreviews,
            ungroupedPhotoCount: ungroupedPhotoCount,
            ungroupedPhotoBytes: ungroupedPhotoBytes,
            ungroupedPhotoPreviewIds: ungroupedPhotoPreviews,
            videoGroupCount: videoGroups.count,
            videoGroupBytes: videoGroupBytes,
            videoGroupPreviewIds: videoGroupPreviews,
            screenRecordingCount: screenRecordingScanResult.count,
            screenRecordingBytes: screenRecordingScanResult.totalBytes,
            screenRecordingPreviewIds: screenRecordingPreviews,
            shortVideoCount: shortVideoScanResult.count,
            shortVideoBytes: shortVideoScanResult.totalBytes,
            shortVideoPreviewIds: shortVideoPreviews,
            longVideoCount: longVideoScanResult.count,
            longVideoBytes: longVideoScanResult.totalBytes,
            longVideoPreviewIds: longVideoPreviews,
            totalClutterBytes: clutterBytes,
            sourceCardCounts: sourceCounts,
            sourceCardBytes: sourceBytes,
            sourceCardPreviewIds: sourcePreviewIds
        )
    }
}

