import SwiftUI

// MARK: - Photo Cleanup View
/// Detail page listing the 6 photo cleanup categories.
/// Reached via the "Photos" tile in QUICK ACCESS on the dashboard.
struct PhotoCleanupView: View {
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
                    destination: .duplicatePhotos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.duplicates.tr,
                    accentColor: .categorySky,
                    itemCount: snap.duplicateGroupCount,
                    storageBytes: snap.duplicateBytes,
                    assetIds: snap.duplicatePreviewIds,
                    isScanning: similarVM.isClusteringPhotos || similarVM.isRunningFullScan || similarVM.isScanningSimilarPhotos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .similarPhotos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.similarPhotos.tr,
                    accentColor: .categoryViolet,
                    itemCount: snap.similarGroupCount,
                    storageBytes: snap.similarBytes,
                    assetIds: snap.similarPreviewIds,
                    isScanning: similarVM.isClusteringPhotos || similarVM.isRunningFullScan || similarVM.isScanningSimilarPhotos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .similarScreenshots,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.similarScreenshots.tr,
                    accentColor: .categoryTeal,
                    itemCount: snap.screenshotGroupCount,
                    storageBytes: snap.screenshotGroupBytes,
                    assetIds: snap.screenshotGroupPreviewIds,
                    isScanning: similarVM.isClusteringScreenshots || similarVM.isRunningFullScan || similarVM.isScanningScreenshots,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .screenshots,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.screenshots.tr,
                    accentColor: .categoryAmber,
                    itemCount: snap.ungroupedScreenshotCount,
                    storageBytes: snap.ungroupedScreenshotBytes,
                    assetIds: snap.ungroupedScreenshotPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningScreenshots,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .blurryPhotos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.blurredPhotos.tr,
                    accentColor: .categoryRose,
                    itemCount: snap.blurryCount,
                    storageBytes: snap.blurryBytes,
                    assetIds: snap.blurryPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningSimilarPhotos,
                    scanComplete: similarVM.progress.isComplete,
                    onAssetUnloadable: { similarVM.pruneUnloadableAsset($0) }
                )

                IntelligentPreviewCard(
                    destination: .otherPhotos,
                    selectedDestination: $selectedCleanup,
                    title: BCLoc.otherPhotos.tr,
                    accentColor: .categorySlate,
                    itemCount: snap.ungroupedPhotoCount,
                    storageBytes: snap.ungroupedPhotoBytes,
                    assetIds: snap.ungroupedPhotoPreviewIds,
                    isScanning: similarVM.isRunningFullScan || similarVM.isScanningSimilarPhotos,
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
        // Bulletproof hard-hide. CRITICAL: we set the override on
        // `.onAppear` but DO NOT clear it on `.onDisappear`. Reason:
        // SwiftUI fires `.onDisappear` on a parent the moment any
        // child is pushed onto the stack (e.g. user taps the Other
        // Photos card and MediaGridView pushes). A disappear-side
        // release would re-show the bar over the child view for the
        // entire push duration. The override is cleared exclusively
        // by ChargingView's `onAppear → forceClear()` which fires
        // only when the user actually returns to the dashboard root
        // — that's the canonical "leave the Quick Access stack"
        // signal.
        .onAppear { BottomNavBarVisibility.shared.setForceHidden(true) }
        .navigationDestination(item: $selectedCleanup) { dest in
            // Every pushed destination ALSO carries `.hidesBottomNavBar()`
            // even though MediaGridView's body already calls it. The
            // redundancy guards a SwiftUI race in production: when the
            // parent (PhotoCleanupView) gets its `.task` cancelled at
            // push time, its hide release lands BEFORE the child's
            // hide request, briefly clearing the counter to 0 — long
            // enough for ChargingView.onAppear's safety `forceClear()`
            // to fire, leaving the bar visible. Stacking the modifier
            // at the push site means the counter never reaches 0
            // mid-navigation.
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

    // Email-style back-chevron + title header. Same spec as
    // EmailCleanerHeader so the Photos/Videos/Email/Compress detail
    // pages share one navigation chrome.
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

            Text(BCLoc.photos.tr)
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(.foreground)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
