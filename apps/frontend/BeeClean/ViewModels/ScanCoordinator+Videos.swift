import Foundation
import Photos

// MARK: - Videos Scan + analyzeVideos helper
extension ScanCoordinator {

    struct VideoAnalysisResult {
        var groups: [SimilarGroupVM]
    }

    @MainActor
    func runSimilarVideosOnly(
        onProgress: @escaping (PhotoAnalysisProgress) -> Void
    ) async -> [SimilarGroupVM]? {
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

        // Load cache so videos already analyzed skip straight to clustering.
        progress.currentPhase = "Loading cache…"
        onProgress(progress)
        let cachedPhotos = await SimilarPersistence.loadCachedPhotos()
        let cachedIndex = Dictionary(cachedPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        progress.currentPhase = "Analyzing videos…"
        onProgress(progress)
        let result = await analyzeVideos(
            progress: &progress,
            onProgress: onProgress,
            cachedIndex: cachedIndex
        )

        progress.currentPhase = "Complete"
        progress.isComplete = true
        onProgress(progress)

        return result.groups
    }

    func analyzeVideos(
        progress: inout PhotoAnalysisProgress,
        onProgress: @escaping (PhotoAnalysisProgress) -> Void,
        cachedIndex: [String: AnalyzedPhoto] = [:]
    ) async -> VideoAnalysisResult {
        let videoFetchResult = await Task.detached { [weak self] in
            return self?.photoService.fetchAllVideos()
        }.value

        guard let videoFetchResult, videoFetchResult.count > 0 else {
            return VideoAnalysisResult(groups: [])
        }

        let vidTotal = videoFetchResult.count
        var vidPhotos: [AnalyzedPhoto] = []
        var vidUnpersisted: [AnalyzedPhoto] = []
        let vidBatchSize = Self.adaptiveBatchSize(for: vidTotal)
        var vidThrottle = ProgressThrottle(totalCount: vidTotal)
        for batchStart in stride(from: 0, to: vidTotal, by: vidBatchSize) {
            if Task.isCancelled {
                await Self.flushPersistable(&vidUnpersisted)
                break
            }
            let batchEnd = min(batchStart + vidBatchSize, vidTotal)
            let batchResults = await processBatchWithCache(
                fetchResult: videoFetchResult,
                startIndex: batchStart,
                endIndex: batchEnd,
                cachedIndex: cachedIndex
            )
            for (photo, isNew) in batchResults {
                vidPhotos.append(photo)
                if isNew && !PhotoAnalyzer.isMetadataOnly(photo) {
                    vidUnpersisted.append(photo)
                }
            }
            if vidUnpersisted.count >= Self.persistenceFlushInterval {
                await Self.flushPersistable(&vidUnpersisted)
            }

            if vidThrottle.shouldReport(current: batchEnd, total: vidTotal) {
                progress.currentPhase = "Analyzing videos \(batchEnd)/\(vidTotal)"
                onProgress(progress)
            }
        }
        await Self.flushPersistable(&vidUnpersisted)

        let vidBurstIds = PhotoKitService.extractBurstIds(videoFetchResult)
        let vidBuckets = TimeBucketing.timeBuckets(photos: vidPhotos, burstIds: vidBurstIds)
        var vidClusters: [[AnalyzedPhoto]] = []
        var vidClusteredIds = Set<String>()
        // Parallel per-bucket clustering — see clusterBucketsParallel.
        let vidBucketClusters = await HashClustering.clusterBucketsParallel(buckets: vidBuckets)
        for clusters in vidBucketClusters {
            for cluster in clusters {
                vidClusters.append(cluster)
                for v in cluster { vidClusteredIds.insert(v.assetIdentifier) }
            }
        }

        // Cross-bucket LSH pass — catches visually identical clips taken at
        // different times (vacation reshoots, camera-roll imports) that fall
        // into separate time buckets. Mirrors the photo flow so the Similar
        // Videos card surfaces everything the Similar Photos card does.
        let vidUnclustered = vidPhotos.filter { !vidClusteredIds.contains($0.assetIdentifier) }
        if vidUnclustered.count >= 2 {
            let crossVid = HashClustering.clusterStrictLSH(photos: vidUnclustered)
            vidClusters.append(contentsOf: crossVid)
        }

        let vidRawGroups = GroupBuilder.buildGroups(from: vidClusters)
        let vidIndex = Dictionary(vidPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })

        let vidGroups = vidRawGroups.map { group in
            let items = GroupBuilder.items(for: group, analyzedIndex: vidIndex)
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

        SimilarPersistence.saveVideoGroupsBackground(vidGroups)

        return VideoAnalysisResult(groups: vidGroups)
    }
}
