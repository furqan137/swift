import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Screenshots View (grouped similar screenshots)
struct ScreenshotsView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    /// Observe so the delete-bar label re-renders on locale change.
    @ObservedObject private var loc = LocalizationService.shared
    @State private var showDeleteConfirm = false
    @State private var showDeletionGate = false
    @State private var showPaywall = false
    @State private var showErrorAlert = false
    @State private var pagerTarget: PagerTarget?
    /// Per-group Tinder swipe deck. See SimilarPhotosView for rationale.
    @State private var swipeGroup: SimilarGroupVM?
    @State private var sortOption: SimilarSortOption = .newest
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var showFilters = false

    /// Sorted + filtered screenshot group list — synchronous computed
    /// property so selection toggles light up the per-cell checkmark
    /// on the same render. See SimilarPhotosView for the
    /// cache-removal rationale.
    private var orderedScreenshotGroups: [SimilarGroupVM] {
        vm.screenshotGroups.applySimilarFilters(sort: sortOption, startDate: startDate, endDate: endDate)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if vm.isScanningScreenshots {
                ZStack { LinearGradient(stops: [.init(color: Color(hex: "DDE1F2"), location: 0), .init(color: Color(hex: "DDE1F2"), location: 0.45), .init(color: Color(hex: "E3E6EE"), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(); VStack(spacing: 0) { nonCollapsingHeader; scanningState } }
            } else if let errorMsg = vm.error {
                ZStack { LinearGradient(stops: [.init(color: Color(hex: "DDE1F2"), location: 0), .init(color: Color(hex: "DDE1F2"), location: 0.45), .init(color: Color(hex: "E3E6EE"), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(); VStack(spacing: 0) { nonCollapsingHeader; errorState(errorMsg) } }
            } else if vm.screenshotGroups.isEmpty && vm.progress.isComplete {
                ZStack { LinearGradient(stops: [.init(color: Color(hex: "DDE1F2"), location: 0), .init(color: Color(hex: "DDE1F2"), location: 0.45), .init(color: Color(hex: "E3E6EE"), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(); VStack(spacing: 0) { nonCollapsingHeader; emptyState } }
            } else if vm.screenshotGroups.isEmpty {
                ZStack { LinearGradient(stops: [.init(color: Color(hex: "DDE1F2"), location: 0), .init(color: Color(hex: "DDE1F2"), location: 0.45), .init(color: Color(hex: "E3E6EE"), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(); VStack(spacing: 0) { nonCollapsingHeader; idleState } }
            } else {
                CollapsingHeaderLayout(
                    title: "Similar Screenshots",
                    subtitle: "\(orderedScreenshotGroups.count) groups found",
                    trailingContent: AnyView(
                        HStack(spacing: 8) {
                            SimilarSortPill(sortOption: sortOption) {
                                showFilters = true
                            }
                            TopBarSelectAllPill(isAllSelected: vm.allNonBestScreenshotsSelected) {
                                if vm.allNonBestScreenshotsSelected {
                                    vm.deselectAllScreenshots()
                                } else {
                                    vm.selectAllNonBestScreenshots()
                                }
                            }
                        }
                    )
                ) {
                    groupListContent
                }
            }

            if !vm.screenshotGroups.isEmpty && vm.totalScreenshotSelectedForDelete > 0 && !vm.isDeleting {
                VStack {
                    Spacer()
                    ActionBar(
                        title: BCLoc.deleteSimilarScreenshotsFormat.format(
                            vm.totalScreenshotSelectedForDelete,
                            formatBytes(vm.totalScreenshotBytesSaved)
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
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.totalScreenshotSelectedForDelete)
            }

            if vm.isDeleting {
                VStack {
                    Spacer()
                    deleteProgressBar
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
        }
        // `orderedScreenshotGroups` is now a synchronous computed
        // property so the `.task(id:)` refresh is no longer needed.
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.notify(.warning) }
        }
        .alert("Delete Screenshots?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { _ = await vm.deleteAllSelectedScreenshots() }
            }
        } message: {
            Text("This will permanently delete \(vm.totalScreenshotSelectedForDelete) screenshots and free up \(formatBytes(vm.totalScreenshotBytesSaved)).")
        }
        .alert("Some deletions failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.error ?? "Unknown error")
        }
        .onChange(of: vm.isDeleting) { wasDeleting, isDeleting in
            if wasDeleting && !isDeleting && vm.deleteProgress.failed > 0 {
                showErrorAlert = true
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
                source: .screenshots,
                startIndex: target.startIndex
            )
            .environment(vm)
        }
        .fullScreenCover(item: $swipeGroup) { group in
            MediaSwipeView(
                vm: GroupSwipeViewModel(
                    store: vm,
                    groupId: group.id,
                    source: .screenshots,
                    items: group.items
                ),
                config: MediaSwipeConfig(
                    accentColor: .categoryTeal,
                    saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .similarScreenshots)
                )
            )
        }
        .sheet(isPresented: $showDeletionGate) {
            GateCoordinator(
                config: .config(for: .photos),
                selectedCount: vm.totalScreenshotSelectedForDelete,
                onActionApproved: { count in
                    _ = await vm.deleteAllSelectedScreenshots(limit: count)
                    return vm.totalScreenshotSelectedForDelete
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

    private var nonCollapsingHeader: some View {
        HStack {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                BottomNavBarVisibility.shared.releaseHide()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
            }
            Spacer()
            Text("Similar Screenshots")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))
            Spacer()
            if vm.isScanningScreenshots {
                Button("Cancel") { vm.cancelScan() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.destructive)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    // MARK: - Idle
    private var idleState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.categoryGreen.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44))
                    .foregroundColor(.categoryGreen)
            }

            VStack(spacing: 8) {
                Text("Find Similar Screenshots")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("Scan your library to find similar\nscreenshots you can clean up")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .multilineTextAlignment(.center)
            }

            PrimaryButton("Scan Photos", iconName: "magnifyingglass") {
                Task { await vm.runScreenshotsScan(force: true) }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Scanning
    private var scanningState: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: vm.progress.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .categoryGreen))
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text(vm.progress.currentPhase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("\(vm.progress.percentComplete)%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.categoryGreen)
            }

            Spacer()
        }
    }

    // MARK: - Empty / Error — both routed through `CategoryEmptyState`
    // so every photo-category screen shares one visual treatment
    // (icon + halo + title + subtitle, no retry button).
    private var emptyState: some View {
        CategoryEmptyState(
            iconName: "rectangle.on.rectangle.fill",
            accentColor: .categoryTeal,
            title: "No Similar Screenshots",
            subtitle: "Your screenshots are all unique."
        )
    }

    private func errorState(_ message: String) -> some View {
        CategoryEmptyState(
            iconName: "rectangle.on.rectangle.fill",
            accentColor: .categoryTeal,
            title: "Unable to Scan",
            subtitle: message
        )
    }

    private var groupListContent: some View {
        // LazyVStack — see DuplicatePhotosView for rationale.
        LazyVStack(spacing: 28) {
            // Stable identity by group.id (UUID) — see SimilarPhotosView.
            ForEach(Array(orderedScreenshotGroups.enumerated()), id: \.element.id) { index, group in
                GroupInlineRow(
                    group: group,
                    groupIndex: index,
                    source: .screenshots,
                    onToggle: { groupId, assetId in
                        vm.toggleScreenshotGroupSelection(groupId: groupId, assetId: assetId)
                    },
                    onSelectAll: { groupId in
                        vm.selectAllScreenshot(groupId: groupId)
                    },
                    onDeselectAll: { groupId in
                        vm.deselectAllScreenshot(groupId: groupId)
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

    // MARK: - Delete Progress
    private var deleteProgressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: vm.deleteProgress.fraction)
                .progressViewStyle(LinearProgressViewStyle(tint: .destructive))

            HStack {
                Text("Deleting… \(vm.deleteProgress.deleted)/\(vm.deleteProgress.totalToDelete)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                if vm.deleteProgress.totalChunks > 1 {
                    Text("Batch \(vm.deleteProgress.currentChunk)/\(vm.deleteProgress.totalChunks)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
        }
        .padding(16)
        .background(Color.surfaceLight)
    }
}

// MARK: - Screenshot Group Card — kept for backwards compatibility
struct ScreenshotGroupCard: View {
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
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                }
                .frame(width: 72, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.count) similar screenshots")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))

                    HStack(spacing: 8) {
                        Label("\(group.selectedCount) selected", systemImage: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.mutedForeground)

                        Text("\u{00B7}")
                            .foregroundColor(.mutedForeground.opacity(0.5))

                        Text(formatBytes(group.bytesSaved))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.categoryGreen)
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
                    .foregroundColor(.mutedForeground)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
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
        ScreenshotsView()
    }
    .preferredColorScheme(.light)
}
