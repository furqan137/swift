import SwiftUI
import Photos

// MARK: - Pager Target
/// Identifiable wrapper so hosts can present the pager via
/// `.fullScreenCover(item:)`. Hosts build one of these when the user taps
/// a thumbnail; the pager opens positioned on that item.
struct PagerTarget: Identifiable, Equatable {
    let id = UUID()
    let groupId: UUID
    let startIndex: Int
}

// MARK: - Similar Detail Pager
/// Full-screen browser for a Similar / Duplicate / Screenshot / Video group.
///
/// Tinder swipe-to-mark/delete UX has been removed per user request:
/// browsing through the group's photos no longer commits any destructive
/// action by accident. Users swipe horizontally to flip between photos
/// (paged TabView, same gesture as Apple Photos), tap to zoom, and the
/// trash button in the top bar deletes the currently-viewed photo with the
/// system permission prompt.
struct SimilarDetailPagerView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    @Environment(\.dismiss) private var dismiss

    let groupId: UUID
    let source: GroupSource
    let startIndex: Int

    /// Selection bound to ASSET ID, not array index.
    ///
    /// Why: TabView previously bound to an Int index. When `items` mutated
    /// mid-browse — incremental clustering refines, a delete lands, the
    /// store re-sorts a group — the photo at index N changed identity, but
    /// TabView kept showing index N and animated the transition. From the
    /// user's perspective the page "auto-swiped" to a different photo
    /// without their input. That's the ghost-swipe bug.
    ///
    /// Binding to assetId pins the visible page to a specific photo. If
    /// the items array reorders, TabView finds the matching tag and stays
    /// on the same photo — no animation, no ghost swipe. If the photo is
    /// removed entirely, the `.onChange(of: items)` handler picks the
    /// nearest remaining asset.
    @State private var currentAssetId: String = ""
    @State private var isDeleting = false
    /// Tap-to-preview target. Setting this opens the ZoomablePreviewOverlay
    /// for the photo currently centered in the pager.
    @State private var previewAssetId: String?

    init(groupId: UUID, source: GroupSource, startIndex: Int = 0) {
        self.groupId = groupId
        self.source = source
        self.startIndex = startIndex
    }

    // MARK: - Derived State

    private var group: SimilarGroupVM? {
        let sourceGroups: [SimilarGroupVM]
        switch source {
        case .photos, .duplicates: sourceGroups = vm.groups
        case .screenshots: sourceGroups = vm.screenshotGroups
        case .videos: sourceGroups = vm.videoGroups
        }
        return sourceGroups.first { $0.id == groupId }
    }

    private var items: [SimilarGroupItem] {
        group?.items ?? []
    }

    private var currentItem: SimilarGroupItem? {
        items.first { $0.assetId == currentAssetId }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.assetId == currentAssetId } ?? 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Cool blue-lavender → warm light-gray gradient — same
            // stops every other secondary surface uses (Email,
            // Settings, Compress, Progress, More, Photos, Videos).
            // Replaces the cream `Color.surfaceLight` so the media
            // pager sits on the unified BitePal canvas.
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

            if items.isEmpty {
                emptyState
            } else {
                pager
                    .padding(.top, 90)
                    .padding(.bottom, 40)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: false)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
        // Resolve the user's tapped startIndex → assetId on first appear.
        // After this, the pager is purely assetId-driven and won't drift
        // when the underlying items array mutates.
        .task {
            if currentAssetId.isEmpty {
                if startIndex >= 0, startIndex < items.count {
                    currentAssetId = items[startIndex].assetId
                } else {
                    currentAssetId = items.first?.assetId ?? ""
                }
            }
        }
        .onChange(of: items.map(\.assetId)) { oldIds, newIds in
            // Items mutated (delete landed, cluster refined). If the
            // current asset is gone, pick the nearest neighbor; if the
            // group is empty, dismiss. Crucially, if the asset is STILL
            // present, do NOTHING — TabView keeps showing it because
            // selection is by assetId, not index.
            if newIds.isEmpty {
                dismiss()
                return
            }
            if !newIds.contains(currentAssetId) {
                let oldPos = oldIds.firstIndex(of: currentAssetId) ?? 0
                let snapped = min(oldPos, newIds.count - 1)
                currentAssetId = newIds[max(0, snapped)]
            }
        }
        .fullScreenCover(item: Binding(
            get: { previewAssetId.map(PreviewTarget.init(assetId:)) },
            set: { previewAssetId = $0?.assetId }
        )) { target in
            ZoomablePreviewOverlay(
                assetIdentifier: target.assetId,
                saveContext: saveContextForSource
            ) {
                previewAssetId = nil
            }
        }
    }

    // Each grouped category maps 1:1 to a SavedFinds source category.
    // Saving from inside the pager bookmarks the asset with the category
    // it was reviewed in.
    private var saveContextForSource: SavedFindContext {
        switch source {
        case .duplicates:  return SavedFindContext(mediaType: .photo, sourceCategory: .duplicates)
        case .photos:      return SavedFindContext(mediaType: .photo, sourceCategory: .similarPhotos)
        case .screenshots: return SavedFindContext(mediaType: .photo, sourceCategory: .similarScreenshots)
        case .videos:      return SavedFindContext(mediaType: .video, sourceCategory: .similarVideos)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            chipButton(systemImage: "xmark") {
                BottomNavBarVisibility.shared.releaseHide()
                dismiss()
            }
            Spacer()
            pageIndicator
            Spacer()
            trashChip
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            Text("\(min(currentIndex + 1, items.count))")
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(Color(hex: "1C1917"))
            Text("/")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "A8A29E"))
            Text("\(items.count)")
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(Color(hex: "1C1917"))
        }
    }

    private var trashChip: some View {
        Button {
            Task { await deleteCurrentImmediate() }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(hex: "DC2626")))
        }
        .buttonStyle(.plain)
        .disabled(isDeleting || currentItem == nil)
        .opacity(isDeleting ? 0.4 : 1)
    }

    private func chipButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(hex: "1C1917"))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(hex: "EEEDF3")))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pager
    //
    // Apple-Photos-style horizontal page view. Each page is a single photo
    // (or video poster) inside the group. Swipe horizontally to navigate;
    // tap to open the zoomable preview. No drag-to-delete: the only delete
    // path is the trash button in the top bar, which deletes the photo at
    // `currentIndex` and triggers the iOS system confirmation prompt.
    private var pager: some View {
        // Selection by assetId — TabView pins to the user's currently
        // visible photo regardless of how items reorder underneath. The
        // `.tag` on each page MUST match the type of the selection
        // binding (String here), or TabView silently falls back to its
        // own internal page-index selection and reintroduces the ghost-
        // swipe bug we just fixed.
        TabView(selection: $currentAssetId) {
            ForEach(items, id: \.assetId) { item in
                PhotoPage(
                    item: item,
                    onTap: { previewAssetId = item.assetId },
                    onUnloadable: { vm.pruneUnloadableAsset(item.assetId) }
                )
                .tag(item.assetId)
                .padding(.horizontal, 20)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color(hex: "C8C7CD"))
            Text("No items left in this group")
                .font(.custom("Poppins-Bold", size: 15))
                .foregroundColor(Color(hex: "78716C"))
        }
    }

    // MARK: - Deletion

    private func deleteCurrentImmediate() async {
        guard let item = currentItem else { return }
        isDeleting = true
        let ok: Bool
        switch source {
        case .photos, .duplicates:
            ok = await vm.deletePhotoSingle(assetId: item.assetId)
        case .screenshots:
            ok = await vm.deleteScreenshotSingle(assetId: item.assetId)
        case .videos:
            ok = await vm.deleteVideoSingle(assetId: item.assetId)
        }
        isDeleting = false
        // onChange(of: items.count) handles dismiss / index clamp when the
        // delete actually lands and the group shrinks.
        _ = ok
    }
}

// MARK: - Photo Page
//
// A single page in the horizontal pager. Just the photo, tap to zoom. No
// drag gesture, no swipe-to-mark — replaced the previous SwipeCard.
private struct PhotoPage: View {
    let item: SimilarGroupItem
    let onTap: () -> Void
    var onUnloadable: (() -> Void)? = nil

    var body: some View {
        ZStack {
            GeometryReader { geo in
                PhotoThumbnailView(
                    assetIdentifier: item.assetId,
                    size: CGSize(width: geo.size.width * 2, height: geo.size.height * 2),
                    contentMode: .fit,
                    onUnloadable: { onUnloadable?() }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture { onTap() }
            }

            if item.isBest {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(BCLoc.best.tr)
                                .font(.custom("Poppins-Bold", size: 12))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.9)))
                        .padding(14)
                    }
                    Spacer()
                }
            }
        }
    }
}

// `formatBytes(_:)` is declared at module scope in VideoAsset.swift and
// is accessible from this file. The file-private copy that used to live
// here has been removed to eliminate a name collision — `private` at file
// scope still collides with a matching internal declaration elsewhere in
// the module when both are visible at the call site.
