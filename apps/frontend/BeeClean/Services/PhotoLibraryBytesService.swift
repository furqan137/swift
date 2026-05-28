import Foundation
import Photos

// MARK: - Photo Library Bytes Service
//
// Computes the user's full photo library bytes — same number Apple's
// Settings → General → iPhone Storage → Photos shows ("50.67 GB"). We
// use this to:
//   1. Compare against our own dashboard's "Space to Clean" total so
//      we can detect when our scan is undercounting the library and
//      surface a more honest headline.
//   2. POST to the backend alongside ScanSnapshotService so the
//      server-side view has both the total library footprint AND the
//      cleanable subset.
//
// Implementation note: there's no single PhotoKit API that returns
// "total library bytes." We walk every PHAsset and sum the largest
// PHAssetResource per asset (mirrors the heuristic Photos uses — Live
// Photos count once, edited assets count their largest representation,
// not original+edited summed).
@MainActor
final class PhotoLibraryBytesService: ObservableObject {
    static let shared = PhotoLibraryBytesService()

    @Published private(set) var totalLibraryBytes: Int64 = 0
    @Published private(set) var lastComputedAt: Date?
    @Published private(set) var isComputing: Bool = false

    /// Re-walking ~25k assets is not free. Cap to once per 10 min unless
    /// the caller forces it (e.g., after a large deletion). Most cleanups
    /// move ~10s of MB, well within the noise of a 50 GB library.
    private let minInterval: TimeInterval = 600

    private init() {}

    /// Returns the cached value immediately and kicks off a recompute
    /// if stale. Safe to call from any view body.
    func refreshIfStale(force: Bool = false) {
        guard !isComputing else { return }
        if !force, let last = lastComputedAt,
           Date().timeIntervalSince(last) < minInterval {
            return
        }
        Task { await recompute() }
    }

    func recompute() async {
        let status = PhotoKitService.shared.authorizationStatus
        guard status == .authorized || status == .limited else { return }
        isComputing = true
        defer { isComputing = false }

        let bytes = await Task.detached(priority: .utility) { () -> Int64 in
            var sum: Int64 = 0
            let opts = PHFetchOptions()
            opts.includeHiddenAssets = false
            opts.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            let assets = PHAsset.fetchAssets(with: opts)
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                // Pick the LARGEST resource per asset — same heuristic
                // Photos uses for its "Photos & Videos" line in iPhone
                // Storage. Avoids double-counting an asset's original +
                // edited representation.
                // PHAssetResource exposes file size via the private
                // KVC key `"fileSize"` (NSNumber). Route via NSObject so
                // a missing key on a future iOS returns nil instead of
                // crashing — the asset just contributes 0 in that case
                // (conservative undercount, never a crash).
                var maxBytes: Int64 = 0
                for r in resources {
                    if let n = (r as NSObject).value(forKey: "fileSize") as? NSNumber {
                        let v = n.int64Value
                        if v > maxBytes { maxBytes = v }
                    }
                }
                sum += maxBytes
            }
            return sum
        }.value

        totalLibraryBytes = bytes
        lastComputedAt = Date()
    }
}
