import Foundation
import Photos
import AVFoundation
import UIKit
import SwiftUI

// MARK: - CompressViewModel: Photo Library Load
extension CompressViewModel {


    func loadPhotos() async {
        guard !hasLoadedPhotos else { return }
        guard !isLoadingPhotos else { return }
        isLoadingPhotos = true
        scanTotal = 0
        scanProcessed = 0
        // Don't clear `photos` — see loadVideos for the rationale. The
        // Phase 1 cache hydration replaces the array with real data; we
        // never want to flash an empty grid in between.

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isLoadingPhotos = false
            return
        }

        // ── Phase 1: Instant cache hydration (see loadVideos for rationale) ──
        let cachedSnapshots = await ScanCache.shared.loadPhotoSnapshots()
        var knownIDs = Set<String>()
        if !cachedSnapshots.isEmpty {
            let idList = cachedSnapshots.map(\.id)
            let fetchOptions = PHFetchOptions()
            let fetched = PHAsset.fetchAssets(
                withLocalIdentifiers: idList,
                options: fetchOptions
            )
            var assetMap: [String: PHAsset] = [:]
            fetched.enumerateObjects { asset, _, _ in
                assetMap[asset.localIdentifier] = asset
            }
            var hydrated: [PhotoAsset] = []
            hydrated.reserveCapacity(cachedSnapshots.count)
            for snap in cachedSnapshots {
                guard let asset = assetMap[snap.id] else { continue }
                // Defensive type check — mirror of the video hydration guard.
                guard asset.mediaType == .image else { continue }
                hydrated.append(snap.toPhotoAsset(asset: asset))
                knownIDs.insert(snap.id)
            }
            hydrated.sort { $0.potentialSavings > $1.potentialSavings }
            photos = hydrated
            photoTotalSize = hydrated.reduce(0) { $0 + $1.fileSize }
            photoPotentialSavings = hydrated.reduce(0) { $0 + $1.potentialSavings }

            let prefetchAssets = hydrated.prefix(40).compactMap { $0.asset }
            AssetThumbnailCache.shared.prefetch(
                Array(prefetchAssets),
                size: CGSize(width: 300, height: 400),
                limit: 40
            )
        }

        // ── Phase 2: Incremental background scan (skip cached IDs) ──
        let skipIDs = knownIDs
        let result: (added: [PhotoAsset], allIDs: Set<String>) = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

            let results = PHAsset.fetchAssets(with: options)

            // Scan the ENTIRE image library. Pre-filter only skips assets
            // that physically cannot produce a meaningful savings (≤100×100
            // thumbnails / sticker detritus). The real byte threshold is
            // applied post-resource-fetch so we don't miss tiny-but-valuable
            // assets (compressed Instagram downloads, screenshot snippets).
            let minPixels = 10_000
            var candidates: [PHAsset] = []
            candidates.reserveCapacity(results.count)
            results.enumerateObjects { asset, _, _ in
                if asset.pixelWidth * asset.pixelHeight >= minPixels {
                    candidates.append(asset)
                }
            }

            // 20KB floor catches small screenshots, social-app downloads,
            // and meme-sized JPEGs that still compress measurably. Anything
            // smaller than this can't yield a saving worth surfacing.
            let minBytes: Int64 = 20_000

            // Filter out IDs already present in the cache — only process
            // NEW photos. Also capture the canonical current ID set so the
            // caller can prune deleted items from the hydrated list.
            var allCurrentIDs = Set<String>()
            results.enumerateObjects { asset, _, _ in
                allCurrentIDs.insert(asset.localIdentifier)
            }
            candidates.removeAll { skipIDs.contains($0.localIdentifier) }

            let totalCandidates = candidates.count
            await MainActor.run { [weak self] in
                self?.scanTotal = totalCandidates
            }
            guard totalCandidates > 0 else {
                return (added: [], allIDs: allCurrentIDs)
            }

            let loaded = await withTaskGroup(of: PhotoAsset?.self) { group -> [PhotoAsset] in
                // Scale concurrency with the device — modern iPhones (A15+)
                // have 6 cores and can comfortably overlap 24+ PHAssetResource
                // DB round-trips. Older devices stay at a safer ceiling so
                // we don't starve the UI thread during scan.
                // PHAssetResource.assetResources is an I/O-bound Core Data
                // call, not CPU-bound. Pushing past cores*4 stays well
                // under thread-explosion territory but keeps the DB queue
                // saturated. 48 ceiling is empirically the point where
                // PhotoKit starts serializing internally on iOS 17+.
                let cores = ProcessInfo.processInfo.activeProcessorCount
                let concurrency = min(max(cores * 6, 16), 48)
                var iter = candidates.makeIterator()

                func spawn(_ asset: PHAsset) {
                    group.addTask {
                        let resources = PHAssetResource.assetResources(for: asset)
                        // Only consider real photo resources. An earlier
                        // `?? resources.first` fallback could pick up an
                        // `.adjustmentData` sidecar on edited photos whose
                        // fileSize is a few KB of XMP — the asset would then
                        // be silently dropped by the minBytes floor and never
                        // surface in the grid. Photo / fullSizePhoto /
                        // alternatePhoto are the only types that point at
                        // actual pixel data.
                        guard let resource = resources.first(where: { $0.type == .fullSizePhoto })
                            ?? resources.first(where: { $0.type == .photo })
                            ?? resources.first(where: { $0.type == .alternatePhoto }) else { return nil }

                        let fileSize = resource.value(forKey: "fileSize") as? Int64 ?? 0
                        guard fileSize >= minBytes else { return nil }

                        // iCloud-only photos ARE included now — see the video
                        // loader for rationale. The card shows a cloud badge so
                        // the user can anticipate the download on tap.
                        let locallyAvailable = (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
                        let isInCloud = !locallyAvailable

                        var resolution: CGSize?
                        let w = CGFloat(asset.pixelWidth)
                        let h = CGFloat(asset.pixelHeight)
                        if w > 0 && h > 0 {
                            resolution = CGSize(width: w, height: h)
                        }

                        let format = PhotoAsset.detectFormat(from: resource)
                        // Tier 1 source-app detection — cheap filename-prefix
                        // match for Snapchat / WhatsApp / Telegram / Messenger
                        // / TikTok. Runs against the same `resources` array we
                        // already fetched, so the badge lights up on first
                        // load without a second pass over PhotoKit. Instagram
                        // saves as IMG_XXXX.jpg and falls through to nil here
                        // — backfilled by the Tier 2 EXIF sweep on the
                        // similar-photos scan (shared analyzedIndex).
                        let detectedSource: PhotoSource? = {
                            for r in resources {
                                if let s = PhotoKitService.detectSourceFromFilename(r.originalFilename) {
                                    return s
                                }
                            }
                            return nil
                        }()
                        let subtypes = asset.mediaSubtypes

                        // Detect smart-tag content types via mediaSubtypes.
                        let isScreenshot = subtypes.contains(.photoScreenshot)
                        let isLivePhoto  = subtypes.contains(.photoLive)
                        let isHDR        = subtypes.contains(.photoHDR)
                        let isPortrait   = subtypes.contains(.photoDepthEffect)
                        let isPanorama   = subtypes.contains(.photoPanorama)
                        // Burst members expose a non-nil burstIdentifier;
                        // representsBurst marks the primary photo in a set.
                        let isBurst = asset.burstIdentifier != nil || asset.representsBurst

                        let baseSaving = CompressionLevel.medium.estimatedPhotoSavings(
                            from: fileSize,
                            resolution: resolution,
                            sourceFormat: format
                        )

                        // Content-aware savings multiplier:
                        //   • Screenshots are basically PNG-ish UI captures —
                        //     re-encoding to HEIC at q=0.65 slashes their size
                        //     by ~70% on top of whatever the base estimator
                        //     computed. Biggest easy win on any library.
                        //   • Portrait / depth-effect photos carry an
                        //     auxiliary depth map that we preserve only in
                        //     part via the re-encode → × 0.85.
                        //   • Panoramas have enormous redundant sky/ground
                        //     that HEVC-style entropy coding loves → × 1.15.
                        //   • Live Photos pair a still + short video — our
                        //     compressor only touches the still, so the
                        //     reported fileSize overstates real wins → × 0.60.
                        //   • HDR photos reserve bits for extended range →
                        //     × 0.85.
                        var savingsMultiplier: Float = 1.0
                        if isScreenshot { savingsMultiplier *= 1.70 }
                        if isPortrait   { savingsMultiplier *= 0.85 }
                        if isPanorama   { savingsMultiplier *= 1.15 }
                        if isLivePhoto  { savingsMultiplier *= 0.60 }
                        if isHDR        { savingsMultiplier *= 0.85 }
                        // Cap at the original file size — we can't save more
                        // than the file is worth, regardless of multipliers.
                        let scaledSaving = Int64(Float(baseSaving) * savingsMultiplier)
                        let potentialSaving = min(scaledSaving, fileSize)

                        let tags = PhotoSmartTags(
                            isScreenshot: isScreenshot,
                            isLivePhoto: isLivePhoto,
                            isBurst: isBurst,
                            isHDR: isHDR,
                            isPortrait: isPortrait,
                            isPanorama: isPanorama,
                            isSelfie: false  // reserved — needs EXIF round-trip
                        )

                        return PhotoAsset(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: fileSize,
                            potentialSavings: potentialSaving,
                            creationDate: asset.creationDate ?? Date(),
                            resolution: resolution,
                            format: format,
                            isInCloud: isInCloud,
                            tags: tags,
                            sourceApp: detectedSource
                        )
                    }
                }

                for _ in 0..<concurrency {
                    guard let next = iter.next() else { break }
                    spawn(next)
                }

                var collected: [PhotoAsset] = []
                collected.reserveCapacity(candidates.count)

                var processed = 0
                var pendingBatch: [PhotoAsset] = []

                while let photo = await group.next() {
                    if let photo = photo {
                        collected.append(photo)
                        pendingBatch.append(photo)
                    }
                    if let next = iter.next() { spawn(next) }
                    processed += 1

                    // 20-item flush: small enough that cards visibly pop in
                    // on a fast scan, large enough that SwiftUI's diff doesn't
                    // get hammered. Down from 30 to make the grid feel even
                    // more "live" — closer to other cleaner apps' streaming UX.
                    let shouldFlush = pendingBatch.count >= 20 || processed == totalCandidates
                    if shouldFlush || processed % 10 == 0 {
                        let snapshotProcessed = processed
                        let batch = pendingBatch
                        if shouldFlush { pendingBatch.removeAll(keepingCapacity: true) }
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            self.scanProcessed = snapshotProcessed
                            if shouldFlush && !batch.isEmpty {
                                self.photos.append(contentsOf: batch)
                                self.photoTotalSize += batch.reduce(0) { $0 + $1.fileSize }
                                self.photoPotentialSavings += batch.reduce(0) { $0 + $1.potentialSavings }
                            }
                        }
                    }
                }

                return collected
            }

            return (added: loaded, allIDs: allCurrentIDs)
        }.value

        // ── Phase 3: Reconcile cache + delta. See loadVideos. ──
        let addedIds = Set(result.added.map(\.id))
        var merged = photos.filter { result.allIDs.contains($0.id) && !addedIds.contains($0.id) }
        merged.append(contentsOf: result.added)
        merged.sort { $0.potentialSavings > $1.potentialSavings }

        withAnimation(.easeInOut(duration: 0.3)) {
            photos = merged
            photoTotalSize = merged.reduce(0) { $0 + $1.fileSize }
            photoPotentialSavings = merged.reduce(0) { $0 + $1.potentialSavings }
        }
        isLoadingPhotos = false
        hasLoadedPhotos = true

        // ── Phase 4: Persist to disk ──
        let snapshots = merged.map(CachedPhotoSnapshot.init(from:))
        await ScanCache.shared.savePhotoSnapshots(snapshots)

        let prefetchAssets = merged.prefix(40).compactMap { $0.asset }
        AssetThumbnailCache.shared.prefetch(
            Array(prefetchAssets),
            size: CGSize(width: 300, height: 400),
            limit: 40
        )
    }
}

