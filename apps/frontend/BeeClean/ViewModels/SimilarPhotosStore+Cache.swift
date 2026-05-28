import Foundation

// MARK: - Cache Load + Scan Summary Persist

/// File-JSON portion of cache load — these readers don't touch SwiftData
/// so they run safely on a userInitiated background queue. The SwiftData-
/// backed readers (`loadCachedPhotos`, `loadCachedGroups`,
/// `loadCachedScreenshotGroups`, `loadCachedVideoGroups`) are @MainActor
/// because their ModelContext is main-actor-bound, so they stay on main.
private struct SimilarJSONCachePayload: Sendable {
    let scanSummary: ScanSummary
    let duplicateScanResult: DuplicateScanResult
    let screenshotScanResult: ScreenshotScanResult
    let screenRecordingScanResult: ScreenshotScanResult
    let shortVideoScanResult: ScreenshotScanResult
    let longVideoScanResult: ScreenshotScanResult
}

extension SimilarPhotosStore {
    func loadFromCache() async {
        guard !isScanning else { return }
        // Concurrency guard — five detail views appearing back-to-back
        // (Cleanup → tap card → back → tap another card) must NOT each
        // spawn their own disk-read storm.
        guard !isLoadingFromCache else { return }
        isLoadingFromCache = true
        defer { isLoadingFromCache = false }

        // 1. JSON-file readers off main (six summary files; together usually
        //    a few hundred KB but historically caught blocking SwiftUI's
        //    first paint by a beat).
        let payload = await Task.detached(priority: .userInitiated) { () -> SimilarJSONCachePayload in
            SimilarJSONCachePayload(
                scanSummary: SimilarPersistence.loadScanSummary(),
                duplicateScanResult: SimilarPersistence.loadDuplicateScanResult(),
                screenshotScanResult: SimilarPersistence.loadScreenshotScanResult(),
                screenRecordingScanResult: SimilarPersistence.loadScreenRecordingScanResult(),
                shortVideoScanResult: SimilarPersistence.loadShortVideoScanResult(),
                longVideoScanResult: SimilarPersistence.loadLongVideoScanResult()
            )
        }.value

        scanSummary = payload.scanSummary
        duplicateScanResult = payload.duplicateScanResult
        screenshotScanResult = payload.screenshotScanResult
        screenRecordingScanResult = payload.screenRecordingScanResult
        shortVideoScanResult = payload.shortVideoScanResult
        longVideoScanResult = payload.longVideoScanResult

        // 2. SwiftData-backed readers — run on a background ModelContext
        //    to prevent watchdog timeout (0x8BADF00D) during scene updates.
        //    Previously these ran on @MainActor using the main ModelContext,
        //    blocking for 10+ seconds during cache hydration on big libraries
        //    and tripping the scene-update watchdog. The Background variants
        //    use a fresh ModelContext on a Task.detached thread, so the main
        //    thread stays responsive while cache hydrates.
        let swiftDataPayload = await Task.detached(priority: .userInitiated) { () -> (
            screenshotGroups: [SimilarGroupVM],
            videoGroups: [SimilarGroupVM],
            cachedPhotos: [AnalyzedPhoto],
            cachedGroups: [SimilarGroupVM]
        ) in
            let screenshots = SimilarPersistence.loadCachedScreenshotGroupsBackground()
            let videos = SimilarPersistence.loadCachedVideoGroupsBackground()
            let photos = SimilarPersistence.loadCachedPhotosBackground()
            let groups = SimilarPersistence.loadCachedGroupsBackground()
            return (screenshots, videos, photos, groups)
        }.value

        if screenshotGroups.isEmpty && !swiftDataPayload.screenshotGroups.isEmpty {
            screenshotGroups = swiftDataPayload.screenshotGroups
        }

        if videoGroups.isEmpty && !swiftDataPayload.videoGroups.isEmpty {
            videoGroups = swiftDataPayload.videoGroups
        }

        if analyzedIndex.isEmpty && !swiftDataPayload.cachedPhotos.isEmpty {
            analyzedIndex = Dictionary(swiftDataPayload.cachedPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            loadedFromCache = true
            // Only mark scan-complete if we also have a non-empty scan
            // summary (i.e., a previous scan actually finished). Without
            // this, loadFromCache after a partial/interrupted run would
            // set `isComplete = true` → cards flash "All clear" with 0
            // counts before the real scan gets a chance to run.
            if scanSummary.lastScanDate != nil {
                progress.isComplete = true
                progress.currentPhase = "Loaded from cache"
            }
        }

        if realScreenshotIds.isEmpty {
            realScreenshotIds = photoService.fetchActualScreenshotIds()
        }

        guard groups.isEmpty else {
            // We populated other state above (analyzedIndex, screenshot
            // groups, video groups, scan summary). Even if `groups` was
            // already populated and we bail here, the cards still need
            // a fresh snapshot reflecting whatever DID get loaded.
            recomputeDashboardSnapshot()
            return
        }
        if !swiftDataPayload.cachedGroups.isEmpty {
            groups = swiftDataPayload.cachedGroups
        }
        // Refresh the dashboard derivations now that all of cache load
        // is settled — preview cards re-render with cached counts and
        // bytes the moment this returns.
        recomputeDashboardSnapshot()
    }

    func persistScanSummary() {
        let duplicateGroupVMs = groups.filter { $0.confidence >= 0.85 }
        let similarGroupVMs = groups.filter { $0.confidence < 0.85 }

        let summary = ScanSummary(
            similarGroupsCount: similarGroupVMs.count,
            similarToCleanCount: similarGroupVMs.reduce(0) { $0 + $1.selectedCount },
            duplicateGroupsCount: duplicateGroupVMs.count,
            duplicateToCleanCount: duplicateGroupVMs.reduce(0) { $0 + $1.selectedCount },
            screenshotCount: screenshotScanResult.count,
            screenshotTotalBytes: screenshotScanResult.totalBytes,
            screenshotGroupsCount: screenshotGroups.count,
            screenshotToCleanCount: screenshotGroups.reduce(0) { $0 + $1.selectedCount },
            videoGroupsCount: videoGroups.count,
            videoToCleanCount: videoGroups.reduce(0) { $0 + $1.selectedCount },
            screenRecordingCount: screenRecordingScanResult.count,
            screenRecordingTotalBytes: screenRecordingScanResult.totalBytes,
            shortVideoCount: shortVideoScanResult.count,
            shortVideoTotalBytes: shortVideoScanResult.totalBytes,
            longVideoCount: longVideoScanResult.count,
            longVideoTotalBytes: longVideoScanResult.totalBytes,
            lastScanDate: Date()
        )
        scanSummary = summary
        SimilarPersistence.saveScanSummary(summary)

        let dupGroups = duplicateGroupVMs.map { g in
            PhotoDuplicateGroup(
                id: g.id,
                keepAssetId: g.bestId,
                deleteAssetIds: g.items.filter { $0.assetId != g.bestId }.map(\.assetId),
                confidence: g.confidence,
                totalBytes: g.totalBytes
            )
        }
        let dupResult = DuplicateScanResult(groups: dupGroups, scannedAt: Date())
        duplicateScanResult = dupResult
        SimilarPersistence.saveDuplicateScanResult(dupResult)
    }
}
