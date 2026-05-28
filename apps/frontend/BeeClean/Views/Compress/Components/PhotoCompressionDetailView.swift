import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Photo Compression Detail View
struct PhotoCompressionDetailView: View {
    let photo: PhotoAsset
    @StateObject var engine = CompressionEngine()
    @State var selectedLevel: CompressionLevel = .medium
    @State var thumbnail: UIImage?
    @State var showSaveSuccess = false
    @State var showSaveError = false
    @State var saveErrorMessage = ""
    @State var showDeleteConfirm = false
    @State var showDeleteOnlyConfirm = false
    @State var originalDeleted = false
    /// True while the user is inspecting the photo full-screen via the
    /// shared `ZoomablePreviewOverlay` (pinch + double-tap zoom, drag to
    /// pan, tap to dismiss). Mirrors how Apple's Photos app behaves when
    /// you tap a thumbnail — full-resolution image loaded from
    /// `PHImageManagerMaximumSize` so the user can inspect detail before
    /// deciding whether to compress.
    @State var showFullScreenPreview = false
    @State var showCompressGate = false
    @State var showPaywall = false
    /// Stashed result URL for the gate callback to use after approval.
    @State var pendingSaveURL: URL?
    @StateObject var actionFlow = ActionFlowCoordinator()
    @Environment(\.dismiss) var dismiss

    // Result animation states — honey-celebration choreography
    @State var heroCardOffset: CGFloat = 60
    @State var heroCardOpacity: Double = 0
    @State var percentDisplay: Int = 0
    @State var beeBob: CGFloat = 0
    @State var beforeAfterOpacity: Double = 0
    @State var resultActionsOffset: CGFloat = 40
    @State var resultActionsOpacity: Double = 0

    var activeProgress: Float { engine.progress }
    var activePhase: CompressionPhase { engine.phase }
    var activeIsCompressing: Bool { engine.isCompressing }
    var activeResult: CompressionResult? { engine.result }

    var estimatedSize: Int64 {
        selectedLevel.estimatedPhotoSize(
            from: photo.fileSize,
            resolution: photo.resolution,
            sourceFormat: photo.format
        )
    }

    var estimatedSavings: Int64 {
        selectedLevel.estimatedPhotoSavings(
            from: photo.fileSize,
            resolution: photo.resolution,
            sourceFormat: photo.format
        )
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
            .alert("Replace Original?", isPresented: $showDeleteConfirm) {
                Button("Replace", role: .destructive) {
                    if let asset = photo.asset {
                        Task { await runDelete(asset: asset, dismissOnSuccess: false) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The original \(formatBytes(photo.fileSize)) photo will be moved to Recently Deleted.")
            }
            .alert("Delete Photo?", isPresented: $showDeleteOnlyConfirm) {
                Button("Delete", role: .destructive) {
                    if let asset = photo.asset {
                        Task { await runDelete(asset: asset, dismissOnSuccess: true) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This \(formatBytes(photo.fileSize)) photo will be moved to Recently Deleted.")
            }
            .overlay {
                if showSaveSuccess {
                    saveSuccessBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if showSaveError {
                    saveErrorBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .hidesBottomNavBar()
        // Full-screen photo viewer — same shared component the swipe
        // decks use, so tap-to-inspect feels identical everywhere in
        // the app. Loads at `PHImageManagerMaximumSize` so pinch-zoom
        // reveals real pixel detail instead of a re-blown-up preview.
        .fullScreenCover(isPresented: $showFullScreenPreview) {
            ZoomablePreviewOverlay(
                assetIdentifier: photo.id,
                onDismiss: { showFullScreenPreview = false }
            )
        }
        .sheet(isPresented: $showCompressGate) {
            GateCoordinator(
                config: .config(for: .compress),
                selectedCount: 1,
                onActionApproved: { _ in
                    if let url = pendingSaveURL, let compressionResult = engine.result {
                        Task {
                            await actionFlow.execute(section: .compress, actionType: .compress, itemCount: 1) {
                                let saved = await engine.savePhotoToPhotoLibrary(url: url)
                                guard saved else { throw NSError(domain: "CompressionSave", code: -1) }
                                await MainActor.run {
                                    HiveStatsManager.shared.recordCleanup(
                                        action: "compression",
                                        itemCount: 1,
                                        bytesSaved: Int64(compressionResult.savings),
                                        category: .photoCompression
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

// MARK: - Speech Bubble Tail
//
// Tiny isoceles triangle pointing down — used as the speech-bubble tail so
// the bubble reads as something the bee just said. Kept as a shared shape
// here (not in DesignTokens) because the tail is tightly coupled to this
// view's bubble proportions and isn't reused anywhere else.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        path.closeSubpath()
        return path
    }
}

#Preview {
    Text("PhotoCompressionDetailView requires PHAsset")
        .preferredColorScheme(.light)
}
