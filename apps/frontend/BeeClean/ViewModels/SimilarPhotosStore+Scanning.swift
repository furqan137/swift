import Foundation
import Photos

// MARK: - Scan Orchestration + Per-Category Scans + Incremental Refresh
extension SimilarPhotosStore {

    // MARK: Full Scan

    func runFullScan(force: Bool = false) async {
        guard !isScanning else { return }
        guard force || !hasCompletedScan else { return }

        isRunningFullScan = true
        error = nil
        // Keep existing groups + analyzedIndex alive while scanning so the
        // UI still shows cached data ("120 items") instead of clearing to 0
        // and flashing "All clear" during the 30-120 second scan window.
        // applyScanResult() will overwrite them atomically once the new
        // data is ready.
        loadedFromCache = false
        progress = PhotoAnalysisProgress()

        let coordinator = ScanCoordinator()
        let result = await coordinator.runFullScan(
            onProgress: { [weak self] prog in
                Task { @MainActor [weak self] in
                    self?.progress = prog
                    if let err = prog.error { self?.error = err }
                }
            },
            onPartial: { [weak self] partial in
                // Stream partial scan results into the @Observable store
                // as each phase completes. The first emission lands ~1–2s
                // after scan start with smart-album results — Cleanup's
                // Screenshots / Screen Recordings / Short / Long Video
                // cards populate immediately. Photo groups + analyzedIndex
                // land on the second emission, screenshot groups on the
                // third, video groups on the fourth.
                guard let self = self else { return }
                if let v = partial.screenshotScanResult { self.screenshotScanResult = v }
                if let v = partial.screenRecordingScanResult { self.screenRecordingScanResult = v }
                if let v = partial.shortVideoScanResult { self.shortVideoScanResult = v }
                if let v = partial.longVideoScanResult { self.longVideoScanResult = v }
                if let v = partial.groups {
                    self.groups = v
                    // Photo clustering done → drop the Duplicates / Similar
                    // Photos "Scanning…" badge.
                    self.isClusteringPhotos = false
                }
                if let v = partial.screenshotGroups {
                    self.screenshotGroups = v
                    self.isClusteringScreenshots = false
                }
                if let v = partial.videoGroups {
                    self.videoGroups = v
                    self.isClusteringVideos = false
                }
                if let v = partial.analyzedIndex { self.analyzedIndex = v }

                // Phase transitions — granular flag flips so non-clustering
                // cards stop showing "Scanning…" the moment analyzedIndex
                // is built, while clustering cards stay in their own
                // "Calculating groups…" state until each phase completes.
                if partial.photoAnalysisDidComplete {
                    self.isRunningFullScan = false
                }
                if partial.photoClusteringDidStart { self.isClusteringPhotos = true }
                if partial.screenshotClusteringDidStart { self.isClusteringScreenshots = true }
                if partial.videoClusteringDidStart { self.isClusteringVideos = true }

                // Refresh the dashboard derivations after every partial
                // emission — counts and previews update card-by-card as
                // smart-album → analysis → clustering phases complete.
                // Without this the cards would show pre-snapshot values
                // until the final `applyScanResult` lands at the very
                // end of the scan.
                self.recomputeDashboardSnapshot()
            }
        )

        if let result {
            applyScanResult(result)
        }

        hasCompletedScan = true
        // Belt-and-suspenders: onPartial usually flips these to false the
        // moment each clustering phase emits, but if the coordinator
        // bailed early (cancel, error) or skipped a phase entirely, clear
        // them here so cards don't get stuck on "Scanning…".
        isRunningFullScan = false
        isClusteringPhotos = false
        isClusteringScreenshots = false
        isClusteringVideos = false

        // Kick off Tier 2 source-app enrichment in the background. Picks
        // up where the inline Tier 1 filename pass left off — Instagram
        // saves (and any source the filename pass missed) get backfilled
        // and surfaced via `recomputeDashboardSnapshot` as each batch
        // lands. Doesn't block the scan-completion return.
        kickoffSourceEnrichment()
    }

    // MARK: Per-Category Scans
    //
    // Each method runs ONLY its own slice of the scan pipeline and flips ONLY
    // its own `isScanning*` flag. Views bound to that flag stay in the
    // "scanning" state; other category views are unaffected.

    /// Scans the photo library and builds similar / duplicate groups.
    /// Populates: `groups`, `analyzedIndex`, `realScreenshotIds`,
    /// `duplicateScanResult`, and the scan summary.
    func runSimilarPhotosScan(force: Bool = false) async {
        guard !isScanningSimilarPhotos && !isRunningFullScan else { return }

        isScanningSimilarPhotos = true
        error = nil
        progress = PhotoAnalysisProgress()

        let coordinator = ScanCoordinator()
        let result = await coordinator.runPhotosOnly { [weak self] prog in
            Task { @MainActor [weak self] in
                self?.progress = prog
                if let err = prog.error { self?.error = err }
            }
        }

        if let result {
            groups = result.groups
            analyzedIndex = result.analyzedIndex
            realScreenshotIds = result.realScreenshotIds
            duplicateScanResult = result.duplicateScanResult
            persistScanSummary()
            recomputeDashboardSnapshot()
        }

        hasCompletedScan = true
        isScanningSimilarPhotos = false
    }

    /// Scans screenshots only and builds similar-screenshot groups.
    func runScreenshotsScan(force: Bool = false) async {
        guard !isScanningScreenshots && !isRunningFullScan else { return }

        isScanningScreenshots = true
        error = nil
        progress = PhotoAnalysisProgress()

        let coordinator = ScanCoordinator()
        let result = await coordinator.runScreenshotsOnly { [weak self] prog in
            Task { @MainActor [weak self] in
                self?.progress = prog
                if let err = prog.error { self?.error = err }
            }
        }

        if let result {
            screenshotGroups = result.groups
            screenshotScanResult = result.scanResult
            persistScanSummary()
            recomputeDashboardSnapshot()
        }

        hasCompletedScan = true
        isScanningScreenshots = false
    }

    /// Scans videos only and builds similar-video groups. Also refreshes
    /// screen-recording / short / long video lists so the full Videos tab is
    /// consistent after a single tap — otherwise those lists could go stale
    /// between full scans and leave newly imported videos invisible.
    func runSimilarVideosScan(force: Bool = false) async {
        guard !isScanningSimilarVideos && !isRunningFullScan else { return }

        isScanningSimilarVideos = true
        error = nil
        progress = PhotoAnalysisProgress()

        let coordinator = ScanCoordinator()
        let result = await coordinator.runSimilarVideosOnly { [weak self] prog in
            Task { @MainActor [weak self] in
                self?.progress = prog
                if let err = prog.error { self?.error = err }
            }
        }

        if let groups = result {
            videoGroups = groups
        }

        await refreshScreenRecordingScanResult()
        await refreshShortVideoScanResult()
        await refreshLongVideoScanResult()
        persistScanSummary()
        recomputeDashboardSnapshot()

        hasCompletedScan = true
        isScanningSimilarVideos = false
    }

    /// Re-fetches only the screen-recording list.
    func runScreenRecordingsScan() async {
        guard !isScanningScreenRecordings && !isRunningFullScan else { return }
        isScanningScreenRecordings = true
        error = nil
        await refreshScreenRecordingScanResult()
        isScanningScreenRecordings = false
    }

    /// Re-fetches only the short-video list.
    func runShortVideosScan() async {
        guard !isScanningShortVideos && !isRunningFullScan else { return }
        isScanningShortVideos = true
        error = nil
        await refreshShortVideoScanResult()
        isScanningShortVideos = false
    }

    /// Re-fetches only the long-video list.
    func runLongVideosScan() async {
        guard !isScanningLongVideos && !isRunningFullScan else { return }
        isScanningLongVideos = true
        error = nil
        await refreshLongVideoScanResult()
        isScanningLongVideos = false
    }

    func applyScanResult(_ result: ScanResult) {
        groups = result.groups
        screenshotGroups = result.screenshotGroups
        videoGroups = result.videoGroups
        screenshotScanResult = result.screenshotScanResult
        screenRecordingScanResult = result.screenRecordingScanResult
        shortVideoScanResult = result.shortVideoScanResult
        longVideoScanResult = result.longVideoScanResult
        scanSummary = result.scanSummary
        duplicateScanResult = result.duplicateScanResult
        analyzedIndex = result.analyzedIndex
        realScreenshotIds = result.realScreenshotIds
        recomputeDashboardSnapshot()
    }

    // MARK: Incremental Refresh

    /// Top up the scan with the delta since the last full scan — fast when
    /// nothing changed, surgical when the user added a handful of photos.
    ///
    /// Coverage: photo groups (diff-and-cluster), screenshot metadata,
    /// screen-recording list, short-video list, and long-video list. The
    /// fetch-based categories (screenshot/short/long) are single PHFetchResult
    /// enumerations — milliseconds on any library — so we refresh all of
    /// them here to keep the cards in lock-step with the camera roll.
    ///
    /// Intentionally silent: does NOT flip `isScanning` flags, so cards stay
    /// on screen without a spinner. The user should never see a "scanning…"
    /// state from an auto-refresh, only from an explicit scan-button tap.
    func incrementalRefresh() async {
        guard !isScanning && !isRefreshing else { return }
        isRefreshing = true
        error = nil

        let coordinator = ScanCoordinator()
        if let result = await coordinator.incrementalRefresh(
            currentGroups: groups,
            currentIndex: analyzedIndex
        ) {
            groups = result.groups
            analyzedIndex = result.analyzedIndex
        }

        // Refresh the non-photo categories — each is a quick PHFetch, no
        // image decoding. Without this, a freshly taken screenshot wouldn't
        // appear under Screenshots until the user triggered a full scan.
        await refreshScreenshotScanResult()
        await refreshScreenRecordingScanResult()
        await refreshShortVideoScanResult()
        await refreshLongVideoScanResult()

        persistScanSummary()
        recomputeDashboardSnapshot()
        hasCompletedScan = true
        isRefreshing = false

        // Tier 2 enrichment over the refreshed analyzedIndex — picks up
        // any newly-added photos that the inline Tier 1 filename pass
        // didn't classify (Instagram, edited TikTok exports, etc.).
        kickoffSourceEnrichment()
    }

    // MARK: - Source-App Enrichment (Tier 2)

    /// Spawns a background EXIF-enrichment pass over the current
    /// `analyzedIndex` and merges results into the store as each batch
    /// lands. Cancels any previous enrichment task first — a re-scan
    /// invalidates the previous pass's seed set.
    ///
    /// The pass:
    ///   • Walks every photo where `sourceApp == nil` and the asset
    ///     isn't metadata-only.
    ///   • Reads each photo's EXIF/TIFF header (NOT pixel data) in
    ///     parallel batches of 8 — see `PhotoKitService.enrichSourcesFromEXIF`.
    ///   • Persists every 50 hits via `savePhotosBackground` so results
    ///     survive a mid-pass kill, and calls back to MainActor here to
    ///     merge into `analyzedIndex` + trigger a dashboard recompute.
    func kickoffSourceEnrichment() {
        sourceEnrichmentTask?.cancel()
        let seeds = analyzedIndex
        guard !seeds.isEmpty else {
            sourceEnrichmentTask = nil
            return
        }

        sourceEnrichmentTask = Task { [weak self] in
            await PhotoKitService.enrichSourcesFromEXIF(seeds: seeds) { [weak self] batch in
                guard let self else { return }
                for (assetId, source) in batch {
                    if var photo = self.analyzedIndex[assetId] {
                        photo.sourceApp = source
                        self.analyzedIndex[assetId] = photo
                    }
                }
                self.recomputeDashboardSnapshot()
            }
            await MainActor.run { [weak self] in
                self?.sourceEnrichmentTask = nil
            }
        }
    }

    // MARK: Refresh Scan Results

    func refreshScreenshotScanResult() async {
        let screenshots = await Task.detached { [weak self] in
            self?.photoService.fetchScreenshots() ?? []
        }.value
        let totalBytes = screenshots.reduce(Int64(0)) { $0 + $1.fileSize }
        let result = ScreenshotScanResult(screenshots: screenshots, totalBytes: totalBytes, scannedAt: Date())
        screenshotScanResult = result
        SimilarPersistence.saveScreenshotScanResult(result)
        persistScanSummary()
    }

    func refreshScreenRecordingScanResult() async {
        let recordings = await Task.detached { [weak self] in
            self?.photoService.fetchScreenRecordings() ?? []
        }.value
        let totalBytes = recordings.reduce(Int64(0)) { $0 + $1.fileSize }
        let result = ScreenshotScanResult(screenshots: recordings, totalBytes: totalBytes, scannedAt: Date())
        screenRecordingScanResult = result
        SimilarPersistence.saveScreenRecordingScanResult(result)
        persistScanSummary()
    }

    func refreshShortVideoScanResult() async {
        let shortVideos = await Task.detached { [weak self] in
            self?.photoService.fetchShortVideos() ?? []
        }.value
        let totalBytes = shortVideos.reduce(Int64(0)) { $0 + $1.fileSize }
        let result = ScreenshotScanResult(screenshots: shortVideos, totalBytes: totalBytes, scannedAt: Date())
        shortVideoScanResult = result
        SimilarPersistence.saveShortVideoScanResult(result)
        persistScanSummary()
    }

    func refreshLongVideoScanResult() async {
        let rawLongVideos = await Task.detached { [weak self] in
            self?.photoService.fetchLongVideos() ?? []
        }.value
        // Filter out videos the user has chosen to keep on-device — they
        // should never reappear in the Long Videos flow across sessions.
        let keptIds = LocalKeptStore.shared.ids(in: .longVideos)
        let longVideos = keptIds.isEmpty
            ? rawLongVideos
            : rawLongVideos.filter { !keptIds.contains($0.assetId) }
        let totalBytes = longVideos.reduce(Int64(0)) { $0 + $1.fileSize }
        let result = ScreenshotScanResult(screenshots: longVideos, totalBytes: totalBytes, scannedAt: Date())
        longVideoScanResult = result
        SimilarPersistence.saveLongVideoScanResult(result)
        persistScanSummary()
    }
}
