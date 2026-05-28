import Foundation
import Photos

// MARK: - Screenshots Scan + analyzeScreenshots helper
extension ScanCoordinator {

    struct ScreenshotsOnlyResult {
        var groups: [SimilarGroupVM]
        var scanResult: ScreenshotScanResult
    }

    struct ScreenshotAnalysisResult {
        var groups: [SimilarGroupVM]
        var scanResult: ScreenshotScanResult
    }

    @MainActor
    func runScreenshotsOnly(
        onProgress: @escaping (PhotoAnalysisProgress) -> Void
    ) async -> ScreenshotsOnlyResult? {
        var progress = PhotoAnalysisProgress()
        progress.currentPhase = "Requesting photo access…"
        onProgress(progress)

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus != .authorized && currentStatus != .limited {
            let authorized = await photoService.requestAuthorization()
            guard authorized else {
                progress.error = "Photo library access is required."
                progress.isComplete = true
                onProgress(progress)
                return nil
            }
        }

        // Load cache up-front so screenshots already analyzed skip the
        // expensive image decode + hash. Without this, every tap on
        // "Scan Screenshots" re-analyzed the entire screenshot library.
        progress.currentPhase = "Loading cache…"
        onProgress(progress)
        let cachedPhotos = await SimilarPersistence.loadCachedPhotos()
        let cachedIndex = Dictionary(cachedPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        progress.currentPhase = "Analyzing screenshots…"
        onProgress(progress)
        let result = await analyzeScreenshots(
            progress: &progress,
            onProgress: onProgress,
            cachedIndex: cachedIndex
        )

        progress.currentPhase = "Complete"
        progress.isComplete = true
        onProgress(progress)

        return ScreenshotsOnlyResult(groups: result.groups, scanResult: result.scanResult)
    }

    func analyzeScreenshots(
        progress: inout PhotoAnalysisProgress,
        onProgress: @escaping (PhotoAnalysisProgress) -> Void,
        cachedIndex: [String: AnalyzedPhoto] = [:]
    ) async -> ScreenshotAnalysisResult {
        let ssFetchResult = await Task.detached { [weak self] in
            return self?.photoService.fetchScreenshotAssets()
        }.value

        guard let ssFetchResult else {
            return ScreenshotAnalysisResult(groups: [], scanResult: .empty)
        }

        let ssTotal = ssFetchResult.count

        // Fetch metadata for raw count tracking
        let screenshots = await Task.detached { [weak self] in
            self?.photoService.fetchScreenshots() ?? []
        }.value
        let totalScreenshotBytes = screenshots.reduce(Int64(0)) { $0 + $1.fileSize }
        let ssResult = ScreenshotScanResult(
            screenshots: screenshots,
            totalBytes: totalScreenshotBytes,
            scannedAt: Date()
        )
        // saveScreenshotScanResult is a plain JSON-file write (not @MainActor).
        SimilarPersistence.saveScreenshotScanResult(ssResult)

        // Analyze each screenshot asset, reusing the shared hash cache so
        // subsequent scans are nearly instant on unchanged screenshots.
        var ssPhotos: [AnalyzedPhoto] = []
        var ssUnpersisted: [AnalyzedPhoto] = []
        let ssBatchSize = Self.adaptiveBatchSize(for: ssTotal)
        var ssThrottle = ProgressThrottle(totalCount: ssTotal)
        for batchStart in stride(from: 0, to: ssTotal, by: ssBatchSize) {
            if Task.isCancelled {
                await Self.flushPersistable(&ssUnpersisted)
                break
            }
            let batchEnd = min(batchStart + ssBatchSize, ssTotal)
            let batchResults = await processBatchWithCache(
                fetchResult: ssFetchResult,
                startIndex: batchStart,
                endIndex: batchEnd,
                cachedIndex: cachedIndex
            )
            for (photo, isNew) in batchResults {
                ssPhotos.append(photo)
                if isNew && !PhotoAnalyzer.isMetadataOnly(photo) {
                    ssUnpersisted.append(photo)
                }
            }
            if ssUnpersisted.count >= Self.persistenceFlushInterval {
                await Self.flushPersistable(&ssUnpersisted)
            }

            if ssThrottle.shouldReport(current: batchEnd, total: ssTotal) {
                progress.currentPhase = "Analyzing screenshots \(batchEnd)/\(ssTotal)"
                onProgress(progress)
            }
        }
        await Self.flushPersistable(&ssUnpersisted)

        // Cluster — parallel per bucket (buckets are independent).
        let ssBurstIds = PhotoKitService.extractBurstIds(ssFetchResult)
        let ssBuckets = TimeBucketing.timeBuckets(photos: ssPhotos, burstIds: ssBurstIds)
        var ssClusters: [[AnalyzedPhoto]] = []
        let ssBucketClusters = await HashClustering.clusterBucketsParallel(buckets: ssBuckets)
        for clusters in ssBucketClusters {
            ssClusters.append(contentsOf: clusters)
        }
        let ssRawGroups = GroupBuilder.buildGroups(from: ssClusters)
        let ssIndex = Dictionary(ssPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })

        let ssGroups = ssRawGroups.map { group in
            let items = GroupBuilder.items(for: group, analyzedIndex: ssIndex)
            return SimilarGroupVM(
                id: group.id,
                count: group.count,
                totalBytes: group.totalBytes,
                confidence: group.confidence,
                createdAt: group.createdAt,
                bestId: group.bestId,
                items: items
            )
        }

        SimilarPersistence.saveScreenshotGroupsBackground(ssGroups)

        return ScreenshotAnalysisResult(groups: ssGroups, scanResult: ssResult)
    }
}
