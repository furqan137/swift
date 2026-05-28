import Foundation
import Photos
import UIKit

// MARK: - Thumbnail Request Token
//
// Cancellable handle returned from `loadThumbnailCancellable`. Holds the
// PHImageRequestID once the underlying PHAsset has been fetched (which
// happens off-main, so the ID isn't available synchronously). Calling
// `cancel()` before the request ID is known marks the token cancelled —
// when the daemon eventually returns one, it's cancelled immediately.
//
// This is the load-bearing fix for "gray boxes after scrolling fast" and
// "lag after using the section for a while": before this, every cell
// that scrolled off-screen left an in-flight PHImageManager request
// running, and the photo daemon's FIFO queue grew unbounded as the user
// kept scrolling. Now each cell cancels its own request on disappear,
// so the daemon's queue only ever holds requests for visible cells.
final class ThumbnailRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var requestId: PHImageRequestID = PHInvalidImageRequestID
    private var cancelled = false

    /// Called from inside `loadThumbnailCancellable` once the underlying
    /// PHAsset fetch has completed and the daemon has issued a request ID.
    /// If `cancel()` was already called, the request is cancelled here.
    func _setRequestId(_ id: PHImageRequestID) {
        lock.lock(); defer { lock.unlock() }
        if cancelled {
            PHImageManager.default().cancelImageRequest(id)
            return
        }
        requestId = id
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if requestId != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestId)
            requestId = PHInvalidImageRequestID
        }
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

extension PhotoKitService {
    // MARK: - Load Thumbnail
    //
    // Two-phase loader optimized for grids of thousands of cells:
    //
    //  1. PHCachingImageManager.requestImage with `.fastFormat` delivers a
    //     single full-size callback (no degraded-preview-then-final two-phase
    //     callback that confuses cell layout). This works for both photos
    //     AND videos — PHImageManager extracts a frame for video assets.
    //
    //  2. If step 1 returns nil for a VIDEO asset (PHImageManager throttles
    //     under high concurrency or fails for cinematic / iCloud-degraded
    //     videos), fall back to AVAssetImageGenerator on the underlying
    //     AVURLAsset. Generates from the first second of playable content,
    //     which is more reliable for awkward video assets.
    //
    // Photos that fail step 1 just deliver nil to the caller — caller is
    // responsible for showing a placeholder. We don't fall back for photos
    // because there's no reliable secondary path that PHImageManager doesn't
    // already cover internally.
    func loadThumbnail(for assetIdentifier: String, size: CGSize, contentMode: PHImageContentMode = .aspectFill, completion: @escaping (UIImage?) -> Void) {
        // `PHAsset.fetchAssets` + `.firstObject` is synchronous and hits the
        // Photos database on the calling thread. Each call is 5–15 ms — fine
        // in isolation, lethal when 30+ thumbnail cells appear at once on
        // the main actor. Capture the main-actor values up front, then hop
        // every disk-touching step (fetchAssets, requestImage, and its
        // completion bookkeeping) onto a userInitiated background queue.
        // The final UIImage is dispatched back to main below so the SwiftUI
        // cell update still lands on the right thread.
        //
        // PHImageManager.default() — NOT the shared PHCachingImageManager.
        // ScanCoordinator pumps `startCachingImages` for thousands of
        // assets through that caching manager during incremental refresh,
        // and a saturated caching manager NEVER delivers the live cell
        // request's completion callback. The retry path can't recover
        // because it only fires when the first callback returns nil, not
        // when the first callback never fires at all. That's the actual
        // root of the recurring "gray boxes that never resolve" bug — the
        // caching manager and the live UI must use independent queues.
        let mgr = PHImageManager.default()
        let screenScale = UIScreen.main.scale

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

        // Retina pixel scaling — callers pass logical-points sizes (e.g. a
        // 160-pt cell). PHImageManager.requestImage interprets `targetSize`
        // in PIXELS and downscales source images to fit. On a 3x retina
        // device, a 160-pt cell needs 480 actual pixels to render sharp;
        // requesting 160 returns an image upscaled 3× by SwiftUI and looks
        // muddy. UIScreen.main.scale is 3 on every shipping iPhone since
        // the X — multiplying the requested size by it is the canonical
        // fix for "thumbnails look blurry in the grid."
        let pixelSize = CGSize(
            width: size.width * screenScale,
            height: size.height * screenScale
        )

        // `.opportunistic` delivers a fast cached thumbnail first, then
        // upgrades to high-quality on a second callback. The previous
        // `.fastFormat` was returning nil for a large fraction of cells
        // when the photo daemon was under contention from PhotoIndexingService
        // (the "Indexing photo metadata… 79%" banner). `.opportunistic`'s
        // cached-thumb path is essentially guaranteed for local photos —
        // every PHAsset has a tiny preview iOS keeps warm for the system
        // Photos app — so the first callback almost always succeeds even
        // when the daemon is saturated.
        //
        // `.exact` resize mode (instead of `.fast`) is paired with the
        // pixel-accurate `targetSize` above so PHImageManager doesn't
        // round to a daemon-internal cached resolution that's smaller
        // than the screen needs. The cost is small for thumbnail-sized
        // requests and the win is crisp tiles even at the largest cell
        // sizes (the 160-pt InlineThumbnailCell in the duplicates flow).
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        // Tracks whether a non-nil image has already been delivered, so a
        // later nil/cancelled callback can never overwrite a successfully-
        // shown thumbnail with a placeholder.
        var didDeliverImage = false

        mgr.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }

            if let image = image {
                didDeliverImage = true
                DispatchQueue.main.async { completion(image) }
                return
            }

            // The opportunistic callback yielded nil. For videos, try the
            // AVAssetImageGenerator fallback (cinematic / iCloud-degraded
            // videos that PHImageManager can't serve). For photos, retry
            // once with `.highQualityFormat` which forces a network fetch
            // for iCloud-only assets — this is what catches the "I just
            // turned on iCloud Photos" case where the device has metadata
            // but no cached thumbnail.
            if asset.mediaType == .video {
                self?.generateVideoThumbnail(asset: asset, size: pixelSize) { fallback in
                    if didDeliverImage { return }
                    DispatchQueue.main.async { completion(fallback) }
                }
            } else {
                self?.retryHighQualityPhotoThumbnail(
                    asset: asset,
                    size: pixelSize,
                    contentMode: contentMode
                ) { retried in
                    if didDeliverImage { return }
                    DispatchQueue.main.async { completion(retried) }
                }
            }
        }
        }  // close DispatchQueue.global async block
    }

    /// Last-resort photo thumbnail path — `.highQualityFormat` forces an
    /// iCloud download if the asset isn't locally available. Slower than
    /// `.opportunistic` but always delivers something for valid PHAssets,
    /// so the grid never gets stuck on a permanent gray skeleton.
    private nonisolated func retryHighQualityPhotoThumbnail(
        asset: PHAsset,
        size: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping (UIImage?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            completion(image)
        }
    }

    /// Video thumbnail extraction via AVAssetImageGenerator — used as a
    /// fallback when PHImageManager can't return a frame. Pulls one frame
    /// from the first second of playable content (skipping any leading
    /// black fade) and returns it as a UIImage at the requested size.
    private nonisolated func generateVideoThumbnail(
        asset: PHAsset,
        size: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.deliveryMode = .fastFormat
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.version = .current

        PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, _, _ in
            guard let avAsset = avAsset else {
                completion(nil)
                return
            }

            Task {
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                // `size` is already in actual pixels — `loadThumbnail`
                // multiplies the caller's logical-points size by
                // UIScreen.main.scale before calling us, so we shouldn't
                // double again. (Previously we multiplied by 2× here for
                // retina; combined with the new caller-side scaling it
                // would have been 6× on a 3x device — way more than
                // needed and slower to extract.)
                generator.maximumSize = size
                // Wide tolerance — cell thumbnails don't need frame-accurate
                // seeking and tight tolerances make seek 5–10× slower.
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

                // 1 second in — typically past any leading black fade. If the
                // clip is shorter than 1 second, fall back to time zero.
                let cmDuration = try await avAsset.load(.duration)
                let duration = CMTimeGetSeconds(cmDuration)
                let target = duration > 1.0 ? CMTime(seconds: 1.0, preferredTimescale: 600) : .zero

                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: target)]) { _, image, _, result, _ in
                    if result == .succeeded, let image = image {
                        completion(UIImage(cgImage: image))
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    // MARK: - Cancellable Load Thumbnail
    //
    // Same loader logic as `loadThumbnail` above, but returns a
    // `ThumbnailRequestToken` so the caller can cancel the underlying
    // PHImageManager request when the cell scrolls off-screen.
    //
    // This is what every grid cell should be using. The non-cancellable
    // variant is kept around only for callers that genuinely don't recycle
    // (e.g. one-shot preview overlays that live for the whole presentation).
    @discardableResult
    func loadThumbnailCancellable(
        for assetIdentifier: String,
        size: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        completion: @escaping (UIImage?) -> Void
    ) -> ThumbnailRequestToken {
        let token = ThumbnailRequestToken()
        // See loadThumbnail above for why this is the default manager and
        // not the shared PHCachingImageManager.
        let mgr = PHImageManager.default()
        let screenScale = UIScreen.main.scale

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if token.isCancelled { return }
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if token.isCancelled { return }

            let pixelSize = CGSize(
                width: size.width * screenScale,
                height: size.height * screenScale
            )
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            var didDeliverImage = false

            let id = mgr.requestImage(
                for: asset,
                targetSize: pixelSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled { return }
                if token.isCancelled { return }

                if let image = image {
                    didDeliverImage = true
                    DispatchQueue.main.async { completion(image) }
                    return
                }

                if asset.mediaType == .video {
                    self?.generateVideoThumbnail(asset: asset, size: pixelSize) { fallback in
                        if didDeliverImage || token.isCancelled { return }
                        DispatchQueue.main.async { completion(fallback) }
                    }
                } else {
                    self?.retryHighQualityPhotoThumbnail(
                        asset: asset,
                        size: pixelSize,
                        contentMode: contentMode
                    ) { retried in
                        if didDeliverImage || token.isCancelled { return }
                        DispatchQueue.main.async { completion(retried) }
                    }
                }
            }
            token._setRequestId(id)
        }

        return token
    }

    // MARK: - Get Asset
    func getAsset(for identifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.firstObject
    }
}
