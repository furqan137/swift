import Foundation
import Photos
import UIKit
import CoreML
import Combine

/// On-device CLIP photo indexer.
///
/// Runs on a dedicated background queue, pauses under thermal pressure
/// or low battery, and supports cancellation + resumption across app launches.
final class CLIPPhotoIndexer: ObservableObject {

    static let shared = CLIPPhotoIndexer()

    // MARK: - Published state

    @Published var progress = Progress(totalUnitCount: 0)
    @Published var isIndexing = false
    @Published var statusLine = ""

    // MARK: - Private state

    private let store = CLIPEmbeddingStore.shared
    private var imgEncoder: ImgEncoder?
    private var currentTask: Task<Void, Never>?
    private var isCancelled = false
    private let batchSize = 50

    // MARK: - Public API

    /// Whether the indexer is currently running. Callable from any actor.
    @MainActor func isCurrentlyIndexing() -> Bool { isIndexing }

    /// Start (or resume) the local CLIP indexing pipeline.
    /// Safe to call multiple times — subsequent calls are no-ops while running.
    func start() {
        guard currentTask == nil else { return }
        isCancelled = false
        currentTask = Task { [weak self] in
            await self?.run()
            let weakSelf = self
            await MainActor.run {
                weakSelf?.currentTask = nil
            }
        }
    }

    /// Cancel the current run. Can be resumed later by calling `start()`.
    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            isIndexing = false
            statusLine = "Paused"
        }
    }

    // MARK: - Core pipeline

    private func run() async {
        await MainActor.run {
            isIndexing = true
            statusLine = "Preparing…"
        }

        // 1. Load model
        do {
            if imgEncoder == nil {
                guard let baseURL = Bundle.main.resourceURL else {
                    throw NSError(
                        domain: "CLIPIndexer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Bundle resource URL is nil"]
                    )
                }
                print("[CLIPIndexer] Loading ImgEncoder from \(baseURL.path)…")
                imgEncoder = try ImgEncoder(resourcesAt: baseURL)
                print("[CLIPIndexer] ImgEncoder loaded successfully")
            }
        } catch {
            print("[CLIPIndexer] Failed to load ImgEncoder: \(error)")
            await MainActor.run {
                AnalyticsService.shared.log("clip_model_load_failed", properties: [
                    "error": error.localizedDescription,
                    "device": UIDevice.current.model,
                    "os": UIDevice.current.systemVersion
                ])
                isIndexing = false
                statusLine = "Model load failed. Tap to retry."
            }
            return
        }

        // 2. Purge stale embeddings from previous model versions
        store.purgeStaleVersions(keeping: CLIPConfig.clipModelVersion)

        // 3. Fetch all image asset IDs from the photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

        var allAssetIds = [String]()
        allAssetIds.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            allAssetIds.append(asset.localIdentifier)
        }

        // 4. Find which assets still need encoding
        let missing = store.missingAssetIds(from: allAssetIds)
        let pendingIds = allAssetIds.filter { missing.contains($0) }

        if pendingIds.isEmpty {
            await MainActor.run {
                isIndexing = false
                statusLine = "Up to date"
                progress = Progress(totalUnitCount: 1)
                progress.completedUnitCount = 1
            }
            print("[CLIPIndexer] All \(allAssetIds.count) photos already indexed")
            return
        }

        await MainActor.run {
            progress = Progress(totalUnitCount: Int64(pendingIds.count))
            progress.completedUnitCount = 0
            statusLine = "Indexing 0/\(pendingIds.count)…"
        }

        print("[CLIPIndexer] \(pendingIds.count) photos to index (\(allAssetIds.count) total)")

        // 5. Build a lookup for PHAssets by ID
        let pendingSet = Set(pendingIds)
        var assetMap = [String: PHAsset]()
        assetMap.reserveCapacity(pendingIds.count)
        fetchResult.enumerateObjects { asset, _, _ in
            if pendingSet.contains(asset.localIdentifier) {
                assetMap[asset.localIdentifier] = asset
            }
        }

        // 6. Process in batches
        var processed = 0
        for batchStart in stride(from: 0, to: pendingIds.count, by: batchSize) {
            // --- Cancellation check ---
            if isCancelled || Task.isCancelled { break }

            // --- Thermal / battery gate ---
            await waitForSafeConditions()

            if isCancelled || Task.isCancelled { break }

            let batchEnd = min(batchStart + batchSize, pendingIds.count)
            let batchIds = Array(pendingIds[batchStart..<batchEnd])

            for assetId in batchIds {
                if isCancelled || Task.isCancelled { break }

                guard let asset = assetMap[assetId] else { continue }

                do {
                    // Request thumbnail
                    guard let thumbnail = await requestThumbnail(for: asset) else {
                        continue
                    }

                    // Encode (returns L2-normalized embedding)
                    guard let encoder = imgEncoder else { break }
                    let embedding = try await encoder.computeImgEmbedding(img: thumbnail)

                    // Extract [Float] and upsert into store
                    let floats = embedding.scalars.map { Float($0) }
                    store.upsert(assetId: assetId, embedding: floats)

                    processed += 1
                    let p = processed
                    let total = pendingIds.count
                    await MainActor.run {
                        progress.completedUnitCount = Int64(p)
                        statusLine = "Indexing \(p)/\(total)…"
                    }
                } catch {
                    print("[CLIPIndexer] Failed to encode \(assetId.prefix(12)): \(error)")
                }
            }

            // Flush IOSurface pool after each batch to prevent exhaustion
            ImgEncoder.flushBufferPool()
        }

        let finalCount = store.count()
        await MainActor.run {
            isIndexing = false
            statusLine = isCancelled ? "Paused" : "Done — \(finalCount) photos indexed"
        }
        print("[CLIPIndexer] Finished — \(processed) new, \(finalCount) total")
    }

    // MARK: - Yield to face indexing

    // MARK: - Thermal / battery guards

    /// Block until thermal state is acceptable and battery is sufficient.
    private func waitForSafeConditions() async {
        var isBlocked = false
        while !isCancelled && !Task.isCancelled {
            let dominated = await thermalOrBatteryDominated()
            let memoryPressure = MemoryPressureMonitor.shared.isUnderMemoryPressure

            if !dominated && !memoryPressure { break }

            if !isBlocked {
                isBlocked = true
                let reason = memoryPressure ? "low memory" : "thermal or low battery"
                print("[CLIPIndexer] Pausing — \(reason)")
                await MainActor.run {
                    statusLine = memoryPressure
                        ? "Paused — low memory"
                        : "Paused — device is hot or low battery"
                }
            }
            try? await Task.sleep(for: .seconds(10))
        }
        if isBlocked {
            print("[CLIPIndexer] Conditions OK — resuming")
        }
    }

    @MainActor
    private func thermalOrBatteryDominated() -> Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical { return true }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let isCharging = state == .charging || state == .full
        if level >= 0 && level < 0.2 && !isCharging { return true }

        return false
    }

    // MARK: - Thumbnail loading

    private func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        // Race the image request against a 30-second timeout. For iCloud-
        // optimized photos on slow networks, this prevents indefinite hangs.
        // If timeout fires first, return nil and the indexer skips the asset.
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let options = PHImageRequestOptions()
                    options.deliveryMode = .highQualityFormat
                    options.resizeMode = .fast
                    options.isNetworkAccessAllowed = true
                    options.isSynchronous = false

                    var resumed = false
                    let lock = NSLock()

                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: CGSize(width: 256, height: 256),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        lock.lock()
                        let alreadyResumed = resumed
                        resumed = true
                        lock.unlock()
                        guard !alreadyResumed else { return }
                        continuation.resume(returning: image)
                    }
                }
            }

            // Timeout task - fires after 30 seconds
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return nil
            }

            // Return the first result (either image or timeout)
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

}
