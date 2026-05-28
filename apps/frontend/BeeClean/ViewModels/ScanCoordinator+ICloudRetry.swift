import Foundation
import Photos

// MARK: - iCloud Retry Pass
//
// Detached background pass that re-analyzes assets the local-only main
// scan fell back to metadata-only on. Runs at .background QoS, with
// concurrency tuned for bandwidth-bound iCloud downloads.
extension ScanCoordinator {


    static func runICloudRetry(
        assetIds: [String],
        analyzer: PhotoAnalyzer,
        seedIndex: [String: AnalyzedPhoto],
        onPartial: @escaping (PartialScanData) -> Void
    ) async {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }

        // iCloud is bandwidth-bound — running 20 in flight just queues up
        // pending downloads at the daemon. 8 keeps the network pipe full
        // without thrashing.
        let concurrency = min(8, assets.count)
        let analyzed: [AnalyzedPhoto] = await withTaskGroup(of: AnalyzedPhoto.self) { group in
            var iterator = assets.makeIterator()
            for _ in 0..<concurrency {
                guard let asset = iterator.next() else { break }
                group.addTask { await analyzer.analyzeAsset(asset, networkAccess: true) }
            }
            var collected: [AnalyzedPhoto] = []
            collected.reserveCapacity(assets.count)
            while let photo = await group.next() {
                collected.append(photo)
                if let asset = iterator.next() {
                    group.addTask { await analyzer.analyzeAsset(asset, networkAccess: true) }
                }
            }
            return collected
        }

        let upgraded = analyzed.filter { !PhotoAnalyzer.isMetadataOnly($0) }
        guard !upgraded.isEmpty else { return }

        // Persist the upgraded analyses so subsequent launches skip iCloud
        // entirely for these assets. Background variant keeps the main
        // thread free during the iCloud retry pass.
        SimilarPersistence.savePhotosBackground(upgraded)

        // Merge upgraded photos into the seed index and re-cluster.
        // `let` (built via an immediately-invoked closure) instead of `var`
        // so Swift 6 strict concurrency stops flagging the capture in the
        // MainActor.run closure below — a let-bound dictionary of Sendable
        // values is itself Sendable and safe to ferry across an actor hop.
        let merged: [String: AnalyzedPhoto] = {
            var m = seedIndex
            for photo in upgraded { m[photo.assetIdentifier] = photo }
            return m
        }()

        let allMerged = Array(merged.values)
        let buckets = TimeBucketing.timeBuckets(photos: allMerged, burstIds: [:])
        let bucketClusters = await HashClustering.clusterBucketsParallel(buckets: buckets)
        var allClusters: [[AnalyzedPhoto]] = []
        var clusteredIds = Set<String>()
        for clusters in bucketClusters {
            for cluster in clusters {
                allClusters.append(cluster)
                for p in cluster { clusteredIds.insert(p.assetIdentifier) }
            }
        }
        let unclustered = allMerged.filter { !clusteredIds.contains($0.assetIdentifier) }
        if unclustered.count >= 2 {
            let crossClusters = HashClustering.clusterStrictLSH(photos: unclustered)
            allClusters.append(contentsOf: crossClusters)
        }
        let raw = GroupBuilder.buildGroups(from: allClusters)
        let refinedGroups: [SimilarGroupVM] = raw.map { g in
            let items = GroupBuilder.items(for: g, analyzedIndex: merged)
            return SimilarGroupVM(
                id: g.id,
                count: g.count,
                totalBytes: g.totalBytes,
                confidence: g.confidence,
                createdAt: g.createdAt,
                bestId: g.bestId,
                items: items
            )
        }

        await MainActor.run {
            SimilarPersistence.saveGroups(refinedGroups)
            onPartial(PartialScanData(groups: refinedGroups, analyzedIndex: merged))
        }
    }
}

