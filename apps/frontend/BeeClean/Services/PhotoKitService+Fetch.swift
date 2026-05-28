import Foundation
import Photos
import ImageIO
import AVFoundation

extension PhotoKitService {
    // MARK: - Fetch Photos
    nonisolated func fetchAllPhotos(limit: Int? = nil) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        Self.applyStandardPolicy(options)

        if let limit = limit {
            options.fetchLimit = limit
        }

        return Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
    }

    /// Fetch only photos created after `date`. Used for incremental indexing.
    nonisolated func fetchPhotosAfter(_ date: Date) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate > %@",
            PHAssetMediaType.image.rawValue,
            date as NSDate
        )
        Self.applyStandardPolicy(options)
        return Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
    }

    // MARK: - Burst Identifier Map
    /// Builds a map of `assetId → burstIdentifier` for every asset in the
    /// fetch result that's part of a burst session. Apple stamps every frame
    /// in a burst with a shared `PHAsset.burstIdentifier` (with our
    /// `includeAllBurstAssets = true` policy, all frames are visible). Using
    /// that as a primary clustering key — instead of just the 90-second time
    /// window — catches long bursts (200+ frames) and bursts captured around
    /// midnight that would otherwise straddle two time buckets.
    ///
    /// Returns an empty map if no asset in the fetch is a burst frame, so the
    /// caller doesn't pay any clustering overhead on libraries with zero
    /// bursts.
    nonisolated static func extractBurstIds(_ fetch: PHFetchResult<PHAsset>) -> [String: String] {
        var map: [String: String] = [:]
        fetch.enumerateObjects { asset, _, _ in
            if let burstId = asset.burstIdentifier, !burstId.isEmpty {
                map[asset.localIdentifier] = burstId
            }
        }
        return map
    }

    // MARK: - Fetch Videos
    //
    // `mediaType == .video` does NOT include Live Photos — those are
    // mediaType `.image` and carry the video as a PHAssetResource sibling on
    // the same PHAsset. So this fetch never double-counts a Live Photo:
    // it'll appear once in the photo path and zero times in the video path.
    // If we ever loosen the predicate (e.g., union with `.photoLive`), we'd
    // need to deduplicate against fetchAllPhotos to avoid surfacing the same
    // Live Photo in both the Similar Photos and Similar Videos cards.
    nonisolated func fetchAllVideos(limit: Int? = nil) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        Self.applyStandardPolicy(options)
        if let limit { options.fetchLimit = limit }
        return Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
    }

    // MARK: - Screen Recording Detection
    /// Centralized screen-recording check. iOS's ReplayKit saves with the
    /// "RPReplay" prefix; exports/renames through Files/Share sheet sometimes
    /// land as "Screen Recording …" or "ScreenRecording…". Matching is
    /// case-insensitive so all variants are caught.
    ///
    /// Filename matching is the primary signal because it's deterministic for
    /// fresh ReplayKit captures. But users rename screen recordings in the
    /// Files app, AirDrop them with custom names, or export from a Mac — at
    /// which point the prefix is gone. As a secondary signal we also accept
    /// the asset-level mediaSubtype `.videoStreamed`, which iOS sets on
    /// ReplayKit-originated captures and survives renames.
    nonisolated static func isScreenRecordingResource(_ resource: PHAssetResource) -> Bool {
        let name = resource.originalFilename.lowercased()
        return name.hasPrefix("rpreplay")
            || name.hasPrefix("screenrecording")
            || name.hasPrefix("screen recording")
            || name.hasPrefix("screenrec_")
    }

    // MARK: - Source-App Detection (Tier 2: EXIF Software tag)
    //
    // Reads the photo's EXIF/TIFF header — NOT the pixel data — looking for
    // the `Software` tag that Instagram, Snapchat (when EXIF preserved),
    // TikTok exports, etc. write into the file. `CGImageSourceCopyProperties`
    // stops parsing once it has the header, so each call is ~5–10ms on a
    // modern device regardless of the source image's pixel size.
    //
    // Skips videos (Tier 1 filename catches them; AVAsset EXIF parsing is
    // a different beast) and iCloud-only assets (network disabled to keep
    // the background pass cheap).
    //
    // The orchestration loop that drives this — chunking, parallel
    // TaskGroup, batched persistence + main-actor merge — lives in
    // `enrichSourcesFromEXIF(_:onBatch:)` below.
    nonisolated static func detectSourceFromEXIF(_ asset: PHAsset) async -> PhotoSource? {
        guard asset.mediaType == .image else { return nil }

        // Two-pass URL fetch — local first (zero cost), then iCloud
        // fallback if the asset isn't on-device. PhotoKit only triggers
        // an actual download when network is allowed AND the file is
        // missing locally; for the local-already case it's a no-op. iOS
        // respects the user's per-app cellular policy under
        // Settings → Cellular → Photos, so flipping network=true here
        // can't surprise-charge the user. Eliminates the iCloud-only
        // gap that previously left Instagram saves unbadged for users
        // with "Optimize iPhone Storage" turned on.
        func fetchURL(networkAllowed: Bool) async -> URL? {
            await withCheckedContinuation { cont in
                let options = PHContentEditingInputRequestOptions()
                options.isNetworkAccessAllowed = networkAllowed
                asset.requestContentEditingInput(with: options) { input, _ in
                    cont.resume(returning: input?.fullSizeImageURL)
                }
            }
        }
        var url = await fetchURL(networkAllowed: false)
        if url == nil { url = await fetchURL(networkAllowed: true) }
        guard let url else { return nil }

        // `kCGImageSourceShouldCache: false` keeps the pixel cache empty —
        // we only want the metadata, never the decoded image.
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imgSrc = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(imgSrc, 0, nil) as? [CFString: Any]
        else { return nil }

        // TIFF Software tag — Instagram's primary fingerprint, and a
        // secondary signal for several other apps when EXIF wasn't stripped.
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFSoftware] as? String {
            let s = raw.lowercased()
            if s.contains("instagram") { return .instagram }
            if s.contains("snapchat")  { return .snapchat }
            if s.contains("tiktok")    { return .tiktok }
            if s.contains("whatsapp")  { return .whatsapp }
            if s.contains("telegram")  { return .telegram }
            if s.contains("messenger") { return .messenger }
        }

        // EXIF UserComment — TikTok exports occasionally stash app name
        // here; cheap to also check while we have the dict loaded.
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifUserComment] as? String {
            let s = raw.lowercased()
            if s.contains("instagram") { return .instagram }
            if s.contains("tiktok")    { return .tiktok }
        }

        return nil
    }

    // MARK: - Source-App Detection (Tier 2: video container metadata)
    //
    // EXIF doesn't apply to videos — the equivalent metadata lives in
    // the mp4 / mov container's atom hierarchy. Common tags carried by
    // social-app exports:
    //   • `software` / `©too` — TikTok writes "TikTok" here; Instagram
    //     exports often carry "Instagram" in the same slot.
    //   • `author` / `©ART` — Snapchat / WhatsApp sometimes stash app
    //     name here when exporting from "Memories" / forwards.
    //   • `comment` / `©cmt` — fallback bucket used by various exporters.
    //
    // AVFoundation surfaces all of these uniformly through
    // `AVAsset.commonMetadata` + the per-format metadata arrays. Reading
    // is header-only (AVAsset doesn't decode frames until you ask) so
    // the cost is comparable to EXIF: ~10-20ms per asset on a modern
    // device. iCloud-only videos download on demand under the user's
    // existing data policy, same as the photo path above.
    nonisolated static func detectSourceFromVideoMetadata(_ asset: PHAsset) async -> PhotoSource? {
        guard asset.mediaType == .video else { return nil }

        // PhotoKit hands us an AVAsset directly — no need to round-trip
        // through a file URL. `isNetworkAccessAllowed = true` lets the
        // call succeed on iCloud-only videos; PhotoKit defers to the
        // user's cellular policy before triggering an actual download.
        let avAsset: AVAsset? = await withCheckedContinuation { cont in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .fastFormat
            options.version = .current
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { av, _, _ in
                cont.resume(returning: av)
            }
        }
        guard let avAsset else { return nil }

        // Pull common + format-specific metadata in one shot. Common
        // covers the cross-container abstractions; format-specific
        // covers the raw QuickTime/mp4 atoms TikTok actually writes
        // ("com.apple.quicktime.software", "©too", etc.).
        async let commonItems: [AVMetadataItem] = (try? avAsset.load(.commonMetadata)) ?? []
        async let formatList: [AVMetadataFormat] = (try? avAsset.load(.availableMetadataFormats)) ?? []

        var allItems: [AVMetadataItem] = await commonItems
        for format in await formatList {
            if let items = try? await avAsset.loadMetadata(for: format) {
                allItems.append(contentsOf: items)
            }
        }

        // Scan every string-valued tag — TikTok exports stamp their
        // signature in several places depending on iOS version and
        // export path, so a single fixed key check is fragile. The
        // cost of scanning is trivial (~10 items per asset).
        for item in allItems {
            guard let raw = try? await item.load(.stringValue), !raw.isEmpty else { continue }
            let s = raw.lowercased()
            if s.contains("tiktok")    { return .tiktok }
            if s.contains("instagram") { return .instagram }
            if s.contains("snapchat")  { return .snapchat }
            if s.contains("whatsapp")  { return .whatsapp }
            if s.contains("telegram")  { return .telegram }
            if s.contains("messenger") { return .messenger }
        }
        return nil
    }

    // MARK: - Source-App Enrichment (orchestration)
    //
    // Background pass that backfills `sourceApp` on every photo in the
    // store's `analyzedIndex` where Tier 1 came back empty. Designed to
    // complete in ~10s on a 5k-asset library without blocking the UI:
    //
    //   • Concurrency 8 — modern A-chips happily parallelize 8 metadata
    //     reads; bumping higher hits diminishing returns from PhotoKit
    //     queue contention.
    //   • Batched every 50 detections — calls `onBatch` on the main actor
    //     so the store can merge into `analyzedIndex` and trigger a
    //     dashboard recompute. Badges + per-source cards light up
    //     progressively as the pass runs.
    //   • Persists each batch via `SimilarPersistence.savePhotosBackground`
    //     so results survive a kill mid-pass.
    //   • Respects cooperative cancellation — caller cancels by cancelling
    //     the enclosing Task.
    nonisolated static func enrichSourcesFromEXIF(
        seeds: [String: AnalyzedPhoto],
        onBatch: @MainActor @Sendable ([String: PhotoSource]) -> Void
    ) async {
        // Candidates: not yet classified (sourceApp == nil), analysis-viable
        // (skip metadata-only sentinels), and big enough to plausibly carry
        // EXIF software tags. Tiny files (<50KB) are almost always
        // thumbnails / chat-strip stickers — Instagram + TikTok saves are
        // always larger. Skipping them removes ~20% of candidates on a
        // typical library for free.
        let minFileSizeForEXIF: Int64 = 50_000
        let candidates = seeds.values
            .filter { $0.sourceApp == nil }
            .filter { !PhotoAnalyzer.isMetadataOnly($0) }
            .filter { ($0.fileSize ?? 0) >= minFileSizeForEXIF }
            .map(\.assetIdentifier)

        guard !candidates.isEmpty else { return }

        // ONE batched PHAsset fetch upfront — Photos round-trips are
        // surprisingly expensive when chunked (~1ms each → 600+ ms wasted
        // on a 5k library if done per concurrency-batch). Resolving every
        // candidate at the start avoids that overhead entirely.
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: candidates, options: nil)
        var assetsById: [String: PHAsset] = [:]
        assetsById.reserveCapacity(candidates.count)
        fetch.enumerateObjects { asset, _, _ in
            assetsById[asset.localIdentifier] = asset
        }

        // Bumped from 8 → 16. EXIF reads are I/O-bound (file headers via
        // PHContentEditingInput + CGImageSource) and modern A-chips comfortably
        // schedule 16 in flight without PhotoKit queue contention. Halves the
        // wall-clock on a 5k library.
        let concurrency = 16
        let batchSize = 50

        var pendingPhotos: [AnalyzedPhoto] = []
        var pendingMap: [String: PhotoSource] = [:]

        // Bounded TaskGroup pattern — keep at most `concurrency` tasks in
        // flight at any moment. When the cap is reached, `group.next()`
        // blocks for a slot before spawning the next task. Faster than
        // chunk-then-await-all because slow tasks don't stall faster ones
        // in the same chunk.
        // Per-task closure runs the full Tier 2 → Tier 3 cascade and
        // routes by mediaType so videos hit the AVMetadata path while
        // images hit the EXIF path. Both tiers internally self-gate
        // (mediaType, aspect-ratio for Tier 3) so passing an off-domain
        // asset is harmless. Eliminates the previous video-side gap
        // where TikTok / Snapchat / IG video saves with stripped
        // filenames had no fallback after Tier 1.
        @Sendable
        func detect(_ asset: PHAsset) async -> PhotoSource? {
            if asset.mediaType == .video {
                if let s = await detectSourceFromVideoMetadata(asset) { return s }
                // Vision Tier 3 for videos uses the first-frame
                // classifier; for vertical 9:16 screen-recorded reels
                // this catches the burned-in UI.
                return await VisualSourceClassifier.classifyVideo(asset)
            }
            if let s = await detectSourceFromEXIF(asset) { return s }
            return await VisualSourceClassifier.classify(asset)
        }

        await withTaskGroup(of: (String, PhotoSource?).self) { group in
            var iter = candidates.makeIterator()

            // Fill the in-flight slots up to `concurrency`.
            var spawned = 0
            while spawned < concurrency, let assetId = iter.next() {
                guard let asset = assetsById[assetId] else { continue }
                group.addTask {
                    let source = await detect(asset)
                    return (assetId, source)
                }
                spawned += 1
            }

            // Pump: whenever a task completes, fold the result into the
            // pending batch, flush if we've hit batchSize, and enqueue the
            // next candidate. Inlined (no helper fn) so SwiftConcurrency
            // doesn't have to reason about a @Sendable closure capturing
            // the outer `pendingPhotos` / `pendingMap` mutable vars.
            while let pair = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                let (assetId, source) = pair
                if let source, var photo = seeds[assetId] {
                    photo.sourceApp = source
                    pendingPhotos.append(photo)
                    pendingMap[assetId] = source
                }
                if pendingPhotos.count >= batchSize {
                    SimilarPersistence.savePhotosBackground(pendingPhotos)
                    let snapshot = pendingMap
                    await MainActor.run { onBatch(snapshot) }
                    pendingPhotos.removeAll(keepingCapacity: true)
                    pendingMap.removeAll(keepingCapacity: true)
                }
                if let nextId = iter.next(), let nextAsset = assetsById[nextId] {
                    group.addTask {
                        let source = await detect(nextAsset)
                        return (nextId, source)
                    }
                }
            }
        }

        // Final flush — anything < batchSize that didn't trigger an in-loop
        // flush gets persisted + surfaced now.
        if !pendingPhotos.isEmpty {
            SimilarPersistence.savePhotosBackground(pendingPhotos)
            let snapshot = pendingMap
            await MainActor.run { onBatch(snapshot) }
        }
    }

    // MARK: - Source-App Detection (Tier 1: filename)
    //
    // Cheap deterministic detection for apps with predictable filename
    // patterns. Runs inline during the scan (PhotoAnalyzer.analyzeAsset)
    // so badges + per-source cards light up without a second pass over
    // the library.
    //
    // Instagram intentionally NOT here — Instagram saves under the default
    // `IMG_XXXX.jpg` name, so filename can't tell us anything. Tier 2 in
    // PhotoSourceDetector reads the EXIF `Software` tag for those.
    //
    // Returns nil when no pattern matches — caller leaves `sourceApp` nil
    // and Tier 2 enrichment picks it up later.
    nonisolated static func detectSourceFromFilename(_ asset: PHAsset) -> PhotoSource? {
        for resource in PHAssetResource.assetResources(for: asset) {
            if let source = detectSourceFromFilename(resource.originalFilename) {
                return source
            }
        }
        return nil
    }

    /// Pure helper — exposed so tests + the EXIF pass can hit the same
    /// name-matching logic without a PHAsset on hand.
    nonisolated static func detectSourceFromFilename(_ originalFilename: String) -> PhotoSource? {
        let name = originalFilename.lowercased()

        // Snapchat: saves photos AND videos as `Snapchat-{timestamp}.{ext}`.
        // Very reliable — Snapchat has used this naming for years.
        if name.hasPrefix("snapchat-") || name.hasPrefix("snapchat_") {
            return .snapchat
        }
        // WhatsApp: `IMG-YYYYMMDD-WA{NNNN}.jpg` for photos,
        // `VID-YYYYMMDD-WA{NNNN}.mp4` for videos. The `-wa` infix is the
        // tell-tale — generic `IMG-` files (Android camera) don't have it.
        if (name.hasPrefix("img-") || name.hasPrefix("vid-")) && name.contains("-wa") {
            return .whatsapp
        }
        // Telegram: `telegram-cloud-document-*`, `*_telegram_*`, etc.
        // The substring is distinctive enough that false positives are
        // implausible.
        if name.contains("telegram") {
            return .telegram
        }
        // Messenger / Facebook downloads: `FB_IMG_*` (Facebook image save),
        // `received_*` (Messenger Lite), `Image_from_FB_*`.
        if name.hasPrefix("fb_img") || name.hasPrefix("received_") || name.hasPrefix("image_from_fb") {
            return .messenger
        }
        // TikTok: official "Save Video" uses `tiktok_{user}_{timestamp}.mp4`
        // and `tiktok-{id}.mp4` patterns. Tightened from the previous loose
        // `hasPrefix("tiktok")` because that false-positived on user
        // filenames like "tiktokvacation2024.jpg" or "mytiktok.heic" —
        // those don't have the trailing separator that the official
        // export does. Substring `_tiktok_` catches "vid_tiktok_2024.mp4"
        // and similar resaved variants without the over-broad prefix.
        if name.hasPrefix("tiktok_") || name.hasPrefix("tiktok-") || name.contains("_tiktok_") {
            return .tiktok
        }
        return nil
    }

    nonisolated static func isScreenRecording(_ asset: PHAsset) -> Bool {
        // Primary: filename prefix on any backing resource.
        if PHAssetResource.assetResources(for: asset).contains(where: { isScreenRecordingResource($0) }) {
            return true
        }
        // Secondary: ReplayKit-originated assets carry .videoStreamed in
        // mediaSubtypes even after the user renames them. This catches
        // recordings that survived a rename in the Files app or an export.
        if asset.mediaSubtypes.contains(.videoStreamed) {
            return true
        }
        // Tertiary content-free fallback: a video whose pixel dimensions match
        // an iPhone screen resolution exactly is almost certainly a screen
        // recording — there's no organic camera capture path that produces
        // 1170×2532 or 1290×2796 video. This catches AirDropped screen
        // recordings whose original filename and `.videoStreamed` flag were
        // both stripped during transfer.
        if asset.mediaType == .video,
           isIPhoneScreenResolution(width: asset.pixelWidth, height: asset.pixelHeight) {
            return true
        }
        return false
    }

    // MARK: - Fetch Short Videos
    /// Fetches all non-screen-recording videos shorter than maxDuration seconds.
    nonisolated func fetchShortVideos(maxDuration: TimeInterval = 60) -> [ScreenshotAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND duration <= %f",
            PHAssetMediaType.video.rawValue, maxDuration
        )
        Self.applyStandardPolicy(options)

        let allVideos = Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
        var results: [ScreenshotAsset] = []

        allVideos.enumerateObjects { asset, _, _ in
            guard !Self.isScreenRecording(asset) else { return }

            let resources = PHAssetResource.assetResources(for: asset)
            let fileSize = resources.first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            results.append(ScreenshotAsset(
                assetId: asset.localIdentifier,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                fileSize: fileSize
            ))
        }

        return results
    }

    // MARK: - Fetch Long Videos
    /// Fetches videos strictly longer than `minDuration` seconds.
    /// Default 60s means every non-screen-recording video lands in EXACTLY ONE
    /// of Short Videos (≤60s) or Long Videos (>60s) — no gap, no overlap.
    /// Excludes screen recordings, which have their own category.
    nonisolated func fetchLongVideos(minDuration: TimeInterval = 60) -> [ScreenshotAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "duration", ascending: false)]
        // Strict greater-than so the boundary video (exactly minDuration)
        // is owned by Short Videos and not double-counted in Long Videos.
        options.predicate = NSPredicate(
            format: "mediaType == %d AND duration > %f",
            PHAssetMediaType.video.rawValue, minDuration
        )
        Self.applyStandardPolicy(options)

        let allVideos = Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
        var results: [ScreenshotAsset] = []

        allVideos.enumerateObjects { asset, _, _ in
            // Exclude screen recordings — they live in their own category
            guard !Self.isScreenRecording(asset) else { return }

            let resources = PHAssetResource.assetResources(for: asset)
            let fileSize = resources.first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            results.append(ScreenshotAsset(
                assetId: asset.localIdentifier,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                fileSize: fileSize
            ))
        }

        return results
    }

    // MARK: - Fetch Screen Recordings
    /// Identifies screen recordings by checking PHAssetResource original filenames
    /// — matches RPReplay (native iOS), Screen Recording (export/share), and
    /// ScreenRecording variants so rename/export flows are still caught.
    nonisolated func fetchScreenRecordings() -> [ScreenshotAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        Self.applyStandardPolicy(options)

        let allVideos = Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
        var results: [ScreenshotAsset] = []

        allVideos.enumerateObjects { asset, _, _ in
            guard Self.isScreenRecording(asset) else { return }

            let resources = PHAssetResource.assetResources(for: asset)
            let fileSize = resources.first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            results.append(ScreenshotAsset(
                assetId: asset.localIdentifier,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                fileSize: fileSize
            ))
        }

        return results
    }

    // MARK: - Fetch Screenshots
    /// Uses the system Screenshots smart album — no AI, pure metadata.
    /// In DEBUG builds, falls back to all photos if the smart album is empty (simulator workaround).
    nonisolated func fetchScreenshots() -> [ScreenshotAsset] {
        let assets = screenshotFetchResult()
        var results: [ScreenshotAsset] = []
        var seen = Set<String>()

        assets.enumerateObjects { asset, _, _ in
            seen.insert(asset.localIdentifier)
            let fileSize = PHAssetResource.assetResources(for: asset)
                .first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            results.append(ScreenshotAsset(
                assetId: asset.localIdentifier,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                fileSize: fileSize
            ))
        }

        // Content-fallback pass: catches screenshots that lost the
        // `.photoScreenshot` mediaSubtype (re-imports, edited screenshots,
        // AirDrop transfers from another phone) by matching exact iPhone
        // screen resolutions. Skip when the smart album already returned
        // a healthy count — re-imports are an edge case the smart album
        // usually catches, and the fallback walks every image in the
        // library (1–3s on a 50k library).
        if seen.count < Self.fallbackScreenshotsThreshold {
            let extras = fallbackScreenshotAssets(excluding: seen)
            for asset in extras {
                let fileSize = PHAssetResource.assetResources(for: asset)
                    .first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
                results.append(ScreenshotAsset(
                    assetId: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    fileSize: fileSize
                ))
            }
        }

        return results
    }

    /// Returns raw PHAssets from the Screenshots smart album for analysis (dHash + sharpness).
    /// Includes content-fallback matches by iPhone screen resolution.
    nonisolated func fetchScreenshotAssets() -> PHFetchResult<PHAsset>? {
        let smartResult = screenshotFetchResult()
        var seen = Set<String>()
        smartResult.enumerateObjects { asset, _, _ in seen.insert(asset.localIdentifier) }
        // Same gating as fetchActualScreenshotIds — only do the linear
        // walk when the smart album hasn't populated reliably.
        let extras: [PHAsset] = seen.count < Self.fallbackScreenshotsThreshold
            ? fallbackScreenshotAssets(excluding: seen)
            : []
        if extras.isEmpty {
            return smartResult.count > 0 ? smartResult : nil
        }

        // Merge smart-album result + fallback into a single PHFetchResult so
        // downstream clustering still operates on a single fetch.
        var allIds: [String] = []
        allIds.reserveCapacity(smartResult.count + extras.count)
        smartResult.enumerateObjects { asset, _, _ in allIds.append(asset.localIdentifier) }
        for asset in extras { allIds.append(asset.localIdentifier) }

        let merged = PHFetchOptions()
        Self.applyStandardPolicy(merged)
        merged.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(withLocalIdentifiers: allIds, options: merged)
        return result.count > 0 ? result : nil
    }

    /// Returns asset IDs from the actual Screenshots smart album (no DEBUG fallback).
    /// Used by Other Photos to correctly exclude real screenshots — also
    /// includes content-fallback matches so a re-imported screenshot doesn't
    /// leak into Other Photos AND show up in the Screenshots card.
    nonisolated func fetchActualScreenshotIds() -> Set<String> {
        var ids = Set<String>()

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        if let album = collections.firstObject {
            let fetchOptions = PHFetchOptions()
            Self.applyStandardPolicy(fetchOptions)
            let result = Self.excludingSharedLibraryAssets(
                PHAsset.fetchAssets(in: album, options: fetchOptions)
            )
            result.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        }

        // Skip the linear-walk fallback when the smart album already
        // returned a healthy count — re-imports / AirDropped screenshots
        // are edge cases, and on a 50k-photo library walking ALL images
        // for an aspect-ratio match was costing 1–3s per scan, called 3
        // times across the pipeline (here + fetchScreenshots +
        // fetchScreenshotAssets). When the album is empty / nearly empty
        // (clean install or non-screenshot-taking user), we still run
        // the fallback as a safety net.
        if ids.count < Self.fallbackScreenshotsThreshold {
            let extras = fallbackScreenshotAssets(excluding: ids)
            for asset in extras { ids.insert(asset.localIdentifier) }
        }
        return ids
    }

    /// Below this count we assume the smart album hasn't populated
    /// reliably and run the linear-walk fallback. Above it, we trust
    /// iOS Photos to have classified everything.
    /// `nonisolated` because the value is read from `nonisolated`
    /// fetch helpers; the `(unsafe)` qualifier is unnecessary for an
    /// Int (already Sendable) so plain `nonisolated` is the correct
    /// Swift 6 form here.
    nonisolated static let fallbackScreenshotsThreshold = 20

    /// Shared helper: fetches from the Screenshots smart album only.
    private nonisolated func screenshotFetchResult() -> PHFetchResult<PHAsset> {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        Self.applyStandardPolicy(fetchOptions)

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        if let album = collections.firstObject {
            return Self.excludingSharedLibraryAssets(
                PHAsset.fetchAssets(in: album, options: fetchOptions)
            )
        }

        // No Screenshots album found — return genuinely empty result
        fetchOptions.predicate = NSPredicate(value: false)
        return PHAsset.fetchAssets(with: fetchOptions)
    }

    // MARK: - iPhone screen resolution catalog
    //
    // Every PHAsset captured natively as a screenshot has `pixelWidth` and
    // `pixelHeight` matching the device's screen pixel dimensions exactly.
    // A cropped or edited screenshot may not match (it'll be re-saved at the
    // crop's size), but unedited re-imports and AirDropped originals do.
    //
    // The list below covers every shipping iPhone display from iPhone 5 through
    // iPhone 16 Pro Max — 12 resolutions × 2 orientations = 24 patterns. A
    // photo from any non-iPhone camera that lands at exactly one of these
    // dimensions would be a one-in-millions false-positive; we accept that
    // risk for the meaningful recall improvement on re-imported screenshots.
    private nonisolated static let iPhoneScreenResolutions: [(Int, Int)] = [
        (640, 1136),   // iPhone 5 / 5s / 5c / SE 1
        (750, 1334),   // iPhone 6 / 6s / 7 / 8 / SE 2 / SE 3
        (828, 1792),   // iPhone XR / 11
        (1080, 1920),  // iPhone 6+/6s+/7+/8+ (downsampled render)
        (1125, 2436),  // iPhone X / XS / 11 Pro
        (1170, 2532),  // iPhone 12 / 12 Pro / 13 / 13 Pro / 14
        (1179, 2556),  // iPhone 15 / 15 Pro / 16
        (1206, 2622),  // iPhone 16
        (1242, 2208),  // iPhone 6+/6s+/7+/8+ (native render)
        (1242, 2688),  // iPhone XS Max / 11 Pro Max
        (1284, 2778),  // iPhone 12 Pro Max / 13 Pro Max / 14 Plus
        (1290, 2796),  // iPhone 14 Pro / 15 Plus / 15 Pro Max / 16 Plus / 16 Pro
        (1320, 2868),  // iPhone 16 Pro Max
    ]

    /// True if a (w, h) pair matches a known iPhone screen resolution exactly,
    /// in either orientation.
    private nonisolated static func isIPhoneScreenResolution(width: Int, height: Int) -> Bool {
        for (w, h) in iPhoneScreenResolutions where (width == w && height == h) || (width == h && height == w) {
            return true
        }
        return false
    }

    /// True if a (w, h) pair has a phone-screenshot-like aspect ratio.
    ///
    /// Picks up the leak: a screenshot that's been edited, AirDropped from an
    /// Android device, or whose Photos-classification was lost will not match
    /// `iPhoneScreenResolutions` exactly, but its shape is still unmistakable.
    /// Modern phones cluster tightly around long/short ≈ 2.0–2.30 (iPhone 14+
    /// at 2.167, iPhone 8 at 1.78, Android flagships at 2.10–2.22). Real
    /// portrait photos are 4:3 (1.33) or 16:9 (1.78) — well below this band.
    ///
    /// Size guard: a phone screenshot's smaller dimension is almost always
    /// ≤ 1500 px (no shipping phone has wider than 1320 px native, and edited
    /// screenshots only shrink). A 6000×12000 vertical panorama would land in
    /// the same ratio band but is excluded by the size guard.
    private nonisolated static func hasPhoneScreenshotAspectRatio(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let longSide = max(width, height)
        let shortSide = min(width, height)
        guard shortSide <= 1500 else { return false }
        let ratio = Double(longSide) / Double(shortSide)
        return ratio >= 1.95 && ratio <= 2.35
    }

    /// Scans all photos for screenshot candidates not already in `excluding`
    /// (the smart-album set). Two passes: exact iPhone resolution match (near-
    /// zero false positives) plus phone-aspect-ratio match with size guard
    /// (covers Android, edited, and re-encoded phone screenshots that were
    /// previously leaking into Other Photos and Blurry). Cheap — metadata only.
    nonisolated func fallbackScreenshotAssets(excluding: Set<String>) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        Self.applyStandardPolicy(options)

        let all = Self.excludingSharedLibraryAssets(PHAsset.fetchAssets(with: options))
        var results: [PHAsset] = []
        all.enumerateObjects { asset, _, _ in
            guard !excluding.contains(asset.localIdentifier) else { return }
            // Hard exclusions before either heuristic fires — panoramas
            // and Live Photos cluster in the same aspect-ratio band as
            // phone screenshots and would otherwise leak into the
            // Screenshots card. The system camera tags both cleanly via
            // mediaSubtypes, so we can drop them with no decode work.
            // Live Photo `.photoLive` keeps a Live Photo's still out of
            // a "Screenshots" cleanup pile where deleting it would also
            // wipe the user's intentional moving photo.
            let subtypes = asset.mediaSubtypes
            if subtypes.contains(.photoPanorama) || subtypes.contains(.photoLive) {
                return
            }
            let w = asset.pixelWidth
            let h = asset.pixelHeight
            if Self.isIPhoneScreenResolution(width: w, height: h)
                || Self.hasPhoneScreenshotAspectRatio(width: w, height: h) {
                results.append(asset)
            }
        }
        return results
    }

}
