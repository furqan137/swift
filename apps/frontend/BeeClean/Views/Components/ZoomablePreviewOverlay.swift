import SwiftUI
import UIKit
import Photos
import AVKit

// MARK: - Zoomable Preview Overlay
//
// Full-screen "click into the image" preview surfaced from any swipe card
// (MediaSwipeView for flat categories, SimilarDetailPagerView for grouped
// categories). The grids and swipe decks already reach every photo and
// video category — wiring tap-to-preview at the swipe-card level means
// every category gets the feature for free.
//
// Photo path: pinch + double-tap zoom up to 4×, drag-to-pan when zoomed.
// Video path: native AVPlayer with the system controls (scrubber, mute,
// AirPlay, picture-in-picture). No autoplay — the user explicitly tapped
// to preview, so the play button is the affordance.
//
// Resolution policy: photos load via `requestImage(targetSize: maximum,
// contentMode: aspectFit)` so the user can zoom into pixel-level detail
// (the whole point of "click into the image"). On a 48 MP iPhone shot
// that's a one-time ~30 MB decode, fine for a foreground sheet.

struct ZoomablePreviewOverlay: View {
    let assetIdentifier: String
    /// Optional context for the Save button. When non-nil, a Save / Saved
    /// pill renders alongside the close chip. Photos/Videos approved
    /// surfaces pass this; banned flows (Compress, Guided Cleanup) leave
    /// it nil and no Save button appears.
    let saveContext: SavedFindContext?
    /// Optional unsave handler, forwarded to the embedded `SaveFindButton`.
    /// When provided AND the item is already saved, tapping the pill
    /// removes it from Saved Finds and runs this closure (so the host can
    /// also dismiss the preview / show a toast). Only the Saved Finds
    /// grid wires this — every other surface leaves it nil.
    let onUnsave: (() -> Void)?
    /// Optional context line rendered under the header — e.g.
    /// "Saved from Duplicates · 3 days ago". Only the Saved Finds grid
    /// wires this; previews launched from cleanup screens leave it nil
    /// (the user already knows where they came from).
    let caption: String?
    let onDismiss: () -> Void

    @State private var asset: PHAsset?
    @State private var fullImage: UIImage?
    @State private var playerItem: AVPlayerItem?
    @State private var isLoading = true
    @State private var saveToast: BeeToast?
    /// Drives the system Share sheet. Surfaces a `UIActivityViewController`
    /// over the preview with the full-resolution UIImage as the share
    /// payload. Only enabled for photos in v1 — videos require an
    /// AVURLAsset round-trip that we can add later if anyone asks.
    @State private var showPreviewShareSheet = false

    init(
        assetIdentifier: String,
        saveContext: SavedFindContext? = nil,
        onUnsave: (() -> Void)? = nil,
        caption: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.assetIdentifier = assetIdentifier
        self.saveContext = saveContext
        self.onUnsave = onUnsave
        self.caption = caption
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Header strip + content stack. The strip lives ABOVE the
            // photo, not on top of it — so the X never sits on the
            // user's actual pixels (which was the case before for any
            // portrait shot, where aspectFit ran the photo to the very
            // top of the screen and the X covered the corner of the
            // image). Putting the X in its own row guarantees the
            // photo area below is fully visible.
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        // Same back-nav rhythm as every other dismiss
                        // chevron in the app — the X is functionally
                        // the same gesture in a different glyph.
                        HapticManager.shared.arrowNudge(.backward)
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                            )
                    }

                    Spacer()

                    // Share — system Activity sheet over the photo. Disabled
                    // for videos in v1 (videos need a file-URL payload, not
                    // a UIImage), and disabled until `fullImage` lands so we
                    // don't share a half-decoded asset. Sits between X and
                    // Save so the right edge stays consistent with the
                    // bookmark glyph the user already learned.
                    if asset?.mediaType != .video {
                        Button {
                            HapticManager.shared.buttonTap()
                            showPreviewShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        // Hide AND disable hit-testing while the full
                        // image is still decoding. The old `.disabled
                        // + opacity(0.45)` left the button frame in the
                        // hit-test tree, and on tight HStacks (Share is
                        // 8pt to the left of Save) edge taps meant for
                        // Save were silently routing to the disabled
                        // Share button and dying there. `opacity(0)
                        // + .allowsHitTesting(false)` removes both the
                        // visual AND the hit region until the image is
                        // ready to share.
                        .opacity(fullImage == nil ? 0 : 1)
                        .allowsHitTesting(fullImage != nil)
                        .padding(.trailing, 8)
                    }

                    if let saveCtx = saveContext {
                        SaveFindButton(
                            assetId: assetIdentifier,
                            context: saveCtx,
                            onSaved: { saveToast = BeeToast(message: "Saved to Finds", icon: "bookmark.fill") },
                            onAlreadySaved: { saveToast = BeeToast(message: "Already saved", icon: "bookmark.fill") },
                            onUnsave: onUnsave,
                            style: .dark
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Optional context line — e.g. "Saved from Duplicates · 3
                // days ago". Lives between header and content so it
                // reads as a subtitle to the preview chrome, not a
                // floating annotation on top of the photo.
                if let caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                content
            }
        }
        .statusBarHidden()
        .beeToast($saveToast, topInset: 70)
        .sheet(isPresented: $showPreviewShareSheet) {
            // Wrapped in a Group so the conditional unwrap stays clean
            // — `.sheet` content closure can't itself be `if let`.
            Group {
                if let image = fullImage {
                    PreviewShareSheet(items: [image])
                        .ignoresSafeArea()
                }
            }
        }
        // Floating BottomNavBar lives in ContentView's outer ZStack — outside
        // every NavigationStack, so a fullScreenCover presented from inside
        // the stack doesn't cover it. Bump the hide counter here so the bar
        // is gone while preview is on screen and snaps back on dismiss.
        .hidesBottomNavBar()
        .task {
            await loadAsset()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let asset, asset.mediaType == .video {
            videoBody(asset: asset)
        } else if let image = fullImage {
            ZoomableImageView(image: image, onDismiss: onDismiss)
        } else if isLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.7))
                Text("Couldn't load preview")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func videoBody(asset: PHAsset) -> some View {
        if let item = playerItem {
            ZoomablePlayerView(playerItem: item)
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
                .task { await loadVideo(asset: asset) }
        }
    }

    // MARK: - Loading

    private func loadAsset() async {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetched.firstObject else {
            isLoading = false
            return
        }
        self.asset = asset

        if asset.mediaType == .image {
            await loadFullImage(asset: asset)
        }
        // Videos lazy-load in `videoBody` once the asset is known.
        isLoading = false
    }

    private func loadFullImage(asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .none
        options.isSynchronous = false

        let image: UIImage? = await withCheckedContinuation { continuation in
            // PHImageManager can deliver multiple callbacks (degraded then
            // final). Guard with a lock so we only resume the continuation
            // once — Swift traps on a second resume.
            let lock = NSLock()
            var didResume = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // Always wait for the non-degraded image — the user is
                // pinching to inspect details, a fuzzy preview defeats
                // the point.
                if isDegraded { return }
                lock.lock()
                if didResume {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()
                continuation.resume(returning: image)
            }
        }

        await MainActor.run {
            self.fullImage = image
        }
    }

    private func loadVideo(asset: PHAsset) async {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        // requestPlayerItem can fire its handler more than once for iCloud-
        // backed assets (download progress + final). Resuming the continuation
        // twice is a hard runtime trap, so guard with a one-shot claim.
        let resumed = ResumeOnce()
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if resumed.tryClaim() {
                    continuation.resume(returning: item)
                }
            }
        }

        await MainActor.run {
            self.playerItem = item
        }
    }
}

// MARK: - Zoomable Image View
//
// Pinch + double-tap zoom and pan, contained in the parent's bounds.
// Implementation notes:
// - Magnification is tracked in two pieces: `currentScale` (the committed
//   value from prior gestures) and `gestureScale` (the live multiplier
//   from the active pinch). The displayed scale is the product. On
//   gesture-end we fold `gestureScale` back into `currentScale` so the
//   next pinch starts from rest.
// - Pan is allowed only above 1× and is clamped so the image can't be
//   dragged past its own edges into empty space.
// - Double-tap toggles between 1× and 2.5× and resets the offset.

private struct ZoomableImageView: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var currentScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    @State private var currentOffset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let displayedScale = currentScale * gestureScale
            let totalOffset = CGSize(
                width: currentOffset.width + gestureOffset.width,
                height: currentOffset.height + gestureOffset.height
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(displayedScale)
                .offset(totalOffset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(magnification(geo: geo))
                .simultaneousGesture(panning(geo: geo))
                .onTapGesture(count: 2) {
                    handleDoubleTap()
                }
                .onTapGesture {
                    // Single-tap on a non-zoomed image dismisses, matching
                    // the Apple Photos "tap to dismiss" affordance. When
                    // zoomed, single-tap is a no-op so the user doesn't
                    // accidentally exit while inspecting detail.
                    if currentScale <= minScale + 0.01 {
                        onDismiss()
                    }
                }
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: currentScale)
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: currentOffset)
        }
    }

    // MARK: Gestures

    private func magnification(geo: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let next = (currentScale * value).clamped(to: minScale...maxScale)
                currentScale = next
                if next <= minScale + 0.01 {
                    currentOffset = .zero
                } else {
                    currentOffset = clampedOffset(currentOffset, scale: next, in: geo.size)
                }
            }
    }

    private func panning(geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                guard currentScale > minScale + 0.01 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard currentScale > minScale + 0.01 else { return }
                let proposed = CGSize(
                    width: currentOffset.width + value.translation.width,
                    height: currentOffset.height + value.translation.height
                )
                currentOffset = clampedOffset(proposed, scale: currentScale, in: geo.size)
            }
    }

    private func handleDoubleTap() {
        if currentScale > minScale + 0.01 {
            currentScale = minScale
            currentOffset = .zero
        } else {
            currentScale = doubleTapScale
        }
    }

    /// Clamps `offset` so the scaled image's edges can't be dragged inside
    /// the visible bounds — i.e. you can pan within the image but not past
    /// it. Approximates the image's scaled bounding box using the
    /// container size; .scaledToFit centers the image so left/right and
    /// top/bottom limits are symmetric.
    private func clampedOffset(_ offset: CGSize, scale: CGFloat, in container: CGSize) -> CGSize {
        let extraX = max(0, (container.width * scale - container.width) / 2)
        let extraY = max(0, (container.height * scale - container.height) / 2)
        return CGSize(
            width: offset.width.clamped(to: -extraX...extraX),
            height: offset.height.clamped(to: -extraY...extraY)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Video Player

private struct ZoomablePlayerView: UIViewControllerRepresentable {
    let playerItem: AVPlayerItem

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(playerItem: playerItem)
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        // Auto-play on appear — the user explicitly opened this video,
        // they shouldn't have to tap a second time to start it. Friction
        // on a tap-to-watch flow is anti-pattern. Mute defaults to off
        // (system AVPlayer respects ringer/silent like the system
        // Photos app — same expectation).
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No-op: the controller's player is created once and never swapped
        // for the lifetime of the overlay, so updates would just churn.
    }

    // Stop playback + release the AVPlayer when SwiftUI tears the view
    // down. Without this, dismissing the preview mid-playback leaves the
    // player running on the audio session for ~1s before iOS reclaims
    // the destroyed view, burning battery and (worse) keeping the
    // audio session active so other UI sounds get ducked.
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }
}

// MARK: - Share Sheet
//
// Thin `UIActivityViewController` wrapper so SwiftUI can present the
// system share sheet over the preview. `items` is whatever the share
// target should accept — `UIImage` works for photos and surfaces every
// installed activity (Messages, Mail, AirDrop, Save to Files, etc).
// We don't customize `excludedActivityTypes` because the system already
// hides irrelevant activities based on the item type.

private struct PreviewShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // No-op — share items are captured at construction time.
    }
}
