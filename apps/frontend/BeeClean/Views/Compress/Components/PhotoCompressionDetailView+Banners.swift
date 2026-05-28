import SwiftUI
import Photos

extension PhotoCompressionDetailView {

    // MARK: - Save Success Banner

    var saveSuccessBanner: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "22C55E"))
                Text("Saved to Camera Roll")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "1C1917"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(GlassPanel(cornerRadius: 18, elevation: .lifted))
            .padding(.top, 60)

            Spacer()
        }
    }

    // MARK: - Save Error Banner

    var saveErrorBanner: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "DC2626"))
                Text(saveErrorMessage)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(GlassPanel(cornerRadius: 18, elevation: .lifted))
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()
        }
    }

    func presentSaveError(_ message: String) {
        HapticManager.shared.notify(.error)
        saveErrorMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSaveError = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { showSaveError = false }
        }
    }

    // MARK: - Delete (single source of truth)
    //
    // Both delete paths — "Delete Photo" (skip compression) and "Save &
    // Replace Original" (after compression) — funnel through here so the
    // post-delete bookkeeping is identical:
    //
    //   1. Run PHAssetChangeRequest.deleteAssets via the engine.
    //   2. On success, prune the photo from `CompressViewModel.photos`
    //      so the grid reflects reality immediately. (Without this the
    //      photo "looked like it didn't delete" — the row stayed in the
    //      grid even though iOS Photos had moved it to Recently Deleted.)
    //   3. Mark `originalDeleted` and either dismiss (delete-only flow) or
    //      keep the result screen open (replace flow).
    //   4. On failure, surface the system reason in the existing error
    //      banner instead of silently no-op'ing.
    @MainActor
    func runDelete(asset: PHAsset, dismissOnSuccess: Bool) async {
        let id = asset.localIdentifier
        let outcome = await engine.deleteOriginal(asset: asset)
        switch outcome {
        case .success:
            CompressViewModel.shared.removePhoto(localIdentifier: id)
            originalDeleted = true
            HapticManager.shared.notify(.success)
            if dismissOnSuccess { dismiss() }
        case .failed(let reason):
            presentSaveError(reason)
        }
    }

    // MARK: - Load Thumbnail
    //
    // Lag fix: previously used `.highQualityFormat` which forces
    // PHImageManager to wait for the full non-degraded decode (and
    // an iCloud round-trip if the asset is cloud-only). On 48 MP
    // iPhone originals or large HEIFs that's a 2–5 second blocker
    // — the user tapped a card and stared at a placeholder while
    // the detail view sat empty. We now:
    //   1. Synchronously surface the grid-cached thumbnail (the
    //      small 300×400 cell image that's already decoded in
    //      `AssetThumbnailCache`) so SOMETHING shows on the very
    //      first frame after the cover transition.
    //   2. Request via `.opportunistic` — PhotoKit hands us a fast
    //      low-res preview in ~50 ms, then upgrades to the
    //      high-quality image on a second callback. Either way,
    //      the user never sees an empty hero card.
    func loadThumbnail() async {
        // (1) Cache peek — the grid almost always populated a
        // 300×400 cell-sized thumbnail before the user tapped, so
        // even on cold-cache misses this is at worst a no-op.
        if let cached = AssetThumbnailCache.shared.cached(
            assetId: photo.id,
            size: CGSize(width: 300, height: 400)
        ) {
            thumbnail = cached
        }

        guard let asset = photo.asset else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        // (2) Opportunistic = fast degraded → final two-callback
        // sequence. Replaces the previous `.highQualityFormat`
        // single-final-callback that blocked for seconds.
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let size = CGSize(width: 1200, height: 1600)

        manager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            // Skip cancelled callbacks (briefly nil-clears the
            // hero on rapid re-entry otherwise).
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            if let image = image {
                thumbnail = image
            }
        }
    }
}

