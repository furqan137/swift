import Foundation
import Photos

@MainActor @Observable
final class SimilarPhotosStore {

    // MARK: - Display State
    // Access is `internal` (default) across the board so extension files
    // (+Scanning, +Cache, +Selection, +Deletion) can mutate these.
    // Previously several were `private(set)` but Swift extensions in separate
    // files can't write through a file-private setter.
    var groups: [SimilarGroupVM] = []
    var screenshotGroups: [SimilarGroupVM] = []
    var videoGroups: [SimilarGroupVM] = []
    var scanSummary: ScanSummary = .empty
    var duplicateScanResult: DuplicateScanResult = .empty
    var screenshotScanResult: ScreenshotScanResult = .empty
    var screenRecordingScanResult: ScreenshotScanResult = .empty
    var shortVideoScanResult: ScreenshotScanResult = .empty
    var longVideoScanResult: ScreenshotScanResult = .empty

    // MARK: - Scan State
    //
    // Per-category scanning flags — set ONLY by the matching per-category scan
    // method. Each category-specific view (e.g. SimilarVideosView) reads its
    // matching flag so tapping "Scan Videos" never makes other categories
    // appear to be scanning.
    var isScanningSimilarPhotos = false
    var isScanningScreenshots = false
    var isScanningSimilarVideos = false
    var isScanningScreenRecordings = false
    var isScanningShortVideos = false
    var isScanningLongVideos = false

    /// Set while `runFullScan()` is running (global "Scan All" + auto-scan on
    /// ChargingView load). When true, all category cards should show scanning.
    /// IMPORTANT: this gets cleared as soon as photo *analysis* completes
    /// (i.e. `analyzedIndex` is built), NOT when clustering finishes. The
    /// non-clustering cards (Other Photos / Screenshots / Blurry / Recordings
    /// / Long / Short) populate from analyzedIndex + smart-album fetches and
    /// can show real counts the moment analysis is done. Clustering keeps
    /// running in the background and is gated by the more granular
    /// `isClusteringPhotos / Screenshots / Videos` flags below.
    var isRunningFullScan = false

    /// Granular clustering flags — true while the matching clustering pass
    /// is still running. Wired into the four clustering-dependent cards
    /// (Duplicates, Similar Photos, Similar Screenshots, Similar Videos) so
    /// they show "Scanning…" only while the work that powers THEM is in
    /// flight, instead of being blocked behind the entire scan pipeline.
    var isClusteringPhotos = false
    var isClusteringScreenshots = false
    var isClusteringVideos = false

    var isRefreshing = false
    var progress: PhotoAnalysisProgress = .init()
    var error: String?
    var loadedFromCache = false

    // Set while `loadFromCache()` has a background disk-read in flight, so
    // that 5 detail views appearing in quick succession (Cleanup → tap card
    // → back → tap another card) don't fire 5 concurrent JSON-decode storms
    // on the same files. The first caller does the work; subsequent callers
    // return immediately and pick up the results via @Observable updates.
    var isLoadingFromCache = false

    // MARK: - Delete State
    var isDeleting = false
    var deleteProgress: DeleteProgress = .init()

    /// True once a full scan has completed at least once this session.
    var hasCompletedScan = false

    // MARK: - Internal (accessed by extension files)
    var analyzedIndex: [String: AnalyzedPhoto] = [:]
    var realScreenshotIds: Set<String> = []
    let photoService = PhotoKitService.shared
    let statsManager = HiveStatsManager.shared

    /// Pre-computed dashboard derivations — split duplicate/similar
    /// counts, preview IDs, ungrouped-photo / blurry / screenshot lists,
    /// total clutter bytes. Read by ChargingView's preview cards
    /// instead of the per-property computed walks. See
    /// `DashboardSnapshot` for the schema and `recomputeDashboardSnapshot()`
    /// for the rebuild contract — every mutation of `groups`,
    /// `screenshotGroups`, `videoGroups`, `analyzedIndex`,
    /// `realScreenshotIds`, or any of the per-category ScanResults must
    /// call recompute so the snapshot stays consistent with its inputs.
    var dashboardSnapshot: DashboardSnapshot = .empty

    // Full-list caches populated by `recomputeDashboardSnapshot()` alongside
    // the dashboard snapshot. The detail-grid + swipe-deck call sites read
    // these instead of re-walking `analyzedIndex.values` (and re-filtering /
    // re-sorting / re-mapping) on every grid appear or post-delete refresh.
    // Same freshness contract as `dashboardSnapshot` — invalidated exclusively
    // by the recompute call.
    var ungroupedPhotosCache: [ScreenshotAsset] = []
    var blurryPhotosCache: [ScreenshotAsset] = []
    var ungroupedScreenshotsCache: [ScreenshotAsset] = []

    // Per-source full-list cache. Mirrors the pattern above for the
    // dedicated "Snapchat / Instagram / WhatsApp / etc." dashboard cards
    // and their detail grids. Tapping a per-source card opens a grid that
    // reads from `assetsFrom(source:)` — without this cache that call
    // would re-filter `analyzedIndex.values` on every grid open and
    // post-delete refresh. With the cache it's an O(1) dictionary lookup.
    // Built in the same single analyzedIndex walk that produces the
    // blurry / ungrouped caches above, so there's no extra pass.
    var sourceFilteredCache: [PhotoSource: [ScreenshotAsset]] = [:]

    // MARK: - Stable Clutter Tracking
    //
    // The "Space to Clean" headline is a STABLE, monotonic value — it must
    // not jitter when scans re-run or when clustering finds different
    // groupings on subsequent passes. Behavior contract:
    //
    //   • First scan: every clutter asset's bytes are added; baseline set.
    //   • Library change → new asset arrives: ONLY the new asset's bytes
    //     are added (delta), so the headline grows.
    //   • Library change → asset deleted from camera roll directly (not
    //     via this app): NO change. The headline stays static — that's
    //     the user's mental model of "the amount to clean."
    //   • In-app delete (performDelete / deleteFlatAssets / pruneUnloadable):
    //     the deleted asset's bytes are SUBTRACTED before the recompute,
    //     so the headline shrinks by exactly what the user just cleaned.
    //
    // Persisted across launches via UserDefaults so the value survives a
    // fresh app launch — otherwise every cold start would rebuild the
    // baseline from the current library, which means an external delete
    // between sessions would silently shrink the number (the very
    // behavior we're trying to eliminate).
    var stableClutterBytes: Int64 = StableClutterPersistence.loadBytes()
    var clutterCountedIds: Set<String> = StableClutterPersistence.loadIds()

    // MARK: - Stable Clutter Persistence (UserDefaults-backed)
    //
    // Inlined into the store file because the Xcode project's build phase
    // is hand-edited and adding a new top-level Swift file requires
    // updating project.pbxproj. Inlining keeps the addition to existing
    // tracked files.
    enum StableClutterPersistence {
        static let bytesKey = "bc.stableClutter.bytes"
        static let idsKey = "bc.stableClutter.ids"

        static func loadBytes() -> Int64 {
            (UserDefaults.standard.object(forKey: bytesKey) as? NSNumber)?.int64Value ?? 0
        }

        static func loadIds() -> Set<String> {
            guard let data = UserDefaults.standard.data(forKey: idsKey),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(arr)
        }

        static func save(bytes: Int64, ids: Set<String>) {
            UserDefaults.standard.set(NSNumber(value: bytes), forKey: bytesKey)
            if let data = try? JSONEncoder().encode(Array(ids)) {
                UserDefaults.standard.set(data, forKey: idsKey)
            }
        }
    }

    func subtractFromStableClutter(assetIds: Set<String>) {
        // Sizes were captured at scan time and cached on the AnalyzedPhoto /
        // ScreenshotAsset rows the snapshot walked. Pull each id's known
        // size from the live state BEFORE the deletion path removes it.
        var byteDelta: Int64 = 0
        for id in assetIds where clutterCountedIds.contains(id) {
            byteDelta += sizeForCountedClutterAsset(id)
            clutterCountedIds.remove(id)
        }
        stableClutterBytes = max(0, stableClutterBytes - byteDelta)
        StableClutterPersistence.save(bytes: stableClutterBytes, ids: clutterCountedIds)
    }

    /// Looks up the source-app classification for an asset by id. Reads
    /// from `analyzedIndex` — populated by Tier 1 filename detection
    /// inline during the similar-photos scan and by Tier 2 EXIF
    /// enrichment in the background sweep. Used by the Compress flow's
    /// `PhotoCompressCard` / `VideoCompressCard` so the SocialSourceBadge
    /// they render reflects the same provenance the rest of the app
    /// uses — Instagram in particular only surfaces via Tier 2 EXIF
    /// (filenames are `IMG_XXXX.jpg`), which the Compress loader doesn't
    /// run on its own.
    ///
    /// Returns nil when:
    ///   • The asset hasn't been indexed yet (similar scan hasn't run /
    ///     bootstrap still loading).
    ///   • The asset was indexed but no source was detected — falls
    ///     through to the caller's local (Tier 1 filename) field.
    func sourceApp(for assetId: String) -> PhotoSource? {
        analyzedIndex[assetId]?.sourceApp ?? liveSourceCache[assetId]
    }

    /// On-demand source cache populated by `requestSourceClassification`.
    /// Read first by `sourceApp(for:)` so a tile that fired its lazy
    /// classification but isn't yet folded into `analyzedIndex` (which
    /// is rebuilt by the full similar-photos scan) still surfaces its
    /// badge the instant Tier 2 lands. `@Observable` propagates the
    /// mutation, so the SocialSourceBadge auto-refreshes.
    var liveSourceCache: [String: PhotoSource] = [:]

    /// In-flight asset ids — dedup guard so a fast scroll past 200 tiles
    /// doesn't queue 200 redundant Vision passes for the same asset.
    /// Cleared per asset when classification completes.
    private var classifyingIds: Set<String> = []

    /// Lazy per-tile source classification. Called from compress / grid
    /// cells via `.task` so the work runs only for assets the user has
    /// actually scrolled to. Idempotent — repeated calls for the same
    /// asset short-circuit on the cache or in-flight set. Heavy enough
    /// to never run sync on the view body; light enough that the first
    /// 100ms after a tile appears almost always produces a badge.
    ///
    /// Tier sequence
    ///   1. Filename — sub-millisecond, runs on the caller's thread.
    ///   2. EXIF Software tag — ~5–10ms, off-main inside a detached task.
    ///   3. Visual classification (Vision) — ~50ms, only if Tier 1 + 2
    ///      both miss. Conservative scoring inside VisualSourceClassifier
    ///      keeps false-positives low.
    func requestSourceClassification(assetId: String, asset: PHAsset? = nil) {
        if sourceApp(for: assetId) != nil { return }
        if classifyingIds.contains(assetId) { return }
        // Caller-supplied PHAsset is a fast path (compress cards already
        // hold one). If absent, the detached task resolves it via a
        // single `fetchAssets(withLocalIdentifiers:)` round-trip so
        // MediaGridView cells (which only carry `assetId`) can still
        // light up their badges without plumbing PHAsset through the
        // grid model.
        classifyingIds.insert(assetId)
        let providedAsset = asset
        // EVERY tier runs off the main actor — even Tier 1's
        // `PHAssetResource.assetResources` is a Core Data hit that can
        // stutter a fast scroll if invoked synchronously from the view
        // body. Detaching the whole pipeline means scroll FPS stays
        // independent of library size: the per-tile request returns
        // instantly, the user keeps scrolling, and badges land on the
        // next render pass when the detached task writes back. Library
        // of 50k assets behaves identically to library of 500.
        Task.detached(priority: .userInitiated) { [weak self] in
            // Resolve the PHAsset off-main if the caller didn't supply
            // one. `fetchAssets(withLocalIdentifiers:)` is the standard
            // PhotoKit lookup; ~1ms per single-id fetch on a warm cache.
            let asset: PHAsset
            if let providedAsset {
                asset = providedAsset
            } else {
                let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                guard let first = fetch.firstObject else {
                    await MainActor.run { [weak self] () -> Void in
                        self?.classifyingIds.remove(assetId)
                    }
                    return
                }
                asset = first
            }
            // Tier 1 — filename. Cheapest tier, hits ~80% of social
            // saves alone (Snapchat / WhatsApp / Telegram / Messenger /
            // TikTok all have deterministic prefixes).
            if let tier1 = PhotoKitService.detectSourceFromFilename(asset) {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.classifyingIds.remove(assetId)
                    self.liveSourceCache[assetId] = tier1
                }
                return
            }
            // Tier 2 — EXIF Software tag for images, AVMetadata
            // (Software / Author / Comment atoms) for videos. The
            // video path catches TikTok / Snapchat / IG video saves
            // where the filename was stripped — same recall floor as
            // the photo path.
            let tier2: PhotoSource? = asset.mediaType == .video
                ? await PhotoKitService.detectSourceFromVideoMetadata(asset)
                : await PhotoKitService.detectSourceFromEXIF(asset)
            if let tier2 {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.classifyingIds.remove(assetId)
                    self.liveSourceCache[assetId] = tier2
                }
                return
            }
            // Tier 3 — visual / Vision text recognition. Photo path
            // OCRs the still; video path OCRs first-frame + mid-clip
            // samples extracted via AVAssetImageGenerator. Conservative
            // thresholds inside `VisualSourceClassifier` keep
            // false-positives low.
            let tier3: PhotoSource? = asset.mediaType == .video
                ? await VisualSourceClassifier.classifyVideo(asset)
                : await VisualSourceClassifier.classify(asset)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.classifyingIds.remove(assetId)
                if let tier3 {
                    self.liveSourceCache[assetId] = tier3
                }
            }
        }
    }

    /// Looks up the byte size for a counted clutter asset across every
    /// in-memory source. Called from `subtractFromStableClutter` BEFORE
    /// the deletion path mutates these collections, so the lookup hits.
    private func sizeForCountedClutterAsset(_ id: String) -> Int64 {
        if let p = analyzedIndex[id] { return Int64(p.fileSize ?? 0) }
        for g in groups { if let item = g.items.first(where: { $0.assetId == id }) { return item.fileSize } }
        for g in screenshotGroups { if let item = g.items.first(where: { $0.assetId == id }) { return item.fileSize } }
        for g in videoGroups { if let item = g.items.first(where: { $0.assetId == id }) { return item.fileSize } }
        if let s = screenshotScanResult.screenshots.first(where: { $0.assetId == id }) { return s.fileSize }
        if let s = screenRecordingScanResult.screenshots.first(where: { $0.assetId == id }) { return s.fileSize }
        if let s = shortVideoScanResult.screenshots.first(where: { $0.assetId == id }) { return s.fileSize }
        if let s = longVideoScanResult.screenshots.first(where: { $0.assetId == id }) { return s.fileSize }
        return 0
    }

    /// The Task running the most-recent full scan. Held by the store (not
    /// by a view's `.task`) so navigating away mid-scan doesn't cancel the
    /// work — the user returns to completed cards instead of a restarted
    /// scan. Set to nil when the scan finishes.
    private var activeScanTask: Task<Void, Never>?
    /// Outer bootstrap task — set synchronously on entry so concurrent
    /// `bootstrap()` calls (e.g. rapid tab switches) can dedup against
    /// the in-flight bootstrap before any await suspends. Distinct from
    /// `activeScanTask` because bootstrap also covers cache hydration +
    /// the cache-vs-fresh-scan branching.
    private var activeBootstrapTask: Task<Void, Never>?

    /// Watches the photo library and triggers `incrementalRefresh` when the
    /// user adds, deletes, or edits photos — this is what makes cards
    /// auto-update without the user tapping a scan button.
    private var libraryMonitor: PhotoLibraryChangeMonitor?

    /// Tier-2 source-app EXIF enrichment task. Spawned after every full
    /// scan / incremental refresh / per-category scan that touches
    /// `analyzedIndex`. Cancelled when a fresh scan starts (so we don't
    /// fight a re-scan with a stale enrichment pass) or when the user
    /// taps cancel. Cleared when the pass completes.
    var sourceEnrichmentTask: Task<Void, Never>?

    // MARK: - Bootstrap
    //
    // The single entry point that ChargingView's .task calls every time the
    // home tab appears. It owns three jobs:
    //
    //   1. Show cached data immediately so the user never sees a "scanning"
    //      spinner on a re-entry — cards render from SwiftData the same
    //      frame the view appears.
    //   2. Start the library change observer so cards auto-update when new
    //      photos are taken or deletions happen.
    //   3. Kick off work only when necessary: silent incremental refresh if
    //      a cache exists, or a full scan only for a first-ever launch.
    //
    // Scans run in a Task owned by the store, NOT in ChargingView's .task —
    // this is the key fix for "scan restarts every time I leave the home
    // tab". Structured concurrency cancels a view's .task when the view
    // disappears, so a scan parented to .task dies the instant the user
    // switches tabs. The store-owned Task survives all navigation.

    func bootstrap() {
        startLibraryMonitoringIfNeeded()

        // De-dup against an in-flight bootstrap — rapid tab switches used
        // to spawn parallel bootstraps that each passed the post-await
        // `activeScanTask == nil` check and kicked off duplicate scans.
        // Setting `activeBootstrapTask` synchronously (before any await)
        // closes that TOCTOU. Subsequent calls in the same window just
        // exit, since the in-flight task will publish its results when
        // it lands.
        if activeBootstrapTask != nil { return }

        // The cache-load decisions (whether to surface cached data vs run a
        // full scan) all depend on state populated by loadFromCache(), so
        // every step lives inside the same Task. bootstrap() stays sync
        // for its non-async callers — the Task runs on @MainActor since
        // the enclosing class is @MainActor, so all state mutations below
        // remain main-actor safe.
        activeBootstrapTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.activeBootstrapTask = nil }
            await self.loadFromCache()

            // A scan is already in flight — let it complete, don't pile on.
            guard self.activeScanTask == nil else { return }

            if self.hasUsableCache {
                // Surface cached data immediately. The user sees full counts
                // the instant the view appears.
                self.hasCompletedScan = true
                self.progress.isComplete = true
                self.progress.currentPhase = "Loaded from cache"

                // Silent background top-up: apply changes since last scan
                // without re-processing the whole library.
                self.activeScanTask = Task { [weak self] in
                    await self?.incrementalRefresh()
                    await MainActor.run { [weak self] in
                        self?.activeScanTask = nil
                    }
                }
                return
            }

            guard !self.hasCompletedScan else { return }

            // No cache — first-ever launch needs a real scan.
            self.activeScanTask = Task { [weak self] in
                await self?.runFullScan(force: false)
                // Explicit void return pins T = Void on
                // `MainActor.run<T>` so the optional-chained assignment
                // (which has type `Void?`) doesn't infer a non-Void
                // return that triggers the "unused result" warning.
                await MainActor.run { [weak self] () -> Void in
                    self?.activeScanTask = nil
                }
            }
        }
    }

    private func startLibraryMonitoringIfNeeded() {
        guard libraryMonitor == nil else { return }
        let monitor = PhotoLibraryChangeMonitor { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Don't pile a refresh on top of an active scan — the scan
                // will surface the latest library state when it finishes.
                guard !self.isScanning, !self.isRefreshing, self.activeScanTask == nil else { return }
                self.activeScanTask = Task { [weak self] in
                    await self?.incrementalRefresh()
                    await MainActor.run { [weak self] in
                        self?.activeScanTask = nil
                    }
                }
            }
        }
        monitor.start()
        libraryMonitor = monitor
    }

    // MARK: - Cancel

    func cancelScan() {
        photoService.cancelAnalysis()
        sourceEnrichmentTask?.cancel()
        sourceEnrichmentTask = nil
        isRunningFullScan = false
        isScanningSimilarPhotos = false
        isScanningScreenshots = false
        isScanningSimilarVideos = false
        isScanningScreenRecordings = false
        isScanningShortVideos = false
        isScanningLongVideos = false
        isClusteringPhotos = false
        isClusteringScreenshots = false
        isClusteringVideos = false
        progress.currentPhase = "Cancelled"
    }
}
