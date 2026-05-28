import SwiftUI


// MARK: - Month Swipe Payload
//
// Identifiable wrapper for `[ScreenshotAsset]` so it can drive a
// `.fullScreenCover(item:)`. Equatable on items.count alone — opening the
// same month back-to-back shouldn't tear the cover down and rebuild it.
private struct MonthSwipePayload: Identifiable, Equatable {
    let items: [ScreenshotAsset]
    var id: Int { items.count == 0 ? 0 : items[0].assetId.hashValue ^ items.count }
    static func == (lhs: MonthSwipePayload, rhs: MonthSwipePayload) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Social Source Badge
//
// Small circular overlay placed in the top-right of any photo/video tile
// (detail grid, swipe deck, group cards) to show which app saved the
// asset. Renders nothing for `nil` (detection hasn't run yet) or
// `.camera` (user's own capture) — vanilla camera shots stay uncluttered.
//
// Inlined here instead of a standalone Views/Components/SocialSourceBadge.swift
// because the Xcode project is hand-tracked (same rationale as the
// PhotoSource enum's inlining in SimilarModels.swift).
struct SocialSourceBadge: View {
    let source: PhotoSource?
    var size: CGFloat = 22

    var body: some View {
        if let source, source.isExternal {
            ZStack {
                Circle()
                    .fill(source.brandColor)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

                Text(source.monogram)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(source.monogramColor)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("From \(source.displayName)")
        }
    }
}

// MARK: - Media Grid View

struct MediaGridView: View {
    let config: MediaGridConfig

    @Environment(SimilarPhotosStore.self) var store
    @State var showSwipeView = false
    @State var selectedIndex = 0
    @State var isSelecting = false
    @State var selectedIds: Set<String> = []
    @State var showDeleteConfirm = false
    @State var showErrorAlert = false
    /// Tap-to-zoom target for a single photo. Tapping a tile opens the
    /// zoomable preview instead of immediately launching swipe-mode — the
    /// user must explicitly press "Swipe" in the header to enter that flow.
    @State var previewAssetId: String?

    /// Cached month-section bucketing for `useMonthGrouping` photo
    /// categories (Blurry / Screenshots / Other Photos). Recomputed only
    /// when the underlying `items` array's count changes via the
    /// `.task(id:)` modifier on `groupedSectionsContent`. Without the
    /// cache, every body invalidation (selection toggle, scroll
    /// preference change, etc.) was re-running the calendar
    /// dateComponents loop over the full library — 5–20ms per render
    /// for a 3k-photo Other Photos list.
    @State var cachedMonthSections: [MonthSection] = []

    /// Items for the currently-active month-scoped swipe deck. Non-nil
    /// drives a fullScreenCover that opens MediaSwipeView restricted to
    /// just that month — letting users tackle a backlog one month at a
    /// time instead of swiping through 6,000 photos in one sitting.
    @State var monthSwipeItems: [ScreenshotAsset]? = nil

    @Environment(\.dismiss) var dismiss

    /// Cached source list — refreshed exclusively by `refreshItems()`,
    /// which fires on initial appear and after every store-side delete.
    /// Used to be a computed property reading `config.items()` on each
    /// access. That call walks `store.ungroupedPhotos` / `blurryPhotos`
    /// (filter + sort + map over `analyzedIndex.values`, ~4500 entries)
    /// and the property was read 5+ times per body render: by the
    /// `items.isEmpty` empty-check, the stats header, `selectedBytes`,
    /// the grid `ForEach`, and the `.onChange(of: items.map(\.assetId))`
    /// modifier that allocated a fresh string array every render even
    /// when nothing changed. Caching as @State turns each subsequent
    /// read into an array indirection.
    @State var items: [ScreenshotAsset] = []

    /// Sort + date-range filter state, mirroring the SimilarPhotosView
    /// pattern. `items` is replaced wholesale by `refreshItems()` with
    /// the sorted+filtered result so the grid, month sections, stats
    /// pill, and selection helpers all read from a single source of
    /// truth.
    @State var sortOption: SimilarSortOption = .newest
    @State var startDate: Date?
    @State var endDate: Date?
    @State var showFilters = false

    /// Side index `assetId → fileSize`. Lets `selectedBytes` skip the
    /// full-list `.filter().reduce()` walk and look up only the bytes
    /// of the currently-selected ids — O(selectedIds.count) instead of
    /// O(items.count) per body invalidation. With 3000+ Other Photos
    /// and a multi-select session, the difference is real.
    @State var fileSizeById: [String: Int64] = [:]

    var selectedBytes: Int64 {
        selectedIds.reduce(Int64(0)) { $0 + (fileSizeById[$1] ?? 0) }
    }

    /// Rebuilds `items` and `fileSizeById` from the live store. Called
    /// on first appear and whenever `store.isDeleting` flips false (the
    /// signal that a user-initiated delete has finished and the source
    /// list has shrunk). The body itself never triggers a refresh, so
    /// scrolling / selection / sheet presentation costs the cache
    /// nothing.
    func refreshItems() {
        let fresh = applyFilters(to: config.items())
        items = fresh
        fileSizeById = Dictionary(uniqueKeysWithValues: fresh.map { ($0.assetId, $0.fileSize) })
        // Drop any selectedIds that aren't in the freshly-fetched list
        // (e.g. an asset deleted under us). Replaces the per-render
        // `.onChange(of: items.map(\.assetId))` modifier that allocated
        // a string-array map on every body invalidation.
        let visible = Set(fresh.map(\.assetId))
        selectedIds.formIntersection(visible)
    }

    /// Applies the active sort + optional date range to a flat list of
    /// `ScreenshotAsset`. Mirrors `[SimilarGroupVM].applySimilarFilters`
    /// from the grouped flow so the user gets identical filter
    /// semantics on either side. Items missing a `creationDate` survive
    /// every filter (they simply can't be date-ranged or date-sorted)
    /// so the grid never silently drops them.
    func applyFilters(to source: [ScreenshotAsset]) -> [ScreenshotAsset] {
        let filtered = source.filter { asset in
            guard let date = asset.creationDate else { return true }
            if let start = startDate, date < start { return false }
            if let end = endDate, date > end { return false }
            return true
        }
        switch sortOption {
        case .newest:
            return filtered.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        case .oldest:
            return filtered.sorted {
                ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        case .largest:
            return filtered.sorted { $0.fileSize > $1.fileSize }
        }
    }

    // Photo categories stay at 3 columns — high-volume tiles (3000+ photos
    // in Other Photos) need the density. Video categories drop to 2
    // columns so each clip's thumbnail + storage pill is large enough to
    // scan at a glance, matching the Cleanup-screen card sizing.
    var columns: [GridItem] {
        let spacing: CGFloat = 8
        if config.showVideoBadge {
            return [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]
        }
        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Shared BitePal canvas — cool blue-lavender gradient
            // used by every secondary surface. Matches the grouped
            // category screens (Similar/Duplicate/Screenshot/Video)
            // so navigating from a grouped card into a flat one
            // (Screenshots, Blurred, Other, Screen Recordings,
            // Short, Long) keeps the same canvas.
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

            VStack(spacing: 0) {
                // Photo categories (Screenshots / Blurred / Other Photos)
                // and video categories (Screen Recordings / Short / Long)
                // share the collapsing-style chrome — back + Select toggle
                // on the top row, big title + sort filter below. The two
                // headers differ only in their right-side action: photos
                // get an explicit Select/Cancel toggle, videos get an
                // always-on Select All pill (selection is implicit there,
                // matching the Cleanup-style review screens).
                if config.showsSwipe {
                    header
                } else {
                    collapsingStyleHeader
                }

                if items.isEmpty {
                    emptyState
                } else {
                    if config.useMonthGrouping {
                        groupedSectionsContent
                    } else {
                        gridContent
                    }
                }
            }

            // Footer slot — delete progress OR action bar. Spring
            // animations are scoped to THIS Group only, not the whole
            // ZStack, so the parent grid + header don't re-animate
            // every time `selectedIds` mutates (every tap during
            // multi-select). Previously a list-wide
            // `.animation(.spring(...), value: selectedIds)` on the
            // ZStack made every cell + header subview reconsider its
            // animation graph on every selection toggle — visible
            // jank on a 3000-cell grid. Now only the footer
            // transitions in / out.
            Group {
                if store.isDeleting {
                    deleteProgressBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !selectedIds.isEmpty && (isSelecting || !config.showsSwipe) {
                    // Video categories surface the delete bar the moment any
                    // tile is selected (no explicit Select-mode gate), matching
                    // the Similar Videos / Cleanup interaction model.
                    ActionBar(
                        title: "Delete \(selectedIds.count) \(config.countLabel.lowercased()) (\(formatBytes(selectedBytes)))",
                        buttonTitle: "Delete",
                        buttonIcon: "trash.fill",
                        isDestructive: true
                    ) {
                        showDeleteConfirm = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIds.isEmpty)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.isDeleting)
        }
        .navigationBarBackButtonHidden(true)
        .hidesBottomNavBar()
        .fullScreenCover(isPresented: $showSwipeView) {
            config.makeSwipeView(selectedIndex)
        }
        // Month-scoped swipe — fired from the "Swipe Month" pill in
        // monthSectionRow. Uses the optional `makeSwipeViewForItems`
        // factory; when the category doesn't define it, the pill is
        // hidden so this branch never opens.
        .fullScreenCover(item: Binding<MonthSwipePayload?>(
            get: { monthSwipeItems.map(MonthSwipePayload.init(items:)) },
            set: { monthSwipeItems = $0?.items }
        )) { payload in
            if let factory = config.makeSwipeViewForItems {
                factory(payload.items)
            }
        }
        // Single-photo zoomable preview triggered by tapping a tile (not
        // selection mode). Mirrors the in-pager preview used by the
        // grouped-category screens — same overlay, same dismiss UX.
        //
        // Save-context enrichment: the per-tile asset's `sourceApp` (if
        // any) overrides whatever the config supplied so previews opened
        // from generic categories (Other Photos, Blurry, …) still tag
        // the save with app provenance. Source-filtered cards already
        // bake their source into config.saveContext as a default.
        .fullScreenCover(item: Binding(
            get: { previewAssetId.map(PreviewTarget.init(assetId:)) },
            set: { previewAssetId = $0?.assetId }
        )) { target in
            ZoomablePreviewOverlay(
                assetIdentifier: target.assetId,
                saveContext: enrichedSaveContext(forAssetId: target.assetId)
            ) {
                previewAssetId = nil
            }
        }
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.notify(.warning) }
        }
        .alert("Delete \(selectedIds.count) \(config.countLabel.lowercased())?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text("This will permanently delete \(selectedIds.count) \(config.countLabel.lowercased()) and free up \(formatBytes(selectedBytes)). Items land in Recently Deleted for 30 days.")
        }
        .alert("Delete failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some items could not be deleted. Please try again.")
        }
        // Clear selection if the user toggles out of select mode.
        // Also fires `filterChange()` on every flip so the tactile
        // tick lands at the same moment as the visual mode change.
        .onChange(of: isSelecting) { _, selecting in
            HapticManager.shared.filterChange()
            if !selecting { selectedIds.removeAll() }
        }
        // Initial fetch — `items` and `fileSizeById` start empty and get
        // populated on first appear. Source list also refreshes when the
        // user finishes a delete (covered by the `store.isDeleting`
        // observer below), or when an upstream scan flushes a new batch
        // (covered by `store.scanSummary.lastScanDate`).
        .task {
            refreshItems()
        }
        .onChange(of: store.isDeleting) { wasDeleting, isDeleting in
            // Fires on the trailing edge of every delete pass: refreshes
            // `items` against the now-shrunk source list AND prunes
            // `selectedIds` of asset ids that vanished. Replaces the
            // per-body `.onChange(of: items.map(\.assetId))` allocation.
            if wasDeleting && !isDeleting { refreshItems() }
        }
        .onChange(of: store.scanSummary.lastScanDate) { _, _ in
            // A fresh scan may surface or remove items in this category
            // even while the user is parked on this screen — refresh so
            // the list stays in sync with the on-device algorithm.
            refreshItems()
        }
        // Re-sort/filter whenever any filter input changes. Cheap —
        // refreshItems() pulls from `config.items()` (already cached
        // upstream) and applies the new sort in-place.
        .onChange(of: sortOption) { _, _ in refreshItems() }
        .onChange(of: startDate) { _, _ in refreshItems() }
        .onChange(of: endDate) { _, _ in refreshItems() }
        .blur(radius: showFilters ? 8 : 0)
        .animation(.easeOut(duration: 0.2), value: showFilters)
        .sheet(isPresented: $showFilters) {
            SimilarFiltersSheet(
                sortOption: $sortOption,
                startDate: $startDate,
                endDate: $endDate
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(20)
        }
    }

}


// MARK: - Preview

#Preview("Screenshots") {
    let store = SimilarPhotosStore()
    NavigationStack {
        MediaGridView(config: .screenshots(store))
    }
    .environment(store)
    .preferredColorScheme(.dark)
}

#Preview("Other Photos") {
    let store = SimilarPhotosStore()
    NavigationStack {
        MediaGridView(config: .otherPhotos(store))
    }
    .environment(store)
    .preferredColorScheme(.dark)
}

#Preview("Screen Recordings") {
    let store = SimilarPhotosStore()
    NavigationStack {
        MediaGridView(config: .screenRecordings(store))
    }
    .environment(store)
    .preferredColorScheme(.dark)
}

#Preview("Short Recordings") {
    let store = SimilarPhotosStore()
    NavigationStack {
        MediaGridView(config: .shortRecordings(store))
    }
    .environment(store)
    .preferredColorScheme(.dark)
}
