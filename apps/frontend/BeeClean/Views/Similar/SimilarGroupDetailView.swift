import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Similar Group Detail View
struct SimilarGroupDetailView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    let groupId: UUID
    var source: GroupSource = .photos
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showDeletionGate = false
    @State private var showPaywall = false
    @State private var showErrorAlert = false
    @State private var pagerStartIndex: Int = 0
    @State private var showPager = false

    private var group: SimilarGroupVM? {
        let sourceGroups: [SimilarGroupVM]
        switch source {
        case .photos, .duplicates: sourceGroups = vm.groups
        case .screenshots: sourceGroups = vm.screenshotGroups
        case .videos: sourceGroups = vm.videoGroups
        }
        return sourceGroups.first { $0.id == groupId }
    }

    var body: some View {
        AppLayout(showBackButton: true, title: source.title) {
            if let group = group {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 16) {
                            groupHeader(group)
                            selectionControls(group)
                            photoGrid(group)
                        }
                        .padding(.bottom, group.selectedCount > 0 ? 120 : 20)
                    }
                    .allowsHitTesting(!vm.isDeleting)

                    // Delete bar / progress
                    if vm.isDeleting {
                        deleteProgressBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if group.selectedCount > 0 {
                        ActionBar(
                            title: "Delete \(group.selectedCount) \(source.itemLabel.lowercased()) (\(formatBytes(group.bytesSaved)))",
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
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: group.selectedCount)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.isDeleting)
            } else {
                ContentUnavailableView("Group not found", systemImage: "photo.stack")
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Delete \(source.itemLabel)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let success: Bool
                    switch source {
                    case .photos, .duplicates:
                        success = await vm.deleteSelected(inGroup: groupId)
                    case .screenshots:
                        success = await vm.deleteSelectedScreenshotGroup(inGroup: groupId)
                    case .videos:
                        success = await vm.deleteSelectedVideoGroup(inGroup: groupId)
                    }
                    if success && (group?.items.count ?? 0) <= 1 {
                        dismiss()
                    }
                }
            }
        } message: {
            if let group = group {
                Text("This will permanently delete \(group.selectedCount) \(source.itemLabel.lowercased()) and free up \(formatBytes(group.bytesSaved)).")
            }
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
        .fullScreenCover(isPresented: $showPager) {
            SimilarDetailPagerView(
                groupId: groupId,
                source: source,
                startIndex: pagerStartIndex
            )
            .environment(vm)
        }
        .sheet(isPresented: $showDeletionGate) {
            GateCoordinator(
                config: .config(for: source == .videos ? .videos : .photos),
                selectedCount: group?.selectedCount ?? 0,
                onActionApproved: { count in
                    let success: Bool
                    switch source {
                    case .photos, .duplicates:
                        success = await vm.deleteSelected(inGroup: groupId, limit: count)
                    case .screenshots:
                        success = await vm.deleteSelectedScreenshotGroup(inGroup: groupId, limit: count)
                    case .videos:
                        success = await vm.deleteSelectedVideoGroup(inGroup: groupId, limit: count)
                    }
                    if success && (group?.items.count ?? 0) <= 1 {
                        dismiss()
                    }
                    return group?.selectedCount ?? 0
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

    // MARK: - Delete Progress Bar
    private var deleteProgressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: vm.deleteProgress.fraction)
                .progressViewStyle(LinearProgressViewStyle(tint: .destructive))

            HStack {
                Text("Deleting… \(vm.deleteProgress.deleted)/\(vm.deleteProgress.totalToDelete)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                if vm.deleteProgress.totalChunks > 1 {
                    Text("Batch \(vm.deleteProgress.currentChunk)/\(vm.deleteProgress.totalChunks)")
                        .font(.system(size: 12))
                        .foregroundColor(.mutedForeground)
                }
            }
        }
        .padding(16)
        .background(Color.surfaceLight)
    }

    // MARK: - Group Header
    private func groupHeader(_ group: SimilarGroupVM) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                statPill(value: "\(group.count)", label: source.itemLabel, color: source.themeColor)
                statPill(value: formatBytes(group.totalBytes), label: "Total Size", color: .categoryBlue)
                statPill(value: "\(Int(group.confidence * 100))%", label: "Match", color: .success)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Selection Controls
    private func selectionControls(_ group: SimilarGroupVM) -> some View {
        HStack {
            Text("Best \(source.itemLabel.lowercased().dropLast()) is kept automatically")
                .font(.system(size: 13))
                .foregroundColor(.mutedForeground)

            Spacer()

            Menu {
                Button("Select All Duplicates") {
                    switch source {
                    case .photos, .duplicates:
                        vm.selectAllExceptBest(groupId: groupId)
                    case .screenshots:
                        vm.selectAllExceptBestScreenshot(groupId: groupId)
                    case .videos:
                        vm.selectAllExceptBestVideo(groupId: groupId)
                    }
                }
                // Deselect is offered only for multi-selection — a single
                // selected tile is faster cleared by tapping it directly.
                if group.selectedCount > 1 {
                    Button("Deselect All") {
                        switch source {
                        case .photos, .duplicates:
                            vm.deselectAll(groupId: groupId)
                        case .screenshots:
                            vm.deselectAllScreenshot(groupId: groupId)
                        case .videos:
                            vm.deselectAllVideo(groupId: groupId)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle")
                    Text(BCLoc.edit.tr)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primaryColor)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Photo Grid
    private func photoGrid(_ group: SimilarGroupVM) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                SimilarPhotoCell(
                    item: item,
                    isBest: item.isBest,
                    isSelected: item.isSelectedForDelete,
                    onOpenDetail: {
                        pagerStartIndex = idx
                        showPager = true
                    },
                    onToggleSelect: {
                        guard !item.isBest else { return }
                        switch source {
                        case .photos, .duplicates:
                            vm.toggleSelection(groupId: groupId, assetId: item.assetId)
                        case .screenshots:
                            vm.toggleScreenshotGroupSelection(groupId: groupId, assetId: item.assetId)
                        case .videos:
                            vm.toggleVideoGroupSelection(groupId: groupId, assetId: item.assetId)
                        }
                    },
                    onUnloadable: { vm.pruneUnloadableAsset(item.assetId) }
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Similar Photo Cell
struct SimilarPhotoCell: View {
    let item: SimilarGroupItem
    let isBest: Bool
    let isSelected: Bool
    let onOpenDetail: () -> Void
    let onToggleSelect: () -> Void
    /// Forwarded to PhotoThumbnailView's `onUnloadable`. Caller must route
    /// to `store.pruneUnloadableAsset(item.assetId)` so a deleted-from-Photos
    /// asset doesn't sit on screen as a blank tile.
    var onUnloadable: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Photo thumbnail — tap to open the full-screen pager
            PhotoThumbnailView(
                assetIdentifier: item.assetId,
                size: CGSize(width: 400, height: 400),
                contentMode: .fill,
                onUnloadable: { onUnloadable?() }
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            // No systemGray6 placeholder — `PhotoThumbnailView` renders
            // `Color.clear` while loading, and `onUnloadable` prunes the
            // cell entirely on failure. A persistent gray rectangle was the
            // user-visible "graybox" bug.
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            // Dim selected-for-delete photos
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(isSelected ? 0.35 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                onOpenDetail()
            }

            // Select chip — tap to toggle, isolated from the photo tap area
            badge
                .padding(6)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isBest else {
                        onOpenDetail()
                        return
                    }
                    onToggleSelect()
                }

            // Source-app badge — top-right corner of the tile. The select
            // chip lives at top-left (via ZStack(alignment: .topLeading)),
            // so they never collide. Renders nothing for nil / .camera.
            SocialSourceBadge(source: item.sourceApp, size: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    private var borderColor: Color {
        if isBest { return .success }
        if isSelected { return .destructive.opacity(0.7) }
        return .clear
    }

    private var borderWidth: CGFloat {
        (isBest || isSelected) ? 3 : 0
    }

    @ViewBuilder
    private var badge: some View {
        if isBest {
            Label("Best", systemImage: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.success)
                .cornerRadius(6)
        } else {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.destructive : Color.black.opacity(0.4))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SimilarGroupDetailView(
            groupId: UUID()
        )
        .environment(SimilarPhotosStore())
    }
    .preferredColorScheme(.dark)
}
