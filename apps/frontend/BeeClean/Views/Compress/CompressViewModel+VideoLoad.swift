import Foundation
import Photos
import AVFoundation
import UIKit
import SwiftUI

// MARK: - CompressViewModel: Video Library Load
extension CompressViewModel {


    func loadVideos() async {
        // Concurrency guards. `hasLoadedVideos` short-circuits a re-entry
        // after a successful scan; `isLoadingVideos` prevents two scans
        // racing on the same array if `ensureLoaded` is called twice
        // before the first finishes.
        guard !hasLoadedVideos else { return }
        guard !isLoadingVideos else { return }
        isLoadingVideos = true
        scanTotal = 0
        scanProcessed = 0
        // Don't blow away `videos` here. If we got interrupted on a
        // previous pass we may already have hydrated cards on screen —
        // wiping them would flash the loading view at the user. The
        // Phase 1 cache hydration below recomputes the array, and Phase 3
        // re-publishes the merged authoritative list at the end. Either
        // way, the existing array is overwritten by real data, not by
        // an empty placeholder.

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isLoadingVideos = false
            return
        }

        // ── Phase 1: Instant cache hydration ──
        // If we've scanned before, publish the cached grid immediately (one
        // batch PHAsset fetch, no per-asset DB round-trips). User sees the
        // full list within ~50ms of opening the tab — no spinner, no wait.
        let cachedSnapshots = await ScanCache.shared.loadVideoSnapshots()
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
            var hydrated: [VideoAsset] = []
            hydrated.reserveCapacity(cachedSnapshots.count)
            for snap in cachedSnapshots {
                // Drop snapshots whose underlying PHAsset no longer exists
                // (user deleted the clip between app sessions).
                guard let asset = assetMap[snap.id] else { continue }
                // Defensive type check — see scanAndAppendVideos for the
                // full rationale. If a localIdentifier was once a video and
                // somehow got reassigned to a different mediaType after a
                // deep iCloud reset, the cache hydration would otherwise
                // surface that asset as a video. The check costs O(1) per
                // entry and closes the last cross-category leak path.
                guard asset.mediaType == .video else { continue }
                hydrated.append(snap.toVideoAsset(asset: asset))
                knownIDs.insert(snap.id)
            }
            hydrated.sort { $0.potentialSavings > $1.potentialSavings }
            videos = hydrated
            videoTotalSize = hydrated.reduce(0) { $0 + $1.fileSize }
            videoPotentialSavings = hydrated.reduce(0) { $0 + $1.potentialSavings }

            // Prefetch thumbnails for the first viewport of cached cards —
            // the grid is already visible, this just ensures thumbs show.
            let prefetchAssets = hydrated.prefix(40).compactMap { $0.asset }
            AssetThumbnailCache.shared.prefetch(
                Array(prefetchAssets),
                size: CGSize(width: 300, height: 400),
                limit: 40
            )
        }

        // ── Phase 2: Incremental background scan ──
        // Only PHAssetResource-fetch IDs not already in the cache. First
        // launch = full scan. Subsequent launches = delta (usually empty
        // or just a handful of new captures since last open).
        let skipIDs = knownIDs
        let result: (added: [VideoAsset], allIDs: Set<String>) = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

            let results = PHAsset.fetchAssets(with: options)

            // "Scan the ENTIRE camera roll" — the pre-filter is intentionally
            // loose. We only skip assets that physically cannot yield
            // meaningful savings (zero-dimension placeholders or sub-second
            // clips where keyframe overhead wipes out any compression win).
            // Byte threshold is applied AFTER the resource fetch so we don't
            // miss genuinely small-but-valuable assets.
            // 0.5s captures short Boomerangs / iMessage loops; 160×120 is
            // the practical floor below which we can't even produce a usable
            // thumbnail. 50KB byte floor lets us include compressed GIF
            // imports and downloaded TikTok / Reels clips that other cleaner
            // apps surface as a saving.
            let minDuration: TimeInterval = 0.5
            let minPixels = 160 * 120
            let minBytes: Int64 = 50_000

            var candidates: [PHAsset] = []
            var allCurrentIDs = Set<String>()
            candidates.reserveCapacity(results.count)
            results.enumerateObjects { asset, _, _ in
                allCurrentIDs.insert(asset.localIdentifier)
                guard asset.duration >= minDuration else { return }
                guard asset.pixelWidth * asset.pixelHeight >= minPixels else { return }
                // Cache-first path: skip IDs we've already scanned. On a
                // repeat visit, this usually drops the candidate list to
                // just the handful of clips recorded since last open.
                if skipIDs.contains(asset.localIdentifier) { return }
                candidates.append(asset)
            }

            // If there's nothing new to scan, short-circuit. The caller
            // has already published the cached hydration and just needs
            // to see zero new items + the canonical ID set for cleanup.
            let totalCandidates = candidates.count
            await MainActor.run { [weak self] in
                self?.scanTotal = totalCandidates
            }
            guard totalCandidates > 0 else {
                return (added: [], allIDs: allCurrentIDs)
            }

            let loaded = await withTaskGroup(of: VideoAsset?.self) { group -> [VideoAsset] in
                // Scale concurrency with the device — modern iPhones (A15+)
                // have 6 cores and can comfortably overlap 24+ PHAssetResource
                // DB round-trips. Older devices stay at a safer ceiling so
                // we don't starve the UI thread during scan.
                // Same I/O-bound rationale as loadPhotos — bump the ceiling
                // to 48 so a 4000-clip library completes the resource sweep
                // in seconds rather than tens of seconds.
                let cores = ProcessInfo.processInfo.activeProcessorCount
                let concurrency = min(max(cores * 6, 16), 48)
                var iter = candidates.makeIterator()

                func spawn(_ asset: PHAsset) {
                    group.addTask {
                        let resources = PHAssetResource.assetResources(for: asset)
                        // Prefer the actual video resource, not a thumbnail
                        // or adjustment-data sidecar that happens to be first.
                        guard let resource = resources.first(where: {
                            $0.type == .video || $0.type == .fullSizeVideo
                        }) ?? resources.first else { return nil }

                        let fileSize = resource.value(forKey: "fileSize") as? Int64 ?? 0
                        guard fileSize >= minBytes else { return nil }

                        // PHAssetResource reports fileSize even for iCloud-only
                        // items (it's cached metadata), so we include them here
                        // instead of skipping. The compressor's network flag is
                        // already set, and the card shows a cloud badge so the
                        // user knows a tap will trigger an iCloud download.
                        let locallyAvailable = (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
                        let isInCloud = !locallyAvailable

                        let duration = max(asset.duration, 0)
                        let subtypes = asset.mediaSubtypes
                        let isHighFrameRate = subtypes.contains(.videoHighFrameRate)
                        let isTimelapse = subtypes.contains(.videoTimelapse)
                        // `videoCinematic` is iOS 16+. Fall back to raw bit
                        // value on older runtimes so the scan doesn't crash
                        // on a deployment target that predates the symbol.
                        let isCinematic: Bool = {
                            if #available(iOS 16.0, *) {
                                let cinematicBit = PHAssetMediaSubtype(rawValue: 1 << 21)
                                return subtypes.contains(cinematicBit)
                            }
                            return false
                        }()

                        // Tier 1 source-app detection — same filename-prefix
                        // match the photo loader uses. Catches Snapchat /
                        // WhatsApp / Telegram / Messenger / TikTok video
                        // saves on first scan; no per-frame work, just the
                        // resources we already fetched.
                        let detectedSource: PhotoSource? = {
                            for r in resources {
                                if let s = PhotoKitService.detectSourceFromFilename(r.originalFilename) {
                                    return s
                                }
                            }
                            return nil
                        }()

                        // Codec detection: iOS reports HEVC video resources
                        // with UTI `public.hevc`. Match exact/suffix tokens
                        // so unrelated identifiers can't false-positive.
                        let uti = resource.uniformTypeIdentifier.lowercased()
                        let isAlreadyHEVC = uti == "public.hevc"
                            || uti == "public.hevc-video"
                            || uti.hasSuffix(".hevc")
                            || uti.hasSuffix(".hvc1")
                            || uti.hasSuffix(".hev1")

                        // 4K detection — any edge ≥ 3840. Covers 4K landscape,
                        // 4K portrait, and the ProRes cinematic form factors.
                        let longestEdge = max(asset.pixelWidth, asset.pixelHeight)
                        let is4K = longestEdge >= 3840

                        // Content-aware savings multiplier. The base is
                        // CompressionLevel.medium.estimatedSavings, but real
                        // savings vary enormously by content type:
                        //   • HEVC source: already efficient → × 0.65
                        //   • Slow-mo / time-lapse: VBR keyframe overhead
                        //     dominates the bitstream → × 0.75
                        //   • Cinematic: Dolby metadata + HDR reserve bits
                        //     that can't be reclaimed → × 0.70
                        //   • 4K sources have more room to fall → × 1.10
                        //   • Very short clips (<5s) hit keyframe overhead
                        //     proportionally harder → × 0.80
                        var savingsMultiplier: Float = 1.0
                        if isAlreadyHEVC                    { savingsMultiplier *= 0.65 }
                        if isHighFrameRate || isTimelapse   { savingsMultiplier *= 0.75 }
                        if isCinematic                      { savingsMultiplier *= 0.70 }
                        if is4K                             { savingsMultiplier *= 1.10 }
                        if duration < 5                     { savingsMultiplier *= 0.80 }

                        let baseSaving = CompressionLevel.medium.estimatedSavings(from: fileSize)
                        let potentialSaving = Int64(Float(baseSaving) * savingsMultiplier)

                        let tags = VideoSmartTags(
                            isSlowMo: isHighFrameRate,
                            isTimelapse: isTimelapse,
                            isCinematic: isCinematic,
                            is4K: is4K,
                            isHEVC: isAlreadyHEVC,
                            isHDR: false
                        )

                        var resolution: CGSize?
                        let w = CGFloat(asset.pixelWidth)
                        let h = CGFloat(asset.pixelHeight)
                        if w > 0 && h > 0 {
                            resolution = CGSize(width: w, height: h)
                        }

                        var bitrate: Float?
                        if duration > 0 {
                            let raw = Float(fileSize * 8) / Float(duration)
                            if raw.isFinite && raw > 0 {
                                bitrate = raw
                            }
                        }

                        return VideoAsset(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: fileSize,
                            potentialSavings: potentialSaving,
                            duration: duration,
                            creationDate: asset.creationDate ?? Date(),
                            resolution: resolution,
                            bitrate: bitrate,
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

                var collected: [VideoAsset] = []
                collected.reserveCapacity(candidates.count)
                var processed = 0
                // Buffer items since the last flush — streamed to the
                // published array in batches so SwiftUI isn't forced to
                // re-diff the grid on every single asset.
                var pendingBatch: [VideoAsset] = []

                while let video = await group.next() {
                    if let video = video {
                        collected.append(video)
                        pendingBatch.append(video)
                    }
                    if let next = iter.next() { spawn(next) }
                    processed += 1

                    // Flush every 30 results or at the final tick. 30 is a
                    // sweet spot: small enough to feel progressive on a big
                    // library (user sees the grid fill), large enough that
                    // SwiftUI's list diffing isn't hammered.
                    // Same 20-item streaming flush as loadPhotos — see there
                    // for rationale.
                    let shouldFlush = pendingBatch.count >= 20 || processed == totalCandidates
                    if shouldFlush || processed % 10 == 0 {
                        let snapshotProcessed = processed
                        let batch = pendingBatch
                        if shouldFlush { pendingBatch.removeAll(keepingCapacity: true) }
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            self.scanProcessed = snapshotProcessed
                            if shouldFlush && !batch.isEmpty {
                                self.videos.append(contentsOf: batch)
                                self.videoTotalSize += batch.reduce(0) { $0 + $1.fileSize }
                                self.videoPotentialSavings += batch.reduce(0) { $0 + $1.potentialSavings }
                            }
                        }
                    }
                }

                return collected
            }

            return (added: loaded, allIDs: allCurrentIDs)
        }.value

        // ── Phase 3: Reconcile cache + new scan ──
        // 1. Drop any cached videos whose asset no longer exists in the
        //    current library (user deleted since last scan).
        // 2. Append freshly-scanned additions.
        // 3. Re-sort by savings so the final order is "biggest wins first"
        //    regardless of which bucket an item came from.
        let addedIds = Set(result.added.map(\.id))
        var merged = videos.filter { result.allIDs.contains($0.id) && !addedIds.contains($0.id) }
        merged.append(contentsOf: result.added)
        merged.sort { $0.potentialSavings > $1.potentialSavings }

        withAnimation(.easeInOut(duration: 0.3)) {
            videos = merged
            videoTotalSize = merged.reduce(0) { $0 + $1.fileSize }
            videoPotentialSavings = merged.reduce(0) { $0 + $1.potentialSavings }
        }
        isLoadingVideos = false
        hasLoadedVideos = true

        // ── Phase 4: Persist the authoritative list back to disk ──
        // Everything currently on screen is now the truth. Serialize and
        // save so the next app launch can skip this whole dance.
        let snapshots = merged.map(CachedVideoSnapshot.init(from:))
        await ScanCache.shared.saveVideoSnapshots(snapshots)

        // Prefetch thumbnails for the first viewport — redundant with the
        // Phase-1 prefetch when we had a cache, but harmless (NSCache
        // dedupes) and critical on the first-ever scan.
        let prefetchAssets = merged.prefix(40).compactMap { $0.asset }
        AssetThumbnailCache.shared.prefetch(
            Array(prefetchAssets),
            size: CGSize(width: 300, height: 400),
            limit: 40
        )
    }
}

