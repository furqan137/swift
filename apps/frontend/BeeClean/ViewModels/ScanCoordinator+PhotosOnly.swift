import Foundation
import Photos

// MARK: - Photos-Only Scan
extension ScanCoordinator {

    struct PhotosOnlyResult {
        var groups: [SimilarGroupVM]
        var analyzedIndex: [String: AnalyzedPhoto]
        var realScreenshotIds: Set<String>
        var duplicateScanResult: DuplicateScanResult
    }

    @MainActor
    func runPhotosOnly(
        onProgress: @escaping (PhotoAnalysisProgress) -> Void
    ) async -> PhotosOnlyResult? {
        var progress = PhotoAnalysisProgress()
        progress.currentPhase = "Requesting photo access…"
        onProgress(progress)

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if currentStatus != .authorized && currentStatus != .limited {
            let authorized = await photoService.requestAuthorization()
            guard authorized else {
                progress.error = "Photo library access is required. Please enable it in Settings → Privacy → Photos."
                progress.isComplete = true
                onProgress(progress)
                return nil
            }
        }

        progress.currentPhase = "Loading cache…"
        onProgress(progress)
        let cachedPhotos = await SimilarPersistence.loadCachedPhotos()
        let cachedIndex = Dictionary(cachedPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        progress.currentPhase = "Fetching photos…"
        onProgress(progress)
        let fetchResult = photoService.fetchAllPhotos()

        let totalCount = fetchResult.count
        guard totalCount > 0 else {
            progress.error = "No photos found in your library."
            progress.isComplete = true
            onProgress(progress)
            return nil
        }

        progress.totalPhotos = totalCount
        progress.currentPhase = "Analyzing photos…"
        onProgress(progress)

        var allPhotos: [AnalyzedPhoto] = []
        var newPhotos: [AnalyzedPhoto] = []
        var unpersistedNewPhotos: [AnalyzedPhoto] = []
        let batchSize = Self.adaptiveBatchSize(for: totalCount)
        var throttle = ProgressThrottle(totalCount: totalCount)
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            if Task.isCancelled {
                await Self.flushPersistable(&unpersistedNewPhotos)
                progress.currentPhase = "Cancelled"
                onProgress(progress)
                return nil
            }
            let batchEnd = min(batchStart + batchSize, totalCount)
            let batchResults = await processBatchWithCache(
                fetchResult: fetchResult,
                startIndex: batchStart,
                endIndex: batchEnd,
                cachedIndex: cachedIndex
            )
            for (photo, isNew) in batchResults {
                allPhotos.append(photo)
                if isNew {
                    newPhotos.append(photo)
                    if !PhotoAnalyzer.isMetadataOnly(photo) {
                        unpersistedNewPhotos.append(photo)
                    }
                }
            }
            if unpersistedNewPhotos.count >= Self.persistenceFlushInterval {
                await Self.flushPersistable(&unpersistedNewPhotos)
            }
            if throttle.shouldReport(current: batchEnd, total: totalCount) {
                progress.processedPhotos = batchEnd
                progress.currentPhase = "Analyzed \(batchEnd)/\(totalCount) photos"
                onProgress(progress)
            }
        }
        await Self.flushPersistable(&unpersistedNewPhotos)

        let analyzedIndex = Dictionary(allPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })

        progress.currentPhase = "Grouping by time…"
        onProgress(progress)
        let burstIds = PhotoKitService.extractBurstIds(fetchResult)
        let buckets = TimeBucketing.timeBuckets(photos: allPhotos, burstIds: burstIds)

        progress.currentPhase = "Finding similar photos…"
        onProgress(progress)
        var allClusters: [[AnalyzedPhoto]] = []
        var clusteredIds = Set<String>()
        // Parallel per-bucket clustering — see clusterBucketsParallel for
        // rationale.
        let bucketClusters = await HashClustering.clusterBucketsParallel(buckets: buckets)
        for clusters in bucketClusters {
            for cluster in clusters {
                allClusters.append(cluster)
                for photo in cluster { clusteredIds.insert(photo.assetIdentifier) }
            }
        }

        // Cross-bucket strict pass — mirrors runFullScan so the Photos-only
        // card shows the same duplicate groups across dates/trips that the
        // full scan finds. Without this, "Scan Photos" was missing same-
        // subject reshoots taken on different days.
        let unclustered = allPhotos.filter { !clusteredIds.contains($0.assetIdentifier) }
        if unclustered.count >= 2 {
            // LSH scales sub-quadratically, so this now completes in a few
            // seconds even on 100k+ libraries where clusterStrict would
            // have ground the device.
            let crossClusters = HashClustering.clusterStrictLSH(photos: unclustered)
            allClusters.append(contentsOf: crossClusters)
        }

        let rawGroups = GroupBuilder.buildGroups(from: allClusters)
        let groups = rawGroups.map { group in
            let items = GroupBuilder.items(for: group, analyzedIndex: analyzedIndex)
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

        SimilarPersistence.saveGroupsBackground(groups)

        let realScreenshotIds = await Task.detached { [weak self] in
            self?.photoService.fetchActualScreenshotIds() ?? []
        }.value

        let duplicateScanResult = buildDuplicateScanResult(groups: groups)
        // saveDuplicateScanResult is a plain JSON-file write (not @MainActor) —
        // calling it directly keeps the work off the main thread.
        SimilarPersistence.saveDuplicateScanResult(duplicateScanResult)

        progress.currentPhase = "Complete"
        progress.isComplete = true
        onProgress(progress)

        return PhotosOnlyResult(
            groups: groups,
            analyzedIndex: analyzedIndex,
            realScreenshotIds: realScreenshotIds,
            duplicateScanResult: duplicateScanResult
        )
    }
}
