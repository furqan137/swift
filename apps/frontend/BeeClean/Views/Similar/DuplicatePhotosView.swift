import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Duplicate Photos View (list of duplicate groups)
//
// Slimmed in this round (was 568 lines). The single-group detail
// screen (`DuplicateGroupDetailView`) and its grid cell
// (`DuplicatePhotoCell`) live in
// `Components/DuplicateGroupDetailView.swift`. Common chrome
// (header, idle/scanning/empty, delete progress) lives in
// `Components/SimilarCommonStates.swift` and is shared with
// SimilarPhotosView.
//
// `StableGroupOrder` pins the rendered order of duplicate groups
// once they appear, so mid-scan additions and confidence resorts
// in `vm.groups` no longer shuffle the visible list under the
// user's finger while they scroll.
struct DuplicatePhotosView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    @Environment(\.dismiss) private var dismiss
    /// Observe so the delete-bar label re-renders the moment the user
    /// switches languages from Settings.
    @ObservedObject private var loc = LocalizationService.shared
    @State private var showDeleteConfirm = false
    @State private var showDeletionGate = false
    @State private var showPaywall = false
    @State private var showErrorAlert = false
    @State private var pagerTarget: PagerTarget?
    @State private var order = StableGroupOrder()
    /// Per-group Tinder-style swipe target. See SimilarPhotosView for
    /// rationale.
    @State private var swipeGroup: SimilarGroupVM?
    @State private var sortOption: SimilarSortOption = .newest
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var showFilters = false

    /// Sorted + filtered duplicate-group list. Computed inline so it
    /// always derives from the live `vm.duplicateGroups`. See the
    /// matching note in SimilarPhotosView for the cache-removal
    /// rationale — `.task(id:)` was async and could miss the
    /// freshness window for selection toggles.
    private var orderedGroups: [SimilarGroupVM] {
        order.ordered(from: vm.duplicateGroups)
            .applySimilarFilters(sort: sortOption, startDate: startDate, endDate: endDate)
    }

    private var totalSelected: Int {
        orderedGroups.reduce(0) { $0 + $1.selectedCount }
    }

    private var totalBytes: Int64 {
        orderedGroups.reduce(Int64(0)) { $0 + $1.bytesSaved }
    }

    var body: some View {
        ZStack {
            stateContent

            // Pinned delete bar
            if !orderedGroups.isEmpty && totalSelected > 0 && !vm.isDeleting {
                VStack {
                    Spacer()
                    ActionBar(
                        title: BCLoc.deleteDuplicatePhotosFormat.format(
                            totalSelected,
                            formatBytes(totalBytes)
                        ),
                        buttonTitle: "Delete",
                        buttonIcon: "trash.fill",
                        isDestructive: true
                    ) {
                        if SubscriptionService.shared.isPro {
                            showDeleteConfirm = true
                        } else {
                            showDeletionGate = true
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: totalSelected)
            }

            if vm.isDeleting {
                VStack {
                    Spacer()
                    SimilarDeleteProgressBar(
                        deleted: vm.deleteProgress.deleted,
                        totalToDelete: vm.deleteProgress.totalToDelete,
                        fraction: vm.deleteProgress.fraction,
                        currentChunk: vm.deleteProgress.currentChunk,
                        totalChunks: vm.deleteProgress.totalChunks
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
        .task {
            await vm.loadFromCache()
            order.absorb(vm.duplicateGroups)
            if vm.loadedFromCache {
                await vm.incrementalRefresh()
            }
        }
        // Append-only sync: lock new duplicate groups into renderOrder
        // on every store mutation. Existing positions never move.
        .onChange(of: vm.duplicateGroups.count) { _, _ in
            order.absorb(vm.duplicateGroups)
        }
        // `orderedGroups` is now a synchronous computed property so the
        // `.task(id:)` refresh is no longer needed.
        .alert("Delete Duplicates?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { _ = await vm.deleteSelected(category: .duplicates) }
            }
        } message: {
            Text("This will permanently delete \(totalSelected) duplicate photos and free up \(formatBytes(totalBytes)).")
        }
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.notify(.warning) }
        }
        .alert("Some deletions failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.error ?? "Unknown error")
        }
        .onChange(of: vm.isDeleting) { wasDeleting, isDeleting in
            if wasDeleting && !isDeleting {
                order.absorb(vm.duplicateGroups)
                if vm.deleteProgress.failed > 0 { showErrorAlert = true }
            }
        }
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
        .fullScreenCover(item: $pagerTarget) { target in
            SimilarDetailPagerView(
                groupId: target.groupId,
                source: .duplicates,
                startIndex: target.startIndex
            )
            .environment(vm)
        }
        .fullScreenCover(item: $swipeGroup) { group in
            MediaSwipeView(
                vm: GroupSwipeViewModel(
                    store: vm,
                    groupId: group.id,
                    source: .photos,
                    items: group.items
                ),
                config: MediaSwipeConfig(
                    accentColor: .categorySky,
                    saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .duplicates)
                )
            )
        }
        .sheet(isPresented: $showDeletionGate) {
            GateCoordinator(
                config: .config(for: .photos),
                selectedCount: totalSelected,
                onActionApproved: { count in
                    _ = await vm.deleteSelected(limit: count, category: .duplicates)
                    return vm.totalSelectedForDelete
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
    }

    // MARK: - State Routing
    @ViewBuilder
    private var stateContent: some View {
        if vm.isScanningSimilarPhotos {
            stateScaffold {
                SimilarScanningProgressState(
                    phase: vm.progress.currentPhase,
                    progress: vm.progress.progress,
                    percentComplete: vm.progress.percentComplete,
                    tint: .categoryBlue
                )
            }
        } else if let errorMsg = vm.error {
            stateScaffold {
                CategoryEmptyState(
                    iconName: "doc.on.doc.fill",
                    accentColor: .categorySky,
                    title: "Unable to Scan",
                    subtitle: errorMsg
                )
            }
        } else if orderedGroups.isEmpty && vm.progress.isComplete {
            stateScaffold {
                CategoryEmptyState(
                    iconName: "doc.on.doc.fill",
                    accentColor: .categorySky,
                    title: "No Duplicate Photos",
                    subtitle: "Your library is duplicate-free."
                )
            }
        } else if orderedGroups.isEmpty {
            stateScaffold {
                SimilarIdleState(
                    iconName: "doc.on.doc",
                    tint: .categoryBlue,
                    title: "Find Duplicate Photos",
                    subtitle: "Scan your library to find exact\nduplicates you can safely remove",
                    onScan: { Task { await vm.runSimilarPhotosScan(force: true) } }
                )
            }
        } else {
            CollapsingHeaderLayout(
                title: "Duplicate Photos",
                subtitle: "\(orderedGroups.count) groups found",
                trailingContent: AnyView(
                    HStack(spacing: 8) {
                        // Filter chip is faded — sort isn't the primary
                        // action on the Duplicates screen, the
                        // bigger Deselect All is. Half-opacity reads
                        // as "available but secondary".
                        SimilarSortPill(sortOption: sortOption) {
                            showFilters = true
                        }
                        .opacity(0.55)

                        // Prominent variant — Cleanup-style primary
                        // pill. Larger font + padding so the action
                        // weight matches the screen's importance
                        // (this is where the user lands the bulk of
                        // their delete decisions).
                        TopBarSelectAllPill(
                            isAllSelected: vm.allNonBestDuplicatesSelected,
                            onTap: {
                                if vm.allNonBestDuplicatesSelected {
                                    vm.deselectAllDuplicates()
                                } else {
                                    vm.selectAllNonBestDuplicates()
                                }
                            },
                            prominent: true
                        )
                    }
                )
            ) {
                groupListContent
            }
        }
    }

    @ViewBuilder
    private func stateScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(hex: "DDE1F2"), location: 0), .init(color: Color(hex: "DDE1F2"), location: 0.45), .init(color: Color(hex: "E3E6EE"), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                SimilarCategoryHeader(
                    title: "Duplicate Photos",
                    isScanning: vm.isScanningSimilarPhotos,
                    onBack: {
                        BottomNavBarVisibility.shared.releaseHide()
                        dismiss()
                    },
                    onCancel: { vm.cancelScan() }
                )
                content()
            }
        }
    }

    // MARK: - Group List Content
    // LazyVStack so libraries with many duplicate groups don't render every
    // GroupInlineRow upfront — each row's first 2-3 thumbnails fire
    // PHImageManager requests on appear, so an eager VStack of 100+ rows
    // produced hundreds of simultaneous thumbnail requests and the
    // "freezes / loads partial" glitch on tap-in. Per-group horizontal
    // LazyHStack still defers thumbnail loads, and outer LazyVStack
    // keeps off-screen rows out of the request pool entirely.
    private var groupListContent: some View {
        LazyVStack(spacing: 28) {
            // Stable identity by group.id (UUID) — see SimilarPhotosView
            // for rationale. Index-based identity was reshuffling cells
            // and resetting their thumbnails to gray on selection toggles.
            ForEach(Array(orderedGroups.enumerated()), id: \.element.id) { index, group in
                GroupInlineRow(
                    group: group,
                    groupIndex: index,
                    source: .duplicates,
                    onToggle: { groupId, assetId in
                        vm.toggleSelection(groupId: groupId, assetId: assetId)
                    },
                    onSelectAll: { groupId in
                        vm.selectAll(groupId: groupId)
                    },
                    onDeselectAll: { groupId in
                        vm.deselectAll(groupId: groupId)
                    },
                    onOpenDetail: { groupId, startIndex in
                        pagerTarget = PagerTarget(groupId: groupId, startIndex: startIndex)
                    },
                    onSwipeGroup: { g in
                        swipeGroup = g
                    },
                    onItemUnloadable: { assetId in
                        vm.pruneUnloadableAsset(assetId)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 120)
        .allowsHitTesting(!vm.isDeleting)
    }
}

#Preview {
    NavigationStack {
        DuplicatePhotosView()
    }
    .preferredColorScheme(.light)
}
