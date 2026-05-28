import Foundation
import Photos
import UIKit

// MARK: - Asset Thumbnail Cache
//
// Both PhotoCompressCard and VideoCompressCard request the same ~300×400
// thumbnail for an asset, and SwiftUI recycles those cells on every scroll,
// filter change, or list reshuffle. Without a shared cache each redraw fires
// a fresh PHImageManager.requestImage call — the grid flickers, the photo
// daemon burns CPU, and iCloud-backed libraries see repeated network round-
// trips.
//
// `AssetThumbnailCache` is a shared NSCache wrapped around a two-phase fetch:
//   1. Hand the caller the cached image synchronously if we have one.
//   2. Otherwise kick off an opportunistic PHImageManager request that
//      yields a low-res thumbnail in milliseconds, then upgrades to the
//      full-quality image on a second callback.
//
// NSCache handles eviction under memory pressure automatically, so the
// 120-entry soft limit only caps steady-state size.
final class AssetThumbnailCache {
    static let shared = AssetThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Bumped from 120 → 500 entries / 60 MB → 200 MB. The duplicates
        // and similar-photos detail screens routinely render 100+ groups
        // × 5+ visible cells with a 480px (3x retina of 160pt) thumbnail
        // each — at 120 entries, scrolling halfway through the list
        // evicted the cells we'd already paid to load and scroll-back
        // re-fired the daemon round-trip, which is what made the screen
        // feel sluggish over time. NSCache still evicts under memory
        // pressure (the @objc clearOnWarning observer below), so the
        // 200 MB cap is just a steady-state ceiling, not a leak target.
        c.countLimit = 500
        c.totalCostLimit = 200 * 1024 * 1024
        return c
    }()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearOnWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func clearOnWarning() {
        cache.removeAllObjects()
    }

    private func key(for assetId: String, size: CGSize) -> NSString {
        "\(assetId)@\(Int(size.width))x\(Int(size.height))" as NSString
    }

    /// Synchronous peek — returns a cached thumbnail if we already have it.
    func cached(assetId: String, size: CGSize) -> UIImage? {
        cache.object(forKey: key(for: assetId, size: size))
    }

    /// Insert a thumbnail into the cache so the next sync peek hits.
    /// Used by `PhotoThumbnailView` after a successful async load so
    /// scroll-back, sibling cells, and view rebuilds skip the skeleton.
    func store(image: UIImage, assetId: String, size: CGSize) {
        // Rough byte cost: width × height × 4 bytes/pixel (RGBA), with
        // the image's actual pixel size as the source of truth so a
        // small thumbnail doesn't get billed at the requested size.
        let pixelSize = image.size
        let cost = Int(pixelSize.width * pixelSize.height * (image.scale * image.scale) * 4)
        cache.setObject(image, forKey: key(for: assetId, size: size), cost: cost)
    }

    /// Opportunistic fetch: calls `onImage` potentially twice — once with a
    /// fast degraded thumbnail (if one is available cheaply), then again with
    /// the high-quality version. The caller is expected to replace the image
    /// on each callback. Returns a request ID so callers can cancel on reuse.
    ///
    /// `assetId` is passed alongside the PHAsset so callers that swap the
    /// asset underneath us (SwiftUI cell recycle) can early-out via id check
    /// before touching UI state.
    @discardableResult
    func loadThumbnail(
        for asset: PHAsset,
        assetId: String,
        size: CGSize,
        allowNetwork: Bool = true,
        onImage: @escaping (UIImage, _ isFinal: Bool) -> Void
    ) -> PHImageRequestID {
        let cacheKey = key(for: assetId, size: size)
        if let hit = cache.object(forKey: cacheKey) {
            // Deliver synchronously — caller treats this as the final image.
            onImage(hit, true)
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        // Opportunistic = daemon returns a fast low-res thumbnail first,
        // then the high-quality image on a second callback. Perceived
        // scroll performance is dramatically better than .highQualityFormat.
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false
        options.resizeMode = .fast

        let cache = self.cache
        return PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            guard let image = image else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                cache.setObject(image, forKey: cacheKey, cost: image.byteCostEstimate)
            }
            onImage(image, !isDegraded)
        }
    }

    func cancel(_ requestId: PHImageRequestID) {
        guard requestId != PHInvalidImageRequestID else { return }
        PHImageManager.default().cancelImageRequest(requestId)
    }

    /// Pre-heat the cache for a list of assets. Fire-and-forget — no cancel
    /// story, no callback. Intended to be called after scan completes so the
    /// first viewport of cards appears pre-rendered.
    func prefetch(_ assets: [PHAsset], size: CGSize, limit: Int = 40) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false // prefetch never hits network
        options.isSynchronous = false
        options.resizeMode = .fast

        let cache = self.cache
        for asset in assets.prefix(limit) {
            let cacheKey = key(for: asset.localIdentifier, size: size)
            if cache.object(forKey: cacheKey) != nil { continue }
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard let image = image else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                cache.setObject(image, forKey: cacheKey, cost: image.byteCostEstimate)
            }
        }
    }
}

private extension UIImage {
    /// Rough decoded-pixel cost for NSCache's totalCostLimit accounting.
    /// Uses 4 bytes per pixel (RGBA8) at the image's scaled pixel dims.
    var byteCostEstimate: Int {
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        return max(w * h * 4, 1024)
    }
}
