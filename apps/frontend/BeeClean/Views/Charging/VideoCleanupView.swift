import SwiftUI

// MARK: - Video Cleanup View
/// Detail page listing the 4 video cleanup categories.
/// Reached via the "Videos" tile in QUICK ACCESS on the dashboard.
struct VideoCleanupView: View {
    @Environment(SimilarPhotosStore.self) private var similarVM
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCleanup: CleanupDestination?

    var body: some View {
        VStack(spacing: 0) {
            categoryHeader

            ScrollView(showsIndicators: false) {
            let snap = similarVM.dashboardSnapshot
            VStack(spacing: 6) {
                IntelligentPreviewCard(
                    destination: .similarVideos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.similarVideos.tr,
                    accentColor: .categoryCrimson,
                    itemCount: snap.videoGroupCount,
                    storageBytes: snap.videoGroupBytes,
                    assetIds: snap.videoGroupPreviewIds,
                    isScanning: similarVM.isClusteringVideos || similarVM.isRunningFullScan || similarVM.isScanningSimilarVideos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .screenRecordings,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.screenRecordings.tr,
                    accentColor: .categoryIndigo,
                    itemCount: snap.screenRecordingCount,
                    storageBytes: snap.screenRecordingBytes,
                    assetIds: snap.screenRecordingPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningScreenRecordings,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .shortRecordings,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.shortRecordings.tr,
                    accentColor: .categoryMint,
                    itemCount: snap.shortVideoCount,
                    storageBytes: snap.shortVideoBytes,
                    assetIds: snap.shortVideoPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningShortVideos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .longVideos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.longVideos.tr,
                    accentColor: .categoryCocoa,
                    itemCount: snap.longVideoCount,
                    storageBytes: snap.longVideoBytes,
                    assetIds: snap.longVideoPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningLongVideos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 40)
            }
        }
        // Cool blue-lavender → warm light-gray gradient. Identical
        // stops to the Email / Settings / Compress glass backdrop so
        // every secondary tab shares one unified canvas.
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .hidesBottomNavBar()
        // Bulletproof hard-hide. `.onDisappear` is intentionally NOT
        // wired to clear the override — SwiftUI fires parent disappear
        // the moment any child is pushed (e.g. user taps Short
        // Recordings card), and clearing there would re-show the bar
        // for the entire push duration. ChargingView's
        // `onAppear → forceClear()` (which fires only when the user
        // pops back to the dashboard root) is the single canonical
        // clear point.
        .onAppear { BottomNavBarVisibility.shared.setForceHidden(true) }
        .navigationDestination(item: $selectedCleanup) { dest in
            // Every pushed destination ALSO carries `.hidesBottomNavBar()`
            // even though MediaGridView's body already calls it. The
            // redundancy guards a SwiftUI race we hit in production:
            // when the parent (VideoCleanupView) gets its `.task`
            // cancelled at push time, its hide release lands BEFORE
            // the child's hide request, briefly clearing the counter
            // to 0 — long enough for ChargingView.onAppear's safety
            // `forceClear()` to fire, leaving the bar permanently
            // visible. Stacking the modifier at the push site too
            // means the counter never reaches 0 mid-navigation.
            switch dest {
            case .duplicatePhotos: DuplicatePhotosView().hidesBottomNavBar()
            case .similarPhotos: SimilarPhotosView().hidesBottomNavBar()
            case .similarScreenshots: ScreenshotsView().hidesBottomNavBar()
            case .screenshots: MediaGridView(config: .screenshots(similarVM)).hidesBottomNavBar()
            case .blurryPhotos: MediaGridView(config: .blurryPhotos(similarVM)).hidesBottomNavBar()
            case .otherPhotos: MediaGridView(config: .otherPhotos(similarVM)).hidesBottomNavBar()
            case .similarVideos: SimilarVideosView().hidesBottomNavBar()
            case .screenRecordings: MediaGridView(config: .screenRecordings(similarVM)).hidesBottomNavBar()
            case .shortRecordings: MediaGridView(config: .shortRecordings(similarVM)).hidesBottomNavBar()
            case .longVideos: MediaGridView(config: .longVideos(similarVM)).hidesBottomNavBar()
            case .guidedCleanup: EmptyView()
            case .sourceFiltered(let source):
                MediaGridView(config: .sourceFiltered(similarVM, source: source)).hidesBottomNavBar()
            }
        }
    }

    // Email-style back-chevron + title header, identical to the one in
    // PhotoCleanupView / EmailCleanerHeader.
    private var categoryHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.foreground)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.card)
                            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    )
                    .overlay(
                        Circle().stroke(Color.foreground.opacity(0.06), lineWidth: 0.5)
                    )
            }
            .buttonStyle(ScaleButtonStyle())

            Text(BCLoc.videos.tr)
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(.foreground)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
