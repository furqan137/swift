import SwiftUI
import Photos
import AVFoundation
import RevenueCatUI
import AVKit

// MARK: - Compression Detail View
struct CompressionDetailView: View {
    let video: VideoAsset
    @StateObject var engine = CompressionEngine()
    @State var selectedLevel: CompressionLevel = .medium
    @State var thumbnail: UIImage?
    @State var showSaveSuccess = false
    @State var showDeleteConfirm = false
    @State var showDeleteOnlyConfirm = false
    @State var originalDeleted = false
    @State var showVideoPlayer = false
    @State var videoPlayerURL: URL?
    @State var inlinePlayer: AVPlayer?
    @State var isPlayingInline = false
    @State var showCompressGate = false
    @State var showPaywall = false
    /// Stashed result URL for the gate callback to use after approval.
    @State var pendingSaveURL: URL?
    @StateObject var actionFlow = ActionFlowCoordinator()
    @Environment(\.dismiss) var dismiss

    // Result animation states
    @State var resultCheckScale: CGFloat = 0
    @State var resultCheckOpacity: Double = 0
    @State var resultRingProgress: CGFloat = 0
    @State var resultTextOpacity: Double = 0
    @State var resultStatsOpacity: Double = 0
    @State var resultActionsOffset: CGFloat = 40
    @State var resultActionsOpacity: Double = 0

    var activeProgress: Float { engine.progress }
    var activePhase: CompressionPhase { engine.phase }
    var activeIsCompressing: Bool { engine.isCompressing }
    var activeResult: CompressionResult? { engine.result }

    // Use accurate estimate when resolution/bitrate available
    var estimatedSize: Int64 {
        selectedLevel.estimatedSize(from: video.fileSize, resolution: video.resolution, bitrate: video.bitrate)
    }

    var estimatedSavings: Int64 {
        selectedLevel.estimatedSavings(from: video.fileSize, resolution: video.resolution, bitrate: video.bitrate)
    }

    var savingsPercent: Int {
        guard video.fileSize > 0 else { return 0 }
        let est = estimatedSize
        guard est < video.fileSize else { return 0 }
        return Int((1.0 - Double(est) / Double(video.fileSize)) * 100)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                glassBackdrop

                VStack(spacing: 0) {
                    customHeader
                    if activePhase == .done, let result = activeResult {
                        resultScreen(result)
                    } else if activeIsCompressing {
                        progressScreen
                    } else {
                        setupScreen
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadThumbnail() }
            // Previously auto-played on appear, which collapsed playback to a
            // single hidden control: tap to stop, no scrubber, no fullscreen.
            // Now the detail view shows the thumbnail + play button on entry
            // and the user explicitly chooses when to start playback —
            // matching the Cleanup video flow. Once they tap play, the
            // inline player is AVPlayerViewController-backed so they get
            // every native control (play/pause, scrub, fullscreen, mute,
            // AirPlay, PiP) without leaving this screen.
            .alert("Replace Original?", isPresented: $showDeleteConfirm) {
                Button("Replace", role: .destructive) {
                    if let asset = video.asset {
                        Task { await runDelete(asset: asset, dismissOnSuccess: false) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The original \(formatBytes(video.fileSize)) video will be moved to Recently Deleted.")
            }
            .alert("Delete Video?", isPresented: $showDeleteOnlyConfirm) {
                Button("Delete", role: .destructive) {
                    if let asset = video.asset {
                        Task { await runDelete(asset: asset, dismissOnSuccess: true) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This \(formatBytes(video.fileSize)) video will be moved to Recently Deleted.")
            }
            .overlay {
                if showSaveSuccess {
                    saveSuccessBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .hidesBottomNavBar()
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let url = videoPlayerURL {
                VideoPlayerFullScreen(url: url, isPresented: $showVideoPlayer)
            }
        }
        .sheet(isPresented: $showCompressGate) {
            GateCoordinator(
                config: .config(for: .compress),
                selectedCount: 1,
                onActionApproved: { _ in
                    if let url = pendingSaveURL, let compressionResult = engine.result {
                        Task {
                            await actionFlow.execute(section: .compress, actionType: .compress, itemCount: 1) {
                                let saved = await engine.saveToPhotoLibrary(url: url)
                                guard saved else { throw NSError(domain: "CompressionSave", code: -1) }
                                await MainActor.run {
                                    HiveStatsManager.shared.recordCleanup(
                                        action: "compression",
                                        itemCount: 1,
                                        bytesSaved: Int64(compressionResult.savings),
                                        category: .videoCompression
                                    )
                                }
                                return ActionResult(
                                    section: .compress, actionType: .compress,
                                    itemsProcessed: 1, bytesFreed: nil,
                                    bytesSaved: compressionResult.savings,
                                    originalBytes: compressionResult.originalSize,
                                    compressedBytes: compressionResult.compressedSize,
                                    timestamp: Date(), breakdown: nil, topSenders: nil
                                )
                            }
                        }
                    }
                    return 0
                },
                onPaywall: { _ in showPaywall = true }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in showPaywall = false }
                .onRestoreCompleted { _ in showPaywall = false }
        }
        .fullScreenCover(isPresented: Binding(
            get: { actionFlow.phase != .idle },
            set: { _ in }
        )) {
            ActionFlowContainer(coordinator: actionFlow, onDismiss: {})
        }
    }

}

// MARK: - Share Sheet
struct CompressShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Aspect-Fill Inline Video Player
//
// SwiftUI's `VideoPlayer` always letterboxes when the frame doesn't match
// the video's natural aspect — it wraps `AVPlayerViewController` and
// hides `videoGravity`. This thin UIView wrapper exposes an
// `AVPlayerLayer` directly so we can pin `videoGravity = .resizeAspectFill`,
// which scales the video to fill the frame and crops the over-axis. Same
// behavior the thumbnail uses (`.aspectRatio(contentMode: .fill)
// .clipped()`), so the preview reads as the same card whether it's
// showing the still or the live playback.
struct AspectFillVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Inline Video Player With Native Controls
//
// Wraps AVPlayerViewController so the compress detail screen ships with the
// full system playback chrome — play/pause, scrubber, fullscreen toggle,
// mute, AirPlay, PiP — instead of the previous custom tap-to-play overlay
// that hid every control behind a single tap. Mirrors what the Cleanup
// video flow uses (`ZoomablePlayerView` in `ZoomablePreviewOverlay.swift`).
struct CompressInlineVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        // Aspect fit so the scrubber + bottom chrome stay visible — fill
        // would crop the controls into the safe area on landscape clips.
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        // Don't auto-jump to fullscreen on play; the user can toggle it via
        // the native fullscreen icon when they want it. This keeps the
        // setup screen's compress controls visible alongside playback.
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - Full Screen Video Player
struct VideoPlayerFullScreen: View {
    let url: URL
    @Binding var isPresented: Bool
    @State var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            Button {
                player?.pause()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.top, 60)
            .padding(.leading, 20)
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#Preview {
    Text("CompressionDetailView requires PHAsset")
        .preferredColorScheme(.light)
}
