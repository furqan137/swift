import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Similar Photos View
//
// Slimmed in this round (was 426 lines). Common chrome — header,
// idle/scanning/empty states, delete progress bar, stale banner —
// lives in `Components/SimilarCommonStates.swift` and is shared
// with DuplicatePhotosView. The detail-cell card extension lives in
// `Components/SimilarGroupListLegacyCard.swift`.
//
// List rendering uses `StableGroupOrder` so groups already shown
// to the user keep their position even as new scan waves land in
// `vm.groups`. Without that snapshot, mid-scan mutations to the
// store re-rendered the list AND moved items, producing the
// "everything shuffles as I scroll" bug the user reported.
struct SimilarPhotosView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    /// Observe so the delete-bar label re-renders the moment the user
    /// switches languages from Settings. Without observation the
    /// `.format()` call would still pull the new locale on the next
    /// invalidation, but the bar text wouldn't refresh until something
    /// else triggered a body recompute.
    @ObservedObject private var loc = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showDeletionGate = false
    @State private var showPaywall = false
    @State private var showErrorAlert = false
    @State private var pagerTarget: PagerTarget?
    @State private var order = StableGroupOrder()
    /// Group whose Tinder-style swipe deck is currently presented. Set by
    /// the per-row Swipe pill in `GroupInlineRow`; cleared by the cover's
    /// dismiss. Identifiable via group.id so `.fullScreenCover(item:)`
    /// re-presents cleanly when the user taps Swipe on a different group.
    @State private var swipeGroup: SimilarGroupVM?
    @State private var sortOption: SimilarSortOption = .newest
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var showFilters = false
    @StateObject private var actionFlow = ActionFlowCoordinator()

    /// Sorted + filtered group list. Computed inline so the value is
    /// always derived from the live `vm.groups`. The previous @State
    /// cache (refreshed via `.task(id: orderedGroupsCacheKey)`) had
    /// two latent failure modes:
    ///   1. Cache key omitted selection state → toggle didn't refresh.
    ///   2. .task(id:) is async and could be preempted between body
    ///      renders, leaving stale value-type item copies on screen.
    /// Direct computation is O((groups × log groups) + items) per
    /// render — microseconds on realistic library sizes — and SwiftUI
    /// only re-evaluates body when @Observable tracks an actual
    /// change. Correctness > the marginal perf the cache bought.
    private var orderedGroups: [SimilarGroupVM] {
        order.ordered(from: vm.groups)
            .applySimilarFilters(sort: sortOption, startDate: startDate, endDate: endDate)
    }

    var body: some View {
        ZStack {
            stateContent

            // Pinned delete bar — animation key is the BOOLEAN
            // "is something selected", not the live count. Previously
            // the value was `vm.totalSelectedForDelete` (an integer
            // that shifts on every per-photo selection toggle), so
            // every tap inside a group fired a spring re-evaluation
            // on this overlay even though its visibility hadn't
            // changed. Boolean key animates only the appear/disappear
            // transition, which is what the user actually perceives.
            if !orderedGroups.isEmpty && vm.totalSelectedForDelete > 0 && !vm.isDeleting {
                VStack {
                    Spacer()
                    deleteButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.totalSelectedForDelete > 0)
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
            order.absorb(vm.groups)
            if vm.loadedFromCache {
                await vm.incrementalRefresh()
            }
        }
        // Append-only sync: lock new groups into renderOrder on
        // every store mutation. Existing positions never move. The
        // ordered+filtered snapshot is now a synchronous computed
        // property (see `orderedGroups`) so no `.task(id:)` refresh
        // is needed — every body render reads the live store state.
        .onChange(of: vm.groups.count) { _, _ in order.absorb(vm.groups) }
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.notify(.warning) }
        }
        .alert("Delete Photos?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let bytesFreed = vm.totalBytesSaved
                let count = vm.totalSelectedForDelete
                Task {
                    await actionFlow.execute(section: .photos, actionType: .delete, itemCount: count) {
                        _ = await vm.deleteSelected(category: .similarPhotos)
                        return ActionResult(
                            section: .photos, actionType: .delete,
                            itemsProcessed: count, bytesFreed: bytesFreed,
                            bytesSaved: nil, originalBytes: nil, compressedBytes: nil,
                            timestamp: Date(), breakdown: nil, topSenders: nil
                        )
                    }
                }
            }
        } message: {
            Text("This will permanently delete \(vm.totalSelectedForDelete) photos and free up \(formatBytes(vm.totalBytesSaved)).")
        }
        .alert("Some deletions failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.error ?? "Unknown error")
        }
        .onChange(of: vm.isDeleting) { wasDeleting, isDeleting in
            if wasDeleting && !isDeleting {
                // After delete completes, prune deleted ids out of renderOrder
                order.absorb(vm.groups)
                if vm.deleteProgress.failed > 0 { showErrorAlert = true }
            }
        }
        .fullScreenCover(item: $pagerTarget) { target in
            SimilarDetailPagerView(
                groupId: target.groupId,
                source: .photos,
                startIndex: target.startIndex
            )
            .environment(vm)
        }
        // Blur the parent while the filter sheet is open — at .medium
        // detent the top half stays visible and the user wanted that
        // area frosted instead of just dimmed by the system.
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
        .fullScreenCover(item: $swipeGroup) { group in
            MediaSwipeView(
                vm: GroupSwipeViewModel(
                    store: vm,
                    groupId: group.id,
                    source: .photos,
                    items: group.items
                ),
                config: MediaSwipeConfig(
                    accentColor: .categoryViolet,
                    saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .similarPhotos)
                )
            )
        }
        .sheet(isPresented: $showDeletionGate) {
            GateCoordinator(
                config: .config(for: .photos),
                selectedCount: vm.totalSelectedForDelete,
                onActionApproved: { count in
                    let bytesFreed = vm.totalBytesSaved
                    let itemCount = min(count, vm.totalSelectedForDelete)
                    Task {
                        await actionFlow.execute(section: .photos, actionType: .delete, itemCount: itemCount) {
                            _ = await vm.deleteSelected(limit: count, category: .similarPhotos)
                            return ActionResult(
                                section: .photos, actionType: .delete,
                                itemsProcessed: itemCount, bytesFreed: bytesFreed,
                                bytesSaved: nil, originalBytes: nil, compressedBytes: nil,
                                timestamp: Date(), breakdown: nil, topSenders: nil
                            )
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

    // MARK: - State Routing
    @ViewBuilder
    private var stateContent: some View {
        if vm.isScanningSimilarPhotos {
            stateScaffold {
                SimilarScanningProgressState(
                    phase: vm.progress.currentPhase,
                    progress: vm.progress.progress,
                    percentComplete: vm.progress.percentComplete,
                    tint: .categoryPurple
                )
            }
        } else if let errorMsg = vm.error {
            stateScaffold {
                CategoryEmptyState(
                    iconName: "photo.stack.fill",
                    accentColor: .categoryViolet,
                    title: "Unable to Scan",
                    subtitle: errorMsg
                )
            }
        } else if orderedGroups.isEmpty && vm.progress.isComplete {
            stateScaffold {
                CategoryEmptyState(
                    iconName: "photo.stack.fill",
                    accentColor: .categoryViolet,
                    title: "No Similar Photos",
                    subtitle: "Your library looks clean."
                )
            }
        } else if orderedGroups.isEmpty {
            stateScaffold {
                SimilarIdleState(
                    iconName: "photo.stack",
                    tint: .categoryPurple,
                    title: "Find Similar Photos",
                    subtitle: "Scan your library to find duplicate\nand similar photos you can clean up",
                    onScan: { Task { await vm.runSimilarPhotosScan(force: true) } }
                )
            }
        } else {
            CollapsingHeaderLayout(
                title: "Similar Photos",
                subtitle: "\(orderedGroups.count) groups found",
                trailingContent: AnyView(
                    HStack(spacing: 8) {
                        SimilarSortPill(sortOption: sortOption) {
                            showFilters = true
                        }
                        TopBarSelectAllPill(isAllSelected: vm.allNonBestPhotosSelected) {
                            if vm.allNonBestPhotosSelected {
                                vm.deselectAllPhotos()
                            } else {
                                vm.selectAllNonBestPhotos()
                            }
                        }
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
                    title: "Similar Photos",
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
    //
    // LazyVStack so libraries with 100+ similar groups don't render every
    // GroupInlineRow upfront — each row's first 2-3 thumbnails fire
    // PHImageManager requests on appear, and an eager VStack of 100 rows
    // = ~300 simultaneous thumbnail requests, which is what was causing
    // the "click into Similar Photos and it freezes / loads partial"
    // glitch. Per-group horizontal scroll inside GroupInlineRow already
    // lazy-loads its tiles; pairing with LazyVStack at the outer level
    // means only on-screen groups pay the thumbnail cost.
    private var groupListContent: some View {
        LazyVStack(spacing: 28) {
            if vm.loadedFromCache && vm.cacheIsStale {
                SimilarStaleCacheBanner {
                    Task { await vm.runSimilarPhotosScan(force: true) }
                }
            }

            // Stable identity by group.id (UUID) so a mid-list mutation
            // (selection toggle, late cluster refinement) doesn't
            // re-shuffle SwiftUI identities and reset thumbnails inside
            // already-rendered rows back to gray boxes.
            ForEach(Array(orderedGroups.enumerated()), id: \.element.id) { index, group in
                GroupInlineRow(
                    group: group,
                    groupIndex: index,
                    source: .photos,
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

    // MARK: - Delete Button
    //
    // Uses the shared ActionBar so the destructive bar renders with the
    // same espresso-deep crimson gradient + leading icon chip as every
    // other category screen (Duplicates, Similar Screenshots, Similar
    // Videos, Blurry, Other Photos, Recordings). Previously this was a
    // custom RoundedRectangle button with a flat red gradient, and the
    // user flagged Similar as visually inconsistent with the rest of
    // the cleanup surfaces.
    private var deleteButton: some View {
        ActionBar(
            title: BCLoc.deleteSimilarPhotosFormat.format(
                vm.totalSelectedForDelete,
                formatBytes(vm.totalBytesSaved)
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
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Similar Group Card (legacy compact list row)
//
// Kept for backwards compatibility with anywhere outside this view
// that still binds to the old card layout. New screens use
// `GroupInlineRow` with the rich preview grid.
struct SimilarGroupCard: View {
    let group: SimilarGroupVM
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    ForEach(Array(group.items.prefix(3).enumerated()), id: \.element.id) { i, item in
                        PhotoThumbnailView(
                            assetIdentifier: item.assetId,
                            size: CGSize(width: 56, height: 56)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .offset(x: CGFloat(i) * 6, y: CGFloat(i) * -4)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                }
                .frame(width: 72, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.count) similar photos")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))

                    HStack(spacing: 8) {
                        Label("\(group.selectedCount) selected", systemImage: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "A1A1AA"))

                        Text("·")
                            .foregroundColor(Color(hex: "A1A1AA").opacity(0.5))

                        Text(formatBytes(group.bytesSaved))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.categoryPurple)
                    }
                }

                Spacer()

                Text("\(Int(group.confidence * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(confidenceColor(group.confidence))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(confidenceColor(group.confidence).opacity(0.15))
                    .cornerRadius(8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.85 { return .success }
        if confidence >= 0.65 { return .warning }
        return .destructive
    }
}

#Preview {
    NavigationStack {
        SimilarPhotosView()
    }
    .preferredColorScheme(.light)
}
