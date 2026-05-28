import SwiftUI
import AVKit

// MARK: - Secret Library View (Unlocked State)
struct SecretLibraryView: View {
    @Binding var showChangePIN: Bool
    let onLock: () -> Void

    @StateObject var vault = SecretVaultManager.shared
    @State var showMediaPicker = false
    @State var showCamera = false
    @State var selectedItems: Set<String> = []
    @State var isSelecting = false
    @State var showDeleteConfirm = false
    @State var importCount = 0
    @State var showImportToast = false
    @State var appeared = false
    @State var assetIdsToDelete: [String] = []
    /// Tap-to-view target. Setting this opens a fullscreen preview of the
    /// vault item (photo or video playback). Cleared via the dismiss X.
    @State var previewItem: VaultMediaItem?
    @State var showDeleteFromCameraRoll = false
    @State var showAddSheet = false
    @State var showShareSheet = false
    @State var shareItems: [Any] = []

    // Lock flow states
    @State var showLockFlow = false
    @State var lockStep = 0          // 0 = create, 1 = confirm, 2 = locked
    @State var lockPIN = ""
    @State var lockPINCandidate = ""
    @State var lockPINError = false
    @State var lockShake: CGFloat = 0

    @AppStorage("secretPIN") var savedPIN = ""
    @AppStorage("hasCreatedPIN") var hasCreatedPIN = false


    var body: some View {
        VStack(spacing: 0) {
            headerBar


            if vault.items.isEmpty {
                emptyState
            } else {
                mediaGrid
            }

            Spacer(minLength: 0)
            bottomBar
        }
        // Shared BitePal canvas — cool blue-lavender gradient used
        // by every secondary surface.
        .background(
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
        )
        .sheet(isPresented: $showMediaPicker) {
            SecretMediaPicker(
                onPickedPhotos: { images in
                    importCount = 0
                    for image in images {
                        vault.addPhoto(image)
                        importCount += 1
                    }
                    showImportToast = true
                    hideToastAfterDelay()
                },
                onPickedVideos: { urls in
                    for url in urls {
                        vault.addVideo(from: url)
                        importCount += 1
                    }
                    showImportToast = true
                    hideToastAfterDelay()
                },
                onAssetIdentifiers: { identifiers in
                    assetIdsToDelete = identifiers
                    showDeleteFromCameraRoll = true
                }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            SecretCameraCapture(
                onCapturedPhoto: { image in
                    vault.addPhoto(image)
                    importCount = 1
                    showImportToast = true
                    hideToastAfterDelay()
                },
                onCapturedVideo: { url in
                    vault.addVideo(from: url)
                    importCount = 1
                    showImportToast = true
                    hideToastAfterDelay()
                }
            )
            .ignoresSafeArea()
        }
        .alert("Delete \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                vault.deleteItems(selectedItems)
                selectedItems.removeAll()
                isSelecting = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Delete originals?", isPresented: $showDeleteFromCameraRoll) {
            Button("Keep Originals", role: .cancel) {
                assetIdsToDelete = []
            }
            Button("Delete", role: .destructive) {
                let ids = assetIdsToDelete
                assetIdsToDelete = []
                Task {
                    await vault.deleteFromCameraRoll(assetIdentifiers: ids)
                }
            }
        } message: {
            Text("Remove \(assetIdsToDelete.count) imported item\(assetIdsToDelete.count == 1 ? "" : "s") from your camera roll? They're safely stored in your vault.")
        }
        .overlay {
            if showAddSheet {
                // Full-screen blur backdrop — softer scrim for the light Bitepal sheet
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.25)) { showAddSheet = false }
                    }
                    .transition(.opacity)

                // Bottom sheet
                VStack {
                    Spacer()
                    addActionSheet
                        .background(addSheetShell)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showAddSheet)
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
                    .presentationDetents([.medium, .large])
            }
        }
        .overlay(alignment: .top) {
            if showImportToast {
                importToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showImportToast)
        .fullScreenCover(isPresented: $showLockFlow) {
            lockFlowView
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.light)
                .onAppear {
                    // Ensure correct step when cover appears
                    if hasCreatedPIN && !savedPIN.isEmpty && lockStep == 0 {
                        lockStep = 10
                    }
                }
        }
        .fullScreenCover(item: $previewItem) { item in
            VaultPreviewView(item: item) {
                previewItem = nil
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
    }

}

// MARK: - Vault Preview View
//
// Fullscreen preview for a vault item — pinch-to-zoom for photos, native
// AVPlayer for videos. Mirrors the in-pager preview UX used elsewhere in
// the app so opening a Secret Space tile feels consistent with opening a
// duplicate / similar / blurry photo.
struct VaultPreviewView: View {
    let item: VaultMediaItem
    let onClose: () -> Void

    @StateObject var vault = SecretVaultManager.shared
    @State var image: UIImage?
    @State var player: AVPlayer?
    @State var scale: CGFloat = 1
    @State var lastScale: CGFloat = 1
    @State var offset: CGSize = .zero
    @State var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 14)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
        .task {
            await loadContent()
        }
        .onDisappear {
            player?.pause()
        }
    }

    @ViewBuilder
    var content: some View {
        if item.isVideo {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        } else if let image {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(lastScale * value, 6))
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                        scale = 1
                                        lastScale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .gesture(
                        TapGesture(count: 2).onEnded {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                if scale > 1 {
                                    scale = 1; lastScale = 1
                                    offset = .zero; lastOffset = .zero
                                } else {
                                    scale = 2.5; lastScale = 2.5
                                }
                            }
                        }
                    )
            }
        } else {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        }
    }

    func loadContent() async {
        if item.isVideo {
            await MainActor.run {
                player = AVPlayer(url: vault.fileURL(for: item))
            }
        } else {
            // Load full image off main since SecretVaultManager is
            // @MainActor but the file methods are nonisolated. Capturing
            // `vault` in the closure capture list (vs. reading it inside
            // the Task body) keeps the read on main where it belongs;
            // only the captured reference travels into the detached task,
            // which then invokes the nonisolated `loadFullImage` safely.
            let v = vault
            let img = await Task.detached(priority: .userInitiated) {
                v.loadFullImage(for: item)
            }.value
            await MainActor.run { self.image = img }
        }
    }
}
