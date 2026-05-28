import Foundation
import Photos

// MARK: - Incremental Refresh
extension ScanCoordinator {

    @MainActor
    func incrementalRefresh(
        currentGroups: [SimilarGroupVM],
        currentIndex: [String: AnalyzedPhoto]
    ) async -> (groups: [SimilarGroupVM], analyzedIndex: [String: AnalyzedPhoto])? {

        let cachedIds = SimilarPersistence.cachedAssetIds()

        let fetchResult = await Task.detached { [weak self] in
            return self?.photoService.fetchAllPhotos()
        }.value

        guard let fetchResult else { return nil }

        var libraryIds = Set<String>()
        var newAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            libraryIds.insert(id)
            if !cachedIds.contains(id) {
                newAssets.append(asset)
            }
        }

        var groups = currentGroups
        var analyzedIndex = currentIndex

        // Prune deleted
        let deletedFromLibrary = cachedIds.subtracting(libraryIds)
        if !deletedFromLibrary.isEmpty {
            SimilarPersistence.deletePhotos(assetIds: Array(deletedFromLibrary))
            for id in deletedFromLibrary {
                analyzedIndex.removeValue(forKey: id)
            }
            for gi in groups.indices.reversed() {
                groups[gi].items.removeAll { deletedFromLibrary.contains($0.assetId) }
                if groups[gi].items.count <= 1 {
                    groups.remove(at: gi)
                }
            }
            SimilarPersistence.saveGroups(groups)
        }

        guard !newAssets.isEmpty else { return (groups, analyzedIndex) }

        // Pre-warm the daemon's thumbnail cache for the new-photo set
        // before the TaskGroup fires its analyzeAsset chain (same
        // pattern as processBatchWithCache).
        let cacheTargetSize = CGSize(width: 128, height: 128)
        let cacheOptions = PHImageRequestOptions()
        cacheOptions.deliveryMode = .fastFormat
        cacheOptions.resizeMode = .fast
        cacheOptions.isNetworkAccessAllowed = false
        let mgr = photoService.imageManager
        mgr.startCachingImages(
            for: newAssets,
            targetSize: cacheTargetSize,
            contentMode: .aspectFill,
            options: cacheOptions
        )
        defer {
            mgr.stopCachingImages(
                for: newAssets,
                targetSize: cacheTargetSize,
                contentMode: .aspectFill,
                options: cacheOptions
            )
        }

        // Analyze new photos in parallel — if the user took 50 photos since
        // the last scan, sequential analysis at ~60ms/photo is 3s blocking;
        // parallel at concurrency 12 is ~250ms and never blocks the UI.
        let analyzer = self.analyzer
        let concurrency = min(Self.analysisConcurrency, newAssets.count)
        let newPhotos: [AnalyzedPhoto] = await withTaskGroup(of: AnalyzedPhoto.self) { group in
            var iterator = newAssets.makeIterator()
            for _ in 0..<concurrency {
                guard let asset = iterator.next() else { break }
                group.addTask { await analyzer.analyzeAsset(asset) }
            }
            var collected: [AnalyzedPhoto] = []
            collected.reserveCapacity(newAssets.count)
            while let photo = await group.next() {
                collected.append(photo)
                if let asset = iterator.next() {
                    group.addTask { await analyzer.analyzeAsset(asset) }
                }
            }
            return collected
        }

        guard !newPhotos.isEmpty else { return (groups, analyzedIndex) }

        let persistableRefresh = newPhotos.filter { !PhotoAnalyzer.isMetadataOnly($0) }
        if !persistableRefresh.isEmpty {
            SimilarPersistence.savePhotos(persistableRefresh)
        }

        for photo in newPhotos {
            analyzedIndex[photo.assetIdentifier] = photo
        }

        // Re-cluster everything — within-bucket + cross-bucket LSH pass
        // mirrors runFullScan so incremental results match a fresh scan.
        // Parallel per-bucket so the incremental refresh stays sub-second
        // even on large libraries.
        let allPhotos = Array(analyzedIndex.values)
        let burstIds = PhotoKitService.extractBurstIds(fetchResult)
        let buckets = TimeBucketing.timeBuckets(photos: allPhotos, burstIds: burstIds)
        var allClusters: [[AnalyzedPhoto]] = []
        var clusteredIds = Set<String>()
        let bucketClusters = await HashClustering.clusterBucketsParallel(buckets: buckets)
        for clusters in bucketClusters {
            for cluster in clusters {
                allClusters.append(cluster)
                for photo in cluster { clusteredIds.insert(photo.assetIdentifier) }
            }
        }
        let unclusteredRefresh = allPhotos.filter { !clusteredIds.contains($0.assetIdentifier) }
        if unclusteredRefresh.count >= 2 {
            let crossClusters = HashClustering.clusterStrictLSH(photos: unclusteredRefresh)
            allClusters.append(contentsOf: crossClusters)
        }

        let rawGroups = GroupBuilder.buildGroups(from: allClusters)
        groups = rawGroups.map { group in
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

        SimilarPersistence.saveGroups(groups)
        return (groups, analyzedIndex)
    }
}
