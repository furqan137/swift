import Foundation
import Photos

// MARK: - Full Scan
extension ScanCoordinator {

    @MainActor
    func runFullScan(
        onProgress: @escaping (PhotoAnalysisProgress) -> Void,
        onPartial: @escaping (PartialScanData) -> Void = { _ in }
    ) async -> ScanResult? {

        var progress = PhotoAnalysisProgress()
        progress.currentPhase = "Requesting photo access…"
        onProgress(progress)

        // 1. Check / request permission
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

        // 2. Load previously analyzed photos from DB (cache acceleration)
        progress.currentPhase = "Loading cache…"
        onProgress(progress)
        let cachedPhotos = await SimilarPersistence.loadCachedPhotos()
        // Defensive: collapse any duplicate cached entries onto the first seen.
        // SwiftData's primary key guarantees uniqueness today but the scan
        // pipeline shouldn't crash if that invariant ever changes.
        var cachedIndex = Dictionary(cachedPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        // 3. Fetch current library assets
        progress.currentPhase = "Fetching photos…"
        onProgress(progress)
        let fetchResult = photoService.fetchAllPhotos()

        // 3b. Prune stale cache entries for photos no longer in the library.
        // Without this, deleted photos accumulate as dead weight in SwiftData
        // and the cache-hit rate inflates (we think we analyzed N photos but
        // only N-K still exist). Collect the current library's IDs first, then
        // diff against the cache and delete orphans.
        let currentIds: Set<String> = {
            var ids = Set<String>()
            ids.reserveCapacity(fetchResult.count)
            fetchResult.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
            return ids
        }()
        let staleIds = cachedIndex.keys.filter { !currentIds.contains($0) }
        if !staleIds.isEmpty {
            await MainActor.run { SimilarPersistence.deletePhotos(assetIds: staleIds) }
            for id in staleIds { cachedIndex.removeValue(forKey: id) }
        }

        let totalCount = fetchResult.count
        guard totalCount > 0 else {
            progress.error = "No photos found in your library."
            progress.isComplete = true
            onProgress(progress)
            return nil
        }

        progress.totalPhotos = totalCount

        // 3c. EARLY SMART-ALBUM PASS (parallel, ~1–2 seconds total).
        //     These four fetches are pure metadata — no per-asset
        //     analysis — so they can complete BEFORE the heavy photo
        //     analysis loop and stream straight to the store via
        //     `onPartial`. The result: Screenshots, Screen Recordings,
        //     Short Videos, and Long Videos cards on Cleanup populate
        //     within seconds of scan start instead of at scan end.
        progress.currentPhase = "Finding videos by type…"
        onProgress(progress)
        async let earlyScreenshotsTask = Task.detached { [weak self] in
            self?.photoService.fetchScreenshots() ?? []
        }.value
        async let earlyScreenRecordingsTask = Task.detached { [weak self] in
            self?.photoService.fetchScreenRecordings() ?? []
        }.value
        async let earlyShortVideosTask = Task.detached { [weak self] in
            self?.photoService.fetchShortVideos() ?? []
        }.value
        async let earlyLongVideosTask = Task.detached { [weak self] in
            self?.photoService.fetchLongVideos() ?? []
        }.value
        let earlyScreenshots = await earlyScreenshotsTask
        let earlyScreenRecordings = await earlyScreenRecordingsTask
        let earlyShortVideos = await earlyShortVideosTask
        let earlyLongVideos = await earlyLongVideosTask

        let earlySSResult = ScreenshotScanResult(
            screenshots: earlyScreenshots,
            totalBytes: earlyScreenshots.reduce(Int64(0)) { $0 + $1.fileSize },
            scannedAt: Date()
        )
        let earlySRResult = ScreenshotScanResult(
            screenshots: earlyScreenRecordings,
            totalBytes: earlyScreenRecordings.reduce(Int64(0)) { $0 + $1.fileSize },
            scannedAt: Date()
        )
        let earlySVResult = ScreenshotScanResult(
            screenshots: earlyShortVideos,
            totalBytes: earlyShortVideos.reduce(Int64(0)) { $0 + $1.fileSize },
            scannedAt: Date()
        )
        let earlyLVResult = ScreenshotScanResult(
            screenshots: earlyLongVideos,
            totalBytes: earlyLongVideos.reduce(Int64(0)) { $0 + $1.fileSize },
            scannedAt: Date()
        )

        // Stream to the store + persist concurrently. The store sees
        // these immediately and re-renders Cleanup cards. The persist
        // step writes the same JSON files that loadFromCache reads on
        // the next launch, so a cancelled scan still leaves the user
        // with up-to-date smart-album results.
        onPartial(PartialScanData(
            screenshotScanResult: earlySSResult,
            screenRecordingScanResult: earlySRResult,
            shortVideoScanResult: earlySVResult,
            longVideoScanResult: earlyLVResult
        ))
        SimilarPersistence.saveScreenshotScanResult(earlySSResult)
        SimilarPersistence.saveScreenRecordingScanResult(earlySRResult)
        SimilarPersistence.saveShortVideoScanResult(earlySVResult)
        SimilarPersistence.saveLongVideoScanResult(earlyLVResult)

        progress.currentPhase = "Analyzing photos…"
        onProgress(progress)

        // 3d. Kick off video analysis IN PARALLEL with the photo batch loop.
        //     Photos use PHImageManager.requestImage (photo daemon's queue);
        //     videos use AVAssetImageGenerator (AVFoundation's own queues).
        //     They don't compete for the same bottleneck, so running them
        //     concurrently turns total = photos + videos into max(photos,
        //     videos) — typically ~30s saved on the field-tested 8k photo
        //     + 200 video library.
        let cachedIndexCopy = cachedIndex
        let videoTask: Task<VideoAnalysisResult, Never> = Task { [weak self] in
            guard let self else { return VideoAnalysisResult(groups: []) }
            var p = PhotoAnalysisProgress()
            return await self.analyzeVideos(
                progress: &p,
                onProgress: { _ in /* swallow; primary progress is the photo loop */ },
                cachedIndex: cachedIndexCopy
            )
        }

        // 4. Analyze in batches.
        //
        // Local-only first pass (`networkAccess: false`) — iCloud-only
        // assets fall back to metadata-only sentinels for now. The
        // background iCloud retry at step 11b downloads + re-analyzes
        // them after the local pass has already populated every card,
        // so the user gets a working app immediately on iCloud-heavy
        // libraries instead of waiting on Wi-Fi round-trips.
        //
        // Incremental clustering — every `intermediateClusterEvery` new
        // photos analyzed, snapshot allPhotos and fire a detached
        // clustering task. The task computes groups on what's analyzed
        // so far and streams them via onPartial. Duplicates / Similar
        // Photos cards START FILLING IN before analysis ends, instead
        // of waiting to the very end. The previous in-flight cluster
        // task is cancelled when a newer one starts so results never
        // arrive out of order.
        var allPhotos: [AnalyzedPhoto] = []
        var newPhotos: [AnalyzedPhoto] = []
        var unpersistedNewPhotos: [AnalyzedPhoto] = []
        let batchSize = Self.adaptiveBatchSize(for: totalCount)
        var throttle = ProgressThrottle(totalCount: totalCount)

        let intermediateClusterEvery = 1500
        var photosSinceLastCluster = 0
        var inFlightCluster: Task<Void, Never>?

        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            if Task.isCancelled {
                // Flush anything we've analyzed so far so the interrupted run
                // isn't wasted — next scan resumes with these already cached.
                inFlightCluster?.cancel()
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
                cachedIndex: cachedIndex,
                networkAccess: false
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
            photosSinceLastCluster += batchResults.count

            // Flush the analysis cache every ~500 new photos so a force-quit,
            // OS suspension, or crash on a huge library doesn't waste minutes
            // of hash computation. Next scan picks up where this one left off.
            if unpersistedNewPhotos.count >= Self.persistenceFlushInterval {
                await Self.flushPersistable(&unpersistedNewPhotos)
            }

            // Incremental cluster trigger — only one in flight at a time.
            // The previous task is cancelled before the new one starts, so
            // the latest snapshot's results win the streaming race.
            if photosSinceLastCluster >= intermediateClusterEvery,
               batchEnd < totalCount /* skip on last batch — final cluster runs anyway */ {
                photosSinceLastCluster = 0
                inFlightCluster?.cancel()
                let snapshot = allPhotos
                let burstSnapshot = PhotoKitService.extractBurstIds(fetchResult)
                inFlightCluster = Task.detached(priority: .utility) {
                    if Task.isCancelled { return }
                    let buckets = TimeBucketing.timeBuckets(photos: snapshot, burstIds: burstSnapshot)
                    if Task.isCancelled { return }
                    let bucketClusters = await HashClustering.clusterBucketsParallel(buckets: buckets)
                    if Task.isCancelled { return }

                    var partials: [[AnalyzedPhoto]] = []
                    var clusteredIds = Set<String>()
                    for clusters in bucketClusters {
                        for cluster in clusters {
                            partials.append(cluster)
                            for p in cluster { clusteredIds.insert(p.assetIdentifier) }
                        }
                    }
                    // Skip cross-bucket LSH on intermediate passes — it adds
                    // ~1s and the next cluster will catch any cross-bucket
                    // matches anyway. Final scan-end pass runs full LSH.
                    let raw = GroupBuilder.buildGroups(from: partials)
                    let snapshotIndex = Dictionary(snapshot.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
                    let groups: [SimilarGroupVM] = raw.map { g in
                        let items = GroupBuilder.items(for: g, analyzedIndex: snapshotIndex)
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
                    if Task.isCancelled { return }
                    await MainActor.run {
                        onPartial(PartialScanData(
                            groups: groups,
                            analyzedIndex: snapshotIndex
                        ))
                    }
                }
            }

            if throttle.shouldReport(current: batchEnd, total: totalCount) {
                progress.processedPhotos = batchEnd
                progress.currentPhase = "Analyzed \(batchEnd)/\(totalCount) photos"
                onProgress(progress)
            }
        }

        // Wait for the last in-flight intermediate cluster to settle, then
        // cancel — the final clustering pass below produces the
        // authoritative result.
        inFlightCluster?.cancel()

        // 5. Flush any remaining unpersisted photos.
        await Self.flushPersistable(&unpersistedNewPhotos)

        // 5b. Signal that photo analysis is done — the store flips
        //     `isRunningFullScan = false` and `isClusteringPhotos = true`
        //     so the non-clustering cards (Other / Screenshots / Blurry /
        //     Recordings / Short / Long) light up with real counts NOW
        //     instead of waiting on the clustering passes that follow.
        let preliminaryIndex = Dictionary(allPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
        onPartial(PartialScanData(
            analyzedIndex: preliminaryIndex,
            photoAnalysisDidComplete: true,
            photoClusteringDidStart: true,
            screenshotClusteringDidStart: true,
            videoClusteringDidStart: true
        ))

        // 5d. Kick off screenshot analysis+clustering IN PARALLEL with the
        //     photo clustering pass that follows. Photo cache rows have
        //     just been flushed (step 5), so the screenshot pass hits the
        //     cache for nearly every asset and runs fast — but it still
        //     has its own cluster pass that can overlap with photo
        //     clustering. Saves ~2-5s on a typical 8k+2k library.
        let screenshotTask: Task<ScreenshotAnalysisResult, Never> = Task { [weak self] in
            guard let self else { return ScreenshotAnalysisResult(groups: [], scanResult: .empty) }
            var p = PhotoAnalysisProgress()
            return await self.analyzeScreenshots(
                progress: &p,
                onProgress: { _ in /* swallow */ },
                cachedIndex: cachedIndex
            )
        }

        // 5c. Checkpoint scan summary AFTER analysis completes, BEFORE the
        //     slow clustering passes. This is the load-bearing fix for the
        //     "infinite Scanning…" bug — if the user kills the app any time
        //     after this point, the next launch will see lastScanDate set and
        //     boot through the cached path instead of restarting a full scan.
        let analysisCheckpoint = ScanSummary(
            similarGroupsCount: 0,
            similarToCleanCount: 0,
            duplicateGroupsCount: 0,
            duplicateToCleanCount: 0,
            screenshotCount: earlySSResult.count,
            screenshotTotalBytes: earlySSResult.totalBytes,
            screenshotGroupsCount: 0,
            screenshotToCleanCount: 0,
            videoGroupsCount: 0,
            videoToCleanCount: 0,
            screenRecordingCount: earlySRResult.count,
            screenRecordingTotalBytes: earlySRResult.totalBytes,
            shortVideoCount: earlySVResult.count,
            shortVideoTotalBytes: earlySVResult.totalBytes,
            longVideoCount: earlyLVResult.count,
            longVideoTotalBytes: earlyLVResult.totalBytes,
            lastScanDate: Date()
        )
        await MainActor.run { SimilarPersistence.saveScanSummary(analysisCheckpoint) }

        // 6. Build index — last-wins on duplicate IDs. In practice PHFetchResult
        //    never returns duplicate localIdentifiers, but a crash here would
        //    take the whole scan down for a single bad library state.
        let analyzedIndex = Dictionary(allPhotos.map { ($0.assetIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })

        // 7. Time-bucket — burst IDs override the time window so multi-frame
        // bursts cluster together regardless of how long they ran.
        progress.currentPhase = "Grouping by time…"
        onProgress(progress)
        let burstIds = PhotoKitService.extractBurstIds(fetchResult)
        let buckets = TimeBucketing.timeBuckets(photos: allPhotos, burstIds: burstIds)

        // 8. Cluster within each bucket (burst-mode, relaxed threshold).
        //    Parallel per-bucket — buckets are independent so they fan out
        //    across cores. Cuts photo-clustering wall-clock from ~1.5s to
        //    ~250ms on the field-tested 8k library.
        progress.currentPhase = "Finding similar photos…"
        onProgress(progress)
        var allClusters: [[AnalyzedPhoto]] = []
        var clusteredIds = Set<String>()
        let bucketClusters = await HashClustering.clusterBucketsParallel(buckets: buckets)
        for clusters in bucketClusters {
            for cluster in clusters {
                allClusters.append(cluster)
                for photo in cluster { clusteredIds.insert(photo.assetIdentifier) }
            }
        }

        // 8b. Cross-bucket pass: photos NOT yet clustered get a second
        //     chance with a stricter threshold. This catches duplicates of
        //     the same subject taken on different days / trips that land
        //     in separate time buckets above. Without this, only within-
        //     burst duplicates are detected.
        let unclustered = allPhotos.filter { !clusteredIds.contains($0.assetIdentifier) }
        if unclustered.count >= 2 {
            // LSH scales sub-quadratically, so this now completes in a few
            // seconds even on 100k+ libraries where clusterStrict would
            // have ground the device.
            let crossClusters = HashClustering.clusterStrictLSH(photos: unclustered)
            allClusters.append(contentsOf: crossClusters)
        }

        // 9. Build groups
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

        // 10. Persist groups + stream them to the store immediately so
        //     the Duplicates / Similar Photos / Other Photos / Blurry
        //     cards on Cleanup populate the moment photo analysis ends,
        //     instead of waiting for screenshot + video clustering to
        //     finish too. Background variant avoids stalling the main
        //     thread during the large group-list flush.
        SimilarPersistence.saveGroupsBackground(groups)
        onPartial(PartialScanData(
            groups: groups,
            analyzedIndex: analyzedIndex
        ))

        // 10b. Refresh the scan-summary checkpoint with photo-group counts
        //      now that clustering is done. Same rationale as 5b: if the user
        //      kills the app between here and the screenshot/video phases,
        //      the cached summary still reflects accurate Duplicates +
        //      Similar Photos counts on next launch.
        let duplicateCount = groups.filter { $0.confidence >= 0.85 }.count
        let similarCount = groups.count - duplicateCount
        let postPhotoCheckpoint = ScanSummary(
            similarGroupsCount: similarCount,
            similarToCleanCount: 0,
            duplicateGroupsCount: duplicateCount,
            duplicateToCleanCount: 0,
            screenshotCount: earlySSResult.count,
            screenshotTotalBytes: earlySSResult.totalBytes,
            screenshotGroupsCount: 0,
            screenshotToCleanCount: 0,
            videoGroupsCount: 0,
            videoToCleanCount: 0,
            screenRecordingCount: earlySRResult.count,
            screenRecordingTotalBytes: earlySRResult.totalBytes,
            shortVideoCount: earlySVResult.count,
            shortVideoTotalBytes: earlySVResult.totalBytes,
            longVideoCount: earlyLVResult.count,
            longVideoTotalBytes: earlyLVResult.totalBytes,
            lastScanDate: Date()
        )
        await MainActor.run { SimilarPersistence.saveScanSummary(postPhotoCheckpoint) }

        // 11. Capture actual screenshot IDs
        let realScreenshotIds = await Task.detached { [weak self] in
            self?.photoService.fetchActualScreenshotIds() ?? []
        }.value

        // 12. Await the screenshot analysis+clustering task we kicked off
        //     in step 5d. By the time we reach this point it's usually
        //     already finished — this is just the join.
        progress.currentPhase = "Finalizing screenshots…"
        onProgress(progress)
        let screenshotResult = await screenshotTask.value
        onPartial(PartialScanData(screenshotGroups: screenshotResult.groups))

        // 13. Await the video analysis task we kicked off at step 3d so it
        //     was running in parallel with the photo batch loop. By the time
        //     we reach this point, video analysis is usually already done —
        //     this is just the join.
        progress.currentPhase = "Finalizing videos…"
        onProgress(progress)
        let videoResult = await videoTask.value
        onPartial(PartialScanData(videoGroups: videoResult.groups))

        // 14–16. Smart-album fetches were already done in step 3c (early
        // pass) — reuse those results here so the final ScanSummary has
        // accurate counts without re-fetching.
        let srResult = earlySRResult
        let svResult = earlySVResult
        let lvResult = earlyLVResult

        // 17. Build scan summary
        let scanSummary = buildScanSummary(
            groups: groups,
            screenshotGroups: screenshotResult.groups,
            videoGroups: videoResult.groups,
            screenshotScanResult: screenshotResult.scanResult,
            screenRecordingScanResult: srResult,
            shortVideoScanResult: svResult,
            longVideoScanResult: lvResult
        )
        let duplicateScanResult = buildDuplicateScanResult(groups: groups)
        await MainActor.run {
            SimilarPersistence.saveScanSummary(scanSummary)
            SimilarPersistence.saveDuplicateScanResult(duplicateScanResult)
        }

        progress.currentPhase = "Complete"
        progress.isComplete = true
        onProgress(progress)

        HiveStatsManager.shared.recordScanCompleted()

        // Recompute the coin pool (maxLifetimeCoins = (photos + videos) * 10)
        // and regenerate level requirements from the freshly scanned library.
        let videoCount = photoService.fetchAllVideos().count
        await ProgressManager.shared.syncLibrary(totalPhotos: totalCount, totalVideos: videoCount)

        // 18. iCloud retry — re-analyze photos that failed local-only.
        //
        // Why: step 4 disabled network access for the main analysis loop so
        // the user gets a fully populated app within 12-15s, even on
        // iCloud-heavy libraries. The cost of that decision is that
        // iCloud-only assets enter analyzedIndex with a metadata-only
        // sentinel (dHash=0, sharpness=-1) and never join clustering. This
        // background pass downloads + re-analyzes them, persists the real
        // hashes, then re-clusters everything and streams the updated
        // groups so the four clustering cards refine themselves.
        //
        // Detached + non-blocking: the function returns the local-pass
        // result NOW. The retry runs at .background priority so it never
        // contends with foreground UI work, and uses concurrency=8 (lower
        // than the photo daemon path) because iCloud is bandwidth-bound,
        // not CPU-bound.
        let metadataOnlyIds = allPhotos
            .filter { PhotoAnalyzer.isMetadataOnly($0) }
            .map(\.assetIdentifier)
        if !metadataOnlyIds.isEmpty {
            let analyzerCopy = self.analyzer
            let analyzedSnapshot = analyzedIndex
            Task.detached(priority: .background) {
                await Self.runICloudRetry(
                    assetIds: metadataOnlyIds,
                    analyzer: analyzerCopy,
                    seedIndex: analyzedSnapshot,
                    onPartial: onPartial
                )
            }
        }

        return ScanResult(
            groups: groups,
            screenshotGroups: screenshotResult.groups,
            videoGroups: videoResult.groups,
            screenshotScanResult: screenshotResult.scanResult,
            screenRecordingScanResult: srResult,
            shortVideoScanResult: svResult,
            longVideoScanResult: lvResult,
            scanSummary: scanSummary,
            duplicateScanResult: duplicateScanResult,
            analyzedIndex: analyzedIndex,
            realScreenshotIds: realScreenshotIds
        )
    }
}
