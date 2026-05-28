import SwiftUI
import AVKit
import Photos

extension CompressionDetailView {

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

    // MARK: - Play Video Inline
    func playInline() async {
        guard let asset = video.asset else { return }
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Previous impl manually allocated/deallocated UnsafeMutablePointer<Bool>
        // to dedupe iCloud's double-callback. The dealloc happened on the FIRST
        // resume, but if the SECOND callback raced past the queue boundary it
        // would dereference freed memory → use-after-free crash. ResumeOnce is
        // a class — ARC keeps it alive as long as the closure captures it,
        // and NSLock makes the claim atomic across any callback thread.
        let resumed = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                DispatchQueue.main.async {
                    guard resumed.tryClaim() else { return }
                    if let urlAsset = avAsset as? AVURLAsset {
                        let player = AVPlayer(url: urlAsset.url)
                        self.inlinePlayer = player
                        self.isPlayingInline = true
                        player.play()
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Load Video URL for Playback (Full Screen)

    func loadVideoURL() async {
        guard let asset = video.asset else { return }
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Same one-shot guard as playInline above — see that comment.
        let resumed = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                DispatchQueue.main.async {
                    guard resumed.tryClaim() else { return }
                    if let urlAsset = avAsset as? AVURLAsset {
                        self.videoPlayerURL = urlAsset.url
                        self.showVideoPlayer = true
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Delete (single source of truth)
    //
    // Mirrors PhotoCompressionDetailView.runDelete — both delete entry
    // points (Delete Video / Save & Replace Original) flow through here so
    // the parent CompressViewModel.videos array is pruned the moment the
    // PHAsset is gone. Without this, the row stayed in the grid and
    // looked like the delete failed.
    @MainActor
    func runDelete(asset: PHAsset, dismissOnSuccess: Bool) async {
        let id = asset.localIdentifier
        let outcome = await engine.deleteOriginal(asset: asset)
        switch outcome {
        case .success:
            CompressViewModel.shared.removeVideo(localIdentifier: id)
            originalDeleted = true
            HapticManager.shared.notify(.success)
            if dismissOnSuccess { dismiss() }
        case .failed:
            // Video detail view doesn't currently surface a failure
            // banner; log and bail. Adding one would be a separate UI
            // task — out of scope for the data-correctness fix.
            HapticManager.shared.notify(.error)
        }
    }

    // MARK: - Load Thumbnail
    //
    // Lag fix: see PhotoCompressionDetailView.loadThumbnail for the
    // full rationale. Same root cause — `.highQualityFormat` blocks
    // for seconds on 4K clips while waiting for the full first-frame
    // decode. Switched to opportunistic two-callback delivery and
    // surface the grid-cached cell thumbnail synchronously so the
    // hero card never renders empty after the cover transition.
    func loadThumbnail() async {
        if let cached = AssetThumbnailCache.shared.cached(
            assetId: video.id,
            size: CGSize(width: 300, height: 400)
        ) {
            thumbnail = cached
        }

        guard let asset = video.asset else { return }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let size = CGSize(width: 800, height: 600)

        manager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            if let image = image {
                thumbnail = image
            }
        }
    }
}

