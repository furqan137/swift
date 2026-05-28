import SwiftUI
import Photos
import AVKit
import AVFoundation

// MARK: - Swipe Direction

enum SwipeDirection {
    case left, right
}

// MARK: - Preview Target
//
// Identifiable wrapper used by `.fullScreenCover(item:)` to drive the
// ZoomablePreviewOverlay from a `String?` asset id. The cover opens when
// the binding becomes non-nil and closes when it goes back to nil.
struct PreviewTarget: Identifiable, Equatable {
    let assetId: String
    var id: String { assetId }
}

// MARK: - Config

struct MediaSwipeConfig {
    let accentColor: Color
    let badgeIcon: String?
    let badgeLabel: String?
    /// When set, a Save / Saved button renders in the swipe deck's top bar
    /// and inside the tap-to-zoom preview. Independent from swipe-left
    /// (delete) and swipe-right (keep). Photos/Videos approved categories
    /// pass a context; banned flows (Guided Cleanup, Compress, etc.) pass
    /// nil and no button appears.
    let saveContext: SavedFindContext?

    init(
        accentColor: Color,
        badgeIcon: String? = nil,
        badgeLabel: String? = nil,
        saveContext: SavedFindContext? = nil
    ) {
        self.accentColor = accentColor
        self.badgeIcon = badgeIcon
        self.badgeLabel = badgeLabel
        self.saveContext = saveContext
    }
}

// MARK: - MediaSwipeView

struct MediaSwipeView<VM: MediaSwipeViewModel>: View {
    @StateObject private var vm: VM
    let config: MediaSwipeConfig
    @Environment(\.dismiss) private var dismiss
    @State private var showReview = false
    // Tap-to-preview target. When non-nil, ZoomablePreviewOverlay is shown
    // for that asset id over the swipe deck. Reset to nil on dismiss.
    @State private var previewAssetId: String?
    @State private var saveToast: BeeToast?
    @State private var showShareSheet: Bool = false

    init(vm: @autoclosure @escaping () -> VM, config: MediaSwipeConfig) {
        _vm = StateObject(wrappedValue: vm())
        self.config = config
    }

    var body: some View {
        ZStack {
            // Shared BitePal canvas — cool blue-lavender → warm
            // light-gray gradient used by every secondary surface.
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "DDE1F2"), location: 0.0),
                    .init(color: Color(hex: "DDE1F2"), location: 0.45),
                    .init(color: Color(hex: "E3E6EE"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if vm.isComplete {
                completionView
            } else {
                cardStack
                    .padding(.top, 80)
                    .padding(.bottom, 130)
                    .clipped()

                VStack {
                    topBar
                    Spacer()
                    bottomControls
                        .padding(.bottom, 40)
                }

                // Heart / bookmark / share rail — anchored to the right
                // edge, vertically centered on the card. Independent
                // from the swipe gesture; tapping a rail icon never
                // advances the deck.
                if let saveCtx = config.saveContext, let active = activeCard {
                    let enrichedCtx = SavedFindContext(
                        mediaType: saveCtx.mediaType,
                        sourceCategory: saveCtx.sourceCategory,
                        sourceApp: active.sourceApp ?? saveCtx.sourceApp
                    )
                    HStack {
                        Spacer()
                        SwipeCardActionRail(
                            assetId: active.assetId,
                            context: enrichedCtx,
                            onShareRequested: { showShareSheet = true }
                        )
                        .id(active.assetId) // hard-cut rail per card so heart/bookmark filled-state re-reads
                        .padding(.trailing, 14)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let active = activeCard {
                MediaShareSheet(
                    assetId: active.assetId,
                    onDismiss: { showShareSheet = false }
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.hidden)
            }
        }
        // Floating BottomNavBar lives in ContentView's outer ZStack, so a
        // fullScreenCover from inside a NavigationStack doesn't cover it —
        // bump the hide counter for the lifetime of the swipe deck.
        .hidesBottomNavBar()
        .fullScreenCover(isPresented: $showReview) {
            MediaReviewView(vm: vm, onDeleteComplete: { dismiss() })
        }
        // Tap-to-preview overlay. Driven by `previewAssetId` so the overlay
        // is bound to a specific asset id (not just a Bool) — the swipe deck
        // can advance underneath while the preview is open without the
        // overlay swapping content. Dismiss zeroes the id, taking the
        // overlay down with it.
        .fullScreenCover(item: Binding(
            get: { previewAssetId.map(PreviewTarget.init(assetId:)) },
            set: { previewAssetId = $0?.assetId }
        )) { target in
            ZoomablePreviewOverlay(
                assetIdentifier: target.assetId,
                saveContext: config.saveContext
            ) {
                previewAssetId = nil
            }
        }
        .beeToast($saveToast, topInset: 64)
        .onAppear {
            // Pause Spotify/YT/podcasts while the swipe deck is active.
            // Released in .onDisappear; ref-counted in the manager.
            AudioSessionManager.shared.requestExclusivePlayback()
        }
        .onDisappear {
            AudioSessionManager.shared.releaseExclusivePlayback()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.foreground)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceLight)
                    .clipShape(Circle())
            }

            Spacer()

            Text("\(vm.currentIndex + 1) / \(vm.items.count)")
                .font(.custom("Poppins-Bold", size: 16))
                .monospacedDigit()
                .foregroundColor(.foreground)

            Spacer()

            // Save button sits between the page counter and the trash
            // chip. Independent from swipe gestures — tapping Save only
            // bookmarks the active asset; the user still chooses to swipe
            // left (delete) or right (keep) afterwards.
            //
            // Context enrichment: if the active card carries a source-app
            // tag (Snapchat / Instagram / etc.) it overrides whatever the
            // config supplied so saves from generic categories
            // (Duplicates, Other Photos, …) still inherit app provenance.
            // The resulting badge surfaces on the Saved Finds tile.
            if let saveCtx = config.saveContext, let active = activeCard {
                let enrichedCtx = SavedFindContext(
                    mediaType: saveCtx.mediaType,
                    sourceCategory: saveCtx.sourceCategory,
                    sourceApp: active.sourceApp ?? saveCtx.sourceApp
                )
                SaveFindButton(
                    assetId: active.assetId,
                    context: enrichedCtx,
                    onSaved: { saveToast = BeeToast(message: "Saved to Finds", icon: "bookmark.fill") },
                    onAlreadySaved: { saveToast = BeeToast(message: "Already saved", icon: "bookmark.fill") },
                    style: .light
                )
                .padding(.trailing, 4)
            }

            Button {
                showReview = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.foreground)
                        .frame(width: 40, height: 40)
                        .background(Color.surfaceLight)
                        .clipShape(Circle())

                    if vm.totalMarked > 0 {
                        Text("\(vm.totalMarked)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.destructive)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .disabled(vm.totalMarked == 0)
            .opacity(vm.totalMarked == 0 ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Card Stack
    //
    // Renders ONLY the active card. The next 1–2 assets are pre-decoded into
    // `AssetThumbnailCache.shared` (warmed by `prefetchUpcoming`) but never
    // mounted to the view tree while the active card is on screen — so
    // there is no peek, offset, scale, shadow, or edge visible behind the
    // top card. When the active card flies off, `vm.currentIndex` advances,
    // the `.id(active.assetId)` on the swipe card flips, and SwiftUI hard-
    // cuts in the next card with fresh @State (offset = .zero). The cache
    // warm-up means the new card's image is already decoded, so the first
    // body evaluation paints it synchronously via PhotoThumbnailView's init.
    private var cardStack: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width
            let cardHeight = geo.size.height

            ZStack {
                if let active = activeCard {
                    MediaSwipeCardView(
                        asset: active,
                        cardSize: CGSize(width: cardWidth, height: cardHeight),
                        badgeIcon: config.badgeIcon,
                        badgeLabel: config.badgeLabel,
                        onTap: {
                            previewAssetId = active.assetId
                        }
                    ) { direction in
                        if direction == .left {
                            vm.swipeLeft()
                        } else {
                            vm.swipeRight()
                        }
                    }
                    .id(active.assetId)
                    .transition(.identity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                prefetchUpcoming(cardWidth: cardWidth, cardHeight: cardHeight)
            }
            .onChange(of: vm.currentIndex) { _, _ in
                prefetchUpcoming(cardWidth: cardWidth, cardHeight: cardHeight)
            }
        }
        .padding(.horizontal, 24)
    }

    private var activeCard: ScreenshotAsset? {
        guard vm.currentIndex < vm.items.count else { return nil }
        return vm.items[vm.currentIndex]
    }

    /// Decode the next 2 thumbnails into `AssetThumbnailCache` without
    /// mounting them to the view tree. Matches PhotoThumbnailView's request
    /// size (cardSize × 2) so the cache key lines up and the next card's
    /// init() resolves synchronously on mount.
    private func prefetchUpcoming(cardWidth: CGFloat, cardHeight: CGFloat) {
        let start = vm.currentIndex + 1
        let end = min(start + 2, vm.items.count)
        guard start < end else { return }
        let ids = vm.items[start..<end].map { $0.assetId }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        let size = CGSize(width: cardWidth * 2, height: cardHeight * 2)
        AssetThumbnailCache.shared.prefetch(assets, size: size, limit: 2)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 32) {
            Button {
                // Soft impact reads as "reversal" — softer than the
                // commit tap fired on a real swipe so the user feels
                // the action being undone rather than re-committed.
                HapticManager.shared.impact(.soft, intensity: 0.7)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    vm.undoLast()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.foreground)
                    .frame(width: 50, height: 50)
                    .background(Color.surfaceLight)
                    .clipShape(Circle())
            }
            .disabled(!vm.canUndo)
            .opacity(vm.canUndo ? 1 : 0.3)

            Button {
                vm.swipeLeft()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.destructive)
                    .clipShape(Circle())
            }

            Button {
                vm.swipeRight()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.success)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.success)

            Text(BCLoc.allDone.tr)
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(.foreground)

            if vm.totalMarked > 0 {
                Text("\(vm.totalMarked) \(vm.mediaLabel) marked for deletion")
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.mutedForeground)

                Text(formatBytes(vm.totalBytesMarked))
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(config.accentColor)

                PrimaryButton("Review & Delete", iconName: "trash.fill", isDestructive: true) {
                    // Warning tick before opening the destructive
                    // confirm sheet — the user is one tap away from
                    // permanent deletion, so the haptic should match
                    // the visual weight of the trash icon. The actual
                    // `notify(.success)` fires after the deletion
                    // lands in the review sheet.
                    HapticManager.shared.destructiveConfirm()
                    showReview = true
                }
                .padding(.horizontal, 40)
            } else {
                Text("No \(vm.mediaLabel) were marked for deletion")
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.mutedForeground)
            }

            SecondaryButton("Close") {
                dismiss()
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        // Milestone reveal — reuses the streak/ascending CoreHaptics
        // pattern so reaching "All Done!" feels like an achievement,
        // not just an empty state.
        .onAppear {
            HapticManager.shared.streakReveal()
        }
    }
}

// MARK: - Swipe Card View

private struct MediaSwipeCardView: View {
    let asset: ScreenshotAsset
    let cardSize: CGSize
    let badgeIcon: String?
    let badgeLabel: String?
    /// Single-tap handler. Used by the parent to open the zoomable preview
    /// overlay for the visible card — "click into the image" for any
    /// photo or video category.
    let onTap: () -> Void
    let onSwipe: (SwipeDirection) -> Void

    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            // SwipeCardMedia transparently swaps between a static thumbnail
            // (photo) and an auto-playing muted loop (video) once the
            // PHAsset's mediaType resolves. Mirrors the Cleanup behaviour
            // the user pointed at: tapping into a video category presents
            // playing previews on the active card so the user can verify
            // what they're about to swipe away.
            SwipeCardMedia(
                assetId: asset.assetId,
                cardSize: cardSize
            )
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(swipeOverlay)
            // Tap to preview. Suppressed mid-drag so a swipe that
            // doesn't pass the threshold doesn't accidentally open
            // the overlay on release. The drag gesture below sets
            // `isDragging` for the duration of the gesture.
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                guard !isDragging else { return }
                onTap()
            }

            if let icon = badgeIcon, let label = badgeLabel {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(label)
                            .font(.custom("Poppins-Bold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                }
            }

            // Source-app badge — top-right corner of the swipe card. Larger
            // than the grid-tile badge (32pt vs 22pt) since the card itself
            // is full-screen sized. Renders nothing for `nil` / `.camera`.
            SocialSourceBadge(source: asset.sourceApp, size: 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(14)
        }
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .offset(x: offset.width)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    offset = value.translation
                }
                .onEnded { value in
                    let distance = value.translation.width

                    if abs(distance) > swipeThreshold {
                        let direction: SwipeDirection = distance < 0 ? .left : .right
                        HapticManager.shared.tapSensation()
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset.width = distance < 0 ? -500 : 500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            offset = .zero
                            onSwipe(direction)
                            isDragging = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = .zero
                        }
                        // Hold the drag flag for a tick so the sub-threshold
                        // release doesn't immediately fire the tap recogniser
                        // and open the preview overlay.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isDragging = false
                        }
                    }
                }
        )
    }

    @ViewBuilder
    private var swipeOverlay: some View {
        // Tinder-style wash + rotated DELETE/KEEP label. The label is the
        // load-bearing intent cue — the colored tint alone read as
        // ambiguous in user testing. Same overlay treatment lives on the
        // email swipe deck for visual consistency across every category.
        ZStack {
            if offset.width < 0 {
                let intensity = Double(min(abs(offset.width) / swipeThreshold, 1))
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(intensity * 0.42))

                Text("Remove")
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .opacity(intensity)
                    .rotationEffect(.degrees(-14))
            }

            if offset.width > 0 {
                let intensity = Double(min(offset.width / swipeThreshold, 1))
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(intensity * 0.42))

                Text("Save")
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .opacity(intensity)
                    .rotationEffect(.degrees(14))
            }
        }
    }
}

// MARK: - Swipe Card Media
//
// Renders either a static photo thumbnail or an auto-playing muted video
// loop, depending on the underlying PHAsset's mediaType. Matches the
// Cleanup-app behaviour the user pointed at: when a video category drops
// you into the swipe deck, the active card plays the clip in-place so you
// know what you're about to swipe away.
//
// Lifecycle: the player is built once per assetId on appear. When the
// parent ForEach swaps a fresh asset into this slot (next swipe), SwiftUI
// tears down this view and rebuilds it — `.task(id:)` re-fetches the new
// asset's player item. The player is muted and loops via an
// AVPlayerLooper so the clip stays in motion regardless of duration; the
// user can mute/unmute through the full-screen preview if they want
// audio.

struct SwipeCardMedia: View {
    let assetId: String
    let cardSize: CGSize
    /// When true, the video case auto-plays with audio ON and overlays a
    /// mute toggle (bottom-right) plus a thin draggable scrub bar pinned
    /// to the very bottom edge. Photos are unaffected. Default is the
    /// legacy preview behavior: muted, looped, no controls.
    var audioControlsEnabled: Bool = false
    /// Fires once when this asset truly cannot be rendered (PHAsset fetch
    /// returns nil, or PhotoThumbnailView exhausts its retry chain).
    /// Owners should route to a "drop this id from my list" action so the
    /// dead cell vanishes instead of sitting on screen as Color.clear.
    var onUnloadable: (() -> Void)? = nil

    @State private var mediaType: PHAssetMediaType?
    @State private var playerItem: AVPlayerItem?
    @State private var player: AVQueuePlayer?
    @State private var isMuted: Bool = false
    @State private var progress: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var durationSeconds: Double = 0
    @State private var timeObserverToken: Any?

    var body: some View {
        ZStack(alignment: .bottom) {
            if mediaType == .video, let item = playerItem {
                AutoPlayingVideoCard(
                    playerItem: item,
                    startsMuted: !audioControlsEnabled,
                    onPlayer: audioControlsEnabled ? { p in attachPlayer(p, item: item) } : nil
                )
                // Pass touches straight through to the parent swipe gesture.
                // AVPlayerViewController otherwise installs UIKit recognizers
                // that swallow drags before SwiftUI sees them. The mute
                // toggle and scrub bar sit ABOVE this in the ZStack and
                // own their own hit areas, so they're unaffected.
                .allowsHitTesting(false)
                if audioControlsEnabled {
                    videoControlsOverlay
                }
            } else {
                PhotoThumbnailView(
                    assetIdentifier: assetId,
                    size: CGSize(width: cardSize.width * 2, height: cardSize.height * 2),
                    onUnloadable: { onUnloadable?() }
                )
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .task(id: assetId) {
            await resolveMedia()
        }
        .onDisappear { detachPlayer() }
    }

    @ViewBuilder
    private var videoControlsOverlay: some View {
        // Mute toggle — bottom-right corner. Wrapped in HStack + Spacer so
        // the Button's hit area stays tight around the 32x32 icon;
        // otherwise its full-width frame would swallow swipes on the
        // bottom strip and prevent the parent swipe gesture from firing.
        HStack {
            Spacer()
            Button {
                isMuted.toggle()
                player?.isMuted = isMuted
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .bottom)

        // Thin scrub bar — pinned to the very bottom edge of the card.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
            .frame(height: 3)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let p = max(0, min(1, value.location.x / geo.size.width))
                        progress = Double(p)
                    }
                    .onEnded { _ in
                        seek(to: progress)
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 3)
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func attachPlayer(_ p: AVQueuePlayer, item: AVPlayerItem) {
        detachPlayer()
        player = p
        isMuted = p.isMuted
        Task {
            if let cm = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(cm)
                if seconds.isFinite, seconds > 0 {
                    await MainActor.run { durationSeconds = seconds }
                }
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing, durationSeconds > 0 else { return }
            let current = CMTimeGetSeconds(time)
            guard current.isFinite else { return }
            progress = min(1, max(0, current / durationSeconds))
        }
    }

    private func detachPlayer() {
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player = nil
    }

    private func seek(to fraction: Double) {
        guard let player, durationSeconds > 0 else { return }
        let target = CMTime(seconds: durationSeconds * fraction, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func resolveMedia() async {
        // Always reset before kicking off a fresh resolve — otherwise a
        // stale player item from the previous card leaks into the new one
        // for a frame and you see the wrong clip start to play.
        await MainActor.run {
            detachPlayer()
            mediaType = nil
            playerItem = nil
            progress = 0
            durationSeconds = 0
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetched.firstObject else {
            await MainActor.run { onUnloadable?() }
            return
        }
        await MainActor.run { mediaType = asset.mediaType }
        guard asset.mediaType == .video else { return }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.version = .current

        let resumed = ResumeOnce()
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if resumed.tryClaim() {
                    continuation.resume(returning: item)
                }
            }
        }
        await MainActor.run { playerItem = item }
    }
}

// MARK: - Auto-Playing Video Card
//
// AVPlayerLooper-backed view that auto-plays muted and loops the asset.
// Hides the system playback controls — the card is a preview surface, not
// a player UI; tapping the card opens the full-screen ZoomablePreviewOverlay
// where the user gets system controls + audio.

struct AutoPlayingVideoCard: UIViewControllerRepresentable {
    let playerItem: AVPlayerItem
    var startsMuted: Bool = true
    var onPlayer: ((AVQueuePlayer) -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.view.backgroundColor = .black
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        // AVPlayerLooper requires an AVQueuePlayer + an AVAsset (the looper
        // re-queues a fresh copy of the item every time it ends). The
        // AVPlayerItem we received from PHImageManager already has the
        // right asset attached — re-derive it for the looper.
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = startsMuted
        queuePlayer.actionAtItemEnd = .none
        // Retain the looper on the coordinator so it survives the lifetime
        // of the controller; without a strong reference ARC tears it down
        // immediately and looping stops after the first cycle.
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        context.coordinator.looper = looper

        controller.player = queuePlayer
        queuePlayer.play()
        if let onPlayer {
            DispatchQueue.main.async { onPlayer(queuePlayer) }
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // No-op: the controller is rebuilt by the parent when assetId
        // changes (SwipeCardMedia recreates SwipeCardMedia via .task(id:)
        // → which tears the controller down). Nothing to refresh in place.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}
