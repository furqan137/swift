import SwiftUI
import AVKit

// MARK: - Full Screen Media Viewer
struct SecretMediaViewer: View {
    let item: VaultMediaItem
    @StateObject private var vault = SecretVaultManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var showDeleteConfirm = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color(hex: "F2F2F7").ignoresSafeArea()

            if item.isVideo {
                VideoPlayerView(url: vault.fileURL(for: item))
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .onTapGesture(count: 1) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
            } else {
                ProgressView()
                    .tint(Color(hex: "A1A1AA"))
            }

            // Controls overlay
            if showControls {
                VStack {
                    // Top bar - back chevron only
                    HStack {
                        Button {
                            HapticManager.shared.arrowNudge(.backward)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "1C1917"))
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Circle()
                                                .fill(Color.white.opacity(0.85))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                                        )
                                )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    // Bottom bar - thumbnail + Share + Delete
                    HStack(spacing: 16) {
                        // Thumbnail
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                                )
                        } else if item.isVideo {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "A1A1AA").opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "A1A1AA"))
                                )
                        }

                        Spacer()

                        // Share button
                        Button {
                            shareCurrentMedia()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .medium))
                                Text(BCLoc.share.tr)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }

                        // Delete button
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                Text(BCLoc.delete.tr)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.85))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .task {
            if !item.isVideo {
                image = vault.loadFullImage(for: item)
            }
        }
        .alert("Delete this \(item.isVideo ? "video" : "photo")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                vault.deleteItem(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Share
    private func shareCurrentMedia() {
        var items: [Any] = []
        if item.isVideo {
            let url = vault.fileURL(for: item)
            items = [url]
        } else if let image = image {
            items = [image]
        }
        guard !items.isEmpty else { return }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            activityVC.popoverPresentationController?.sourceView = topVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 50, width: 0, height: 0)
            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Video Player View
//
// Crash history: a previous version held an `AVPlayer?` and nilled it in
// onDisappear. SwiftUI can call body once more during the dismiss
// transition, which dereferenced the just-zeroed player and tore the app
// down. Plus there was no error-handling on AVPlayerItem.status.failed —
// a corrupt or partially-written vault file produced a hard crash from
// AVFoundation rather than a recoverable error message.
//
// Fix:
//   • Allocate the AVPlayer eagerly with a single stable item and never
//     nil it (just pause on disappear). SwiftUI keeps a valid pointer
//     for the entire view lifetime.
//   • Configure the AVAudioSession so playback doesn't fight whichever
//     audio route the app currently holds.
//   • Listen for AVPlayerItem.statusDidChange and surface "Can't play
//     this video" instead of crashing on a bad file.
struct VideoPlayerView: View {
    let url: URL
    @StateObject private var controller = VaultVideoController()

    var body: some View {
        ZStack {
            if controller.didFail {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "A1A1AA"))
                    Text("Can't play this video")
                        .font(.custom("Poppins-Bold", size: 16))
                        .foregroundColor(Color(hex: "1C1917"))
                }
                .padding(24)
            } else {
                VideoPlayer(player: controller.player)
                    .ignoresSafeArea()
            }
        }
        .onAppear { controller.start(url: url) }
        .onDisappear { controller.teardown() }
    }
}

@MainActor
final class VaultVideoController: ObservableObject {
    let player = AVPlayer()
    @Published var didFail = false

    private var statusObserver: NSKeyValueObservation?
    private var didConfigureAudio = false

    func start(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            didFail = true
            return
        }

        if !didConfigureAudio {
            // Allow playback while other audio is muted; iOS otherwise
            // routes vault video through the silent ringer category and a
            // few decoder paths assert.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
            didConfigureAudio = true
        }

        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed { self.didFail = true }
            }
        }
        didFail = false
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func teardown() {
        player.pause()
        statusObserver?.invalidate()
        statusObserver = nil
        // Intentionally do NOT replaceCurrentItem(with: nil) here — SwiftUI
        // can still hold a presentation reference during the dismiss
        // animation and zeroing the item from underneath it crashes.
    }

    deinit {
        statusObserver?.invalidate()
    }
}
