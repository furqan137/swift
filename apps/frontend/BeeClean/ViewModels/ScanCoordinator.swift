import Foundation
import Photos

// MARK: - Scan Result
struct ScanResult {
    var groups: [SimilarGroupVM]
    var screenshotGroups: [SimilarGroupVM]
    var videoGroups: [SimilarGroupVM]
    var screenshotScanResult: ScreenshotScanResult
    var screenRecordingScanResult: ScreenshotScanResult
    var shortVideoScanResult: ScreenshotScanResult
    var longVideoScanResult: ScreenshotScanResult
    var scanSummary: ScanSummary
    var duplicateScanResult: DuplicateScanResult
    var analyzedIndex: [String: AnalyzedPhoto]
    var realScreenshotIds: Set<String>
}

// MARK: - Partial Scan Result
//
// Streaming intermediates the scan emits as each phase completes, so the
// store can populate Cleanup cards INCREMENTALLY instead of waiting for
// the entire scan to finish before showing anything. Smart-album phases
// (1–2 seconds) land first, photo-analysis groups (30–120 seconds) land
// next, screenshot/video clustering lands after that. Every field is
// optional — only the fields the just-completed phase produced are
// non-nil on a given emission.
struct PartialScanData {
    var screenshotScanResult: ScreenshotScanResult?
    var screenRecordingScanResult: ScreenshotScanResult?
    var shortVideoScanResult: ScreenshotScanResult?
    var longVideoScanResult: ScreenshotScanResult?
    var groups: [SimilarGroupVM]?
    var screenshotGroups: [SimilarGroupVM]?
    var videoGroups: [SimilarGroupVM]?
    var analyzedIndex: [String: AnalyzedPhoto]?

    /// Phase transitions the store latches onto for granular flag flips.
    /// Each is a one-shot signal — the coordinator emits it at most once
    /// per scan when the matching phase boundary is crossed.
    var photoAnalysisDidComplete: Bool = false
    var photoClusteringDidStart: Bool = false
    var screenshotClusteringDidStart: Bool = false
    var videoClusteringDidStart: Bool = false
}

// MARK: - Scan Coordinator
/// Runs the full scan pipeline. NOT @MainActor — heavy work runs off main thread.
/// Reports progress via callback; returns final ScanResult.
final class ScanCoordinator: Sendable {

    let photoService: PhotoKitService
    let analyzer = PhotoAnalyzer()

    @MainActor
    init() {
        self.photoService = PhotoKitService.shared
    }

    // MARK: - Scale tuning
    //
    // These knobs make the scan self-adjust to library size. Sequential,
    // fixed-batch-of-20 analysis was the main reason the scan felt slow on
    // libraries ≥ 5k photos — PHImageManager handles concurrent requests
    // well, so running N analyses in parallel per batch gives a ~4–6×
    // real-device speedup. The concurrency ceiling is kept conservative to
    // avoid thermal throttling and to leave headroom for UI responsiveness.

    /// Max concurrent PHImageManager requests per batch.
    /// Bumped 8 → 12 → 20 after measuring on the user's 8k+ library.
    /// PHImageManager is mostly daemon-IPC + decode work, not pinned to a
    /// single hardware core, so the previous 12-deep queue was leaving
    /// performance cores idle on A17/A18-class hardware. 20 saturates the
    /// daemon's own queue without crossing the thermal-throttle threshold
    /// observed on older A15/A16 devices in field testing. iCloud-only
    /// assets still bottleneck on bandwidth — that's the network, not us.
    static let analysisConcurrency = 20

    /// Persist the new-photo queue whenever it crosses this many entries.
    /// Keeps SwiftData transaction sizes moderate while still making
    /// interrupted scans recoverable — on a 200k library a crash 80% of the
    /// way through costs at most 500 photos of re-analysis.
    static let persistenceFlushInterval = 500

    /// Flushes `unpersisted` to SwiftData and clears the buffer. The caller
    /// passes the buffer by reference so we can only swap the in-memory copy
    /// once — no accidental double-saves on retry.
    @MainActor
    static func flushPersistable(_ unpersisted: inout [AnalyzedPhoto]) async {
        guard !unpersisted.isEmpty else { return }
        let batch = unpersisted
        unpersisted.removeAll(keepingCapacity: true)
        SimilarPersistence.savePhotos(batch)
    }

    /// Batch size grows with library size so huge libraries don't pay the
    /// per-batch progress/sleep overhead 50,000 times over. Small libraries
    /// keep a tight batch so the progress bar still feels live.
    static func adaptiveBatchSize(for total: Int) -> Int {
        if total < 500 { return 20 }
        if total < 5000 { return 40 }
        if total < 20000 { return 80 }
        return 120
    }

    /// Throttles progress callbacks so the UI isn't spammed with updates
    /// on huge scans. Reports on time-elapsed OR count-delta, whichever hits
    /// first, plus a forced final report.
    struct ProgressThrottle {
        var lastReport: Date = .distantPast
        var lastCount: Int = 0
        let intervalSeconds: TimeInterval
        let minCountDelta: Int

        init(totalCount: Int) {
            self.intervalSeconds = 0.20
            // At least 100 photos between reports, or 1% of total, whichever is larger.
            self.minCountDelta = max(100, totalCount / 100)
        }

        mutating func shouldReport(current: Int, total: Int) -> Bool {
            if current >= total { // always report completion
                lastReport = Date(); lastCount = current; return true
            }
            let now = Date()
            if now.timeIntervalSince(lastReport) >= intervalSeconds
                || current - lastCount >= minCountDelta {
                lastReport = now
                lastCount = current
                return true
            }
            return false
        }
    }

    /// Parallel batch analysis with a cached-hit fast path.
    ///
    /// Order is NOT preserved across the fresh set — downstream code either
    /// sorts by creationDate (TimeBucketing) or doesn't depend on order.
    ///
    /// Concurrency is bounded by `analysisConcurrency` using a "seed then
    /// replace on completion" pattern so we never queue more than N in-
    /// flight PHImageManager requests at once.
    ///
    /// `networkAccess: false` skips iCloud downloads — the first scan pass
    /// runs local-only so the user sees real counts before any network
    /// round-trip; iCloud-only assets fall back to metadata-only sentinels
    /// and are picked up by the background iCloud retry pass.
    func processBatchWithCache(
        fetchResult: PHFetchResult<PHAsset>,
        startIndex: Int,
        endIndex: Int,
        cachedIndex: [String: AnalyzedPhoto],
        networkAccess: Bool = true
    ) async -> [(photo: AnalyzedPhoto, isNew: Bool)] {
        let analyzer = self.analyzer
        var results: [(photo: AnalyzedPhoto, isNew: Bool)] = []
        results.reserveCapacity(endIndex - startIndex)

        var toAnalyze: [PHAsset] = []
        toAnalyze.reserveCapacity(endIndex - startIndex)
        for index in startIndex..<endIndex {
            let asset = fetchResult.object(at: index)
            if let cached = cachedIndex[asset.localIdentifier] {
                results.append((cached, false))
            } else {
                toAnalyze.append(asset)
            }
        }

        guard !toAnalyze.isEmpty else { return results }

        // PHCachingImageManager pre-warm — the photo daemon starts
        // pre-decoding the entire batch's thumbnails BEFORE we ask for
        // them in the TaskGroup. Each `analyzer.analyzeAsset` then hits
        // a warm cache instead of paying the cold-decode cost (typically
        // 30-80ms per asset). For a 50k library batched at 200 assets,
        // this can shave seconds off each batch's wall-clock time.
        let cacheTargetSize = CGSize(width: 128, height: 128)
        let cacheOptions = PHImageRequestOptions()
        cacheOptions.deliveryMode = .fastFormat
        cacheOptions.resizeMode = .fast
        cacheOptions.isNetworkAccessAllowed = false
        let mgr = photoService.imageManager
        mgr.startCachingImages(
            for: toAnalyze,
            targetSize: cacheTargetSize,
            contentMode: .aspectFill,
            options: cacheOptions
        )
        defer {
            mgr.stopCachingImages(
                for: toAnalyze,
                targetSize: cacheTargetSize,
                contentMode: .aspectFill,
                options: cacheOptions
            )
        }

        let concurrency = min(Self.analysisConcurrency, toAnalyze.count)
        let analyzed: [AnalyzedPhoto] = await withTaskGroup(of: AnalyzedPhoto.self) { group in
            var iterator = toAnalyze.makeIterator()
            for _ in 0..<concurrency {
                guard let asset = iterator.next() else { break }
                group.addTask { await analyzer.analyzeAsset(asset, networkAccess: networkAccess) }
            }
            var collected: [AnalyzedPhoto] = []
            collected.reserveCapacity(toAnalyze.count)
            while let photo = await group.next() {
                collected.append(photo)
                if let asset = iterator.next() {
                    group.addTask { await analyzer.analyzeAsset(asset, networkAccess: networkAccess) }
                }
            }
            return collected
        }

        for photo in analyzed {
            results.append((photo, true))
        }
        return results
    }

    func buildScanSummary(
        groups: [SimilarGroupVM],
        screenshotGroups: [SimilarGroupVM],
        videoGroups: [SimilarGroupVM],
        screenshotScanResult: ScreenshotScanResult,
        screenRecordingScanResult: ScreenshotScanResult,
        shortVideoScanResult: ScreenshotScanResult,
        longVideoScanResult: ScreenshotScanResult
    ) -> ScanSummary {
        let duplicateGroupVMs = groups.filter { $0.confidence >= 0.85 }
        let similarGroupVMs = groups.filter { $0.confidence < 0.85 }

        return ScanSummary(
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
    }

    func buildDuplicateScanResult(groups: [SimilarGroupVM]) -> DuplicateScanResult {
        let duplicateGroupVMs = groups.filter { $0.confidence >= 0.85 }
        let dupGroups = duplicateGroupVMs.map { g in
            PhotoDuplicateGroup(
                id: g.id,
                keepAssetId: g.bestId,
                deleteAssetIds: g.items.filter { $0.assetId != g.bestId }.map(\.assetId),
                confidence: g.confidence,
                totalBytes: g.totalBytes
            )
        }
        return DuplicateScanResult(groups: dupGroups, scannedAt: Date())
    }
}
