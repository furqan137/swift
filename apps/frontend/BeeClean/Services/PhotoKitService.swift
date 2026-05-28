import Foundation
import Photos
import UIKit
import AVFoundation

// MARK: - PhotoKit Service
@MainActor
class PhotoKitService: ObservableObject {
    static let shared = PhotoKitService()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var analysisProgress = PhotoAnalysisProgress()
    @Published var analyzedPhotos: [AnalyzedPhoto] = []
    @Published var isAnalyzing = false

    let analyzer = PhotoAnalyzer()
    /// Nonisolated so background scan code (ScanCoordinator) can call
    /// `startCachingImages` / `stopCachingImages` without hopping to
    /// @MainActor. PHCachingImageManager is documented as thread-safe.
    nonisolated let imageManager = PHCachingImageManager()

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization
    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        let granted = status == .authorized || status == .limited
        return granted
    }

    // MARK: - Fetch Policy
    //
    // - `includeAllBurstAssets = true`: iOS stores burst-mode sessions as a
    //   representative frame plus hidden siblings. A "cleanup the camera roll"
    //   feature that silently skips 9 out of 10 burst frames is broken by
    //   definition — those siblings are the core duplicate candidates.
    //
    // - `includeHiddenAssets = false`: user-hidden photos are intentionally
    //   hidden; surfacing them in a scan would surprise the user. This is the
    //   PHFetchOptions default but we set it explicitly so the policy doesn't
    //   silently flip if Apple changes the default.
    //
    // Shared iCloud Photo Library assets (iOS 16+) are filtered out in
    // `excludingSharedLibraryAssets` below — they belong to a family member
    // and the app must never offer them as cleanup candidates.
    nonisolated static func applyStandardPolicy(_ options: PHFetchOptions) {
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = false
    }

    /// Drops shared assets from a fetch result. Covers iCloud Shared Albums
    /// (`PHAssetSourceType.typeCloudShared`), the long-standing shared-stream
    /// feature where another user invited you into an album. We never want to
    /// offer those as cleanup candidates — the asset isn't really "yours" and
    /// deleting it from your library doesn't remove the shared copy anyway,
    /// just confuses the user.
    ///
    /// NOTE: iOS 16+ Shared Photo Library (the family library feature) does
    /// not expose a stable public per-asset predicate in current SDKs. The
    /// `sourceType` filter here covers the older shared-albums case, which
    /// is the dominant source of non-personal assets in real libraries.
    /// If/when Apple ships a public `isSharedLibraryAsset` accessor we can
    /// extend this.
    nonisolated static func excludingSharedLibraryAssets(
        _ fetch: PHFetchResult<PHAsset>
    ) -> PHFetchResult<PHAsset> {
        var personalIds: [String] = []
        var sawShared = false
        fetch.enumerateObjects { asset, _, _ in
            if asset.sourceType.contains(.typeCloudShared) {
                sawShared = true
            } else {
                personalIds.append(asset.localIdentifier)
            }
        }
        // Hot path: nothing shared, return the original fetch untouched so
        // ordering and any sort descriptors are preserved exactly.
        guard sawShared else { return fetch }
        let opts = PHFetchOptions()
        // Re-apply the same policy so the filtered result behaves identically.
        applyStandardPolicy(opts)
        return PHAsset.fetchAssets(withLocalIdentifiers: personalIds, options: opts)
    }

}
