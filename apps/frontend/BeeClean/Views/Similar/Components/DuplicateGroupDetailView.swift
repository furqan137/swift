import SwiftUI
import Photos
import RevenueCatUI

// MARK: - Duplicate Group Detail View
//
// Single-group detail screen pushed from `DuplicateGroupListRow` /
// `GroupInlineRow`. Shows the "best" photo at the top with a Keep
// crown, then a 3-column grid of selectable duplicates underneath.
// Lives in its own file so DuplicatePhotosView stays focused on the
// list-of-groups concern.
struct DuplicateGroupDetailView: View {
    @Environment(SimilarPhotosStore.self) private var vm
    let groupId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showDeletionGate = false
    @State private var showPaywall = false
    @State private var showErrorAlert = false

    private var group: SimilarGroupVM? {
        vm.groups.first { $0.id == groupId }
    }

    var body: some View {
        AppLayout(showBackButton: true, title: "Duplicate Group") {
            if let group = group {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 20) {
                            keepSection(group)
                            duplicatesSection(group)
                        }
                        .padding(.bottom, group.selectedCount > 0 ? 120 : 20)
                    }
                    .allowsHitTesting(!vm.isDeleting)

                    if vm.isDeleting {
                        SimilarDeleteProgressBar(
                            deleted: vm.deleteProgress.deleted,
                            totalToDelete: vm.deleteProgress.totalToDelete,
                            fraction: vm.deleteProgress.fraction,
                            currentChunk: vm.deleteProgress.currentChunk,
                            totalChunks: vm.deleteProgress.totalChunks
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if group.selectedCount > 0 {
                        ActionBar(
                            title: "Delete \(group.selectedCount) duplicates (\(formatBytes(group.bytesSaved)))",
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
                ContentUnavailableView("Group not found", systemImage: "doc.on.doc")
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Delete Duplicates?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let success = await vm.deleteSelected(inGroup: groupId)
                    if success && (group?.items.count ?? 0) <= 1 {
                        BottomNavBarVisibility.shared.releaseHide()
                        dismiss()
                    }
                }
            }
        } message: {
            if let group = group {
                Text("This will permanently delete \(group.selectedCount) duplicate photos and free up \(formatBytes(group.bytesSaved)).")
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
        .sheet(isPresented: $showDeletionGate) {
            GateCoordinator(
                config: .config(for: .photos),
                selectedCount: group?.selectedCount ?? 0,
                onActionApproved: { count in
                    let success = await vm.deleteSelected(inGroup: groupId, limit: count)
                    if success && (group?.items.count ?? 0) <= 1 {
                        BottomNavBarVisibility.shared.releaseHide()
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

    // MARK: - Keep Section (best photo, large)
    private func keepSection(_ group: SimilarGroupVM) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label("Keep", systemImage: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.success)
                Spacer()
            }
            .padding(.horizontal, 20)

            if let bestItem = group.items.first(where: { $0.isBest }) {
                PhotoThumbnailView(
                    assetIdentifier: bestItem.assetId,
                    size: CGSize(width: 400, height: 280),
                    contentMode: .fill,
                    onUnloadable: { vm.pruneUnloadableAsset(bestItem.assetId) }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.success, lineWidth: 3)
                )
                .overlay(alignment: .topLeading) {
                    Label("Best Quality", systemImage: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.success)
                        .cornerRadius(8)
                        .padding(10)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Duplicates Section (deletable photos)
    private func duplicatesSection(_ group: SimilarGroupVM) -> some View {
        let dupes = group.items.filter { !$0.isBest }

        return VStack(spacing: 10) {
            HStack {
                Label("\(dupes.count) Duplicates", systemImage: "trash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.destructive)

                Spacer()

                Menu {
                    Button("Select All") {
                        vm.selectAllExceptBest(groupId: groupId)
                    }
                    // Deselect All only after the user has built up
                    // a multi-select; a single tap on the chosen
                    // tile clears it faster than a menu round-trip.
                    if group.selectedCount > 1 {
                        Button("Deselect All") {
                            vm.deselectAll(groupId: groupId)
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

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(dupes) { item in
                    DuplicatePhotoCell(
                        item: item,
                        isSelected: item.isSelectedForDelete,
                        onUnloadable: { vm.pruneUnloadableAsset(item.assetId) }
                    ) {
                        vm.toggleSelection(groupId: groupId, assetId: item.assetId)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Duplicate Photo Cell
struct DuplicatePhotoCell: View {
    let item: SimilarGroupItem
    let isSelected: Bool
    /// Optional callback fired once when the underlying PHAsset can't
    /// be rendered after the loadThumbnail retry chain. The owning
    /// view wires this to `store.pruneUnloadableAsset` so the cell
    /// vanishes from the grid instead of sitting on screen as a gray
    /// placeholder.
    var onUnloadable: (() -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                PhotoThumbnailView(
                    assetIdentifier: item.assetId,
                    size: CGSize(width: 200, height: 200),
                    contentMode: .fill,
                    onUnloadable: { onUnloadable?() }
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.destructive.opacity(0.7) : .clear,
                                lineWidth: isSelected ? 3 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(isSelected ? 0.35 : 0))
                )

                selectionBadge
                    .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                // Source-app badge — top-right corner. Selection chip
                // stays at top-left, so they never collide.
                SocialSourceBadge(source: item.sourceApp, size: 18)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionBadge: some View {
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
