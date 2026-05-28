import SwiftUI
import Photos

// MARK: - SavedFindsView
//
// Personal Hub → Saved Finds destination. Renders the user's bookmarked
// photos and videos as a sleek grid, newest first. Removing an item
// here only deletes the saved reference — the original asset stays in
// Photos.

struct SavedFindsView: View {
    @StateObject private var vm = SavedFindsViewModel()
    @ObservedObject private var savedFindsStore = SavedFindsStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Polled on `.task` and `.onAppear` (PhotoKit doesn't publish auth
    /// changes via Combine). Drives the "Some saves are hidden" banner
    /// when the user has granted `.limited` access AND any of their
    /// saves live outside the granted set.
    @State private var photoAuth: PHAuthorizationStatus = .notDetermined
    @State private var previewAssetId: String?
    @State private var pendingRemove: SavedFind?
    @State private var toast: BeeToast?
    /// Select-mode flag. While true, tile tap toggles selection instead
    /// of opening the preview; long-press context menu is suppressed; a
    /// destructive action bar surfaces at the bottom.
    @State private var isSelecting: Bool = false
    /// Keyed by `SavedFind.id` rather than asset identifier — that's the
    /// id `vm.remove(_:)` deletes by, and lets us distinguish a saved
    /// reference from the underlying PHAsset (which could in principle
    /// be saved again under a new SavedFind).
    @State private var selectedFindIds: Set<UUID> = []
    /// Hearted vs Bookmarked toggle — two sections rendered as a
    /// segmented control above the grid. Default `.bookmarked` so the
    /// legacy Save-pill entries (which decode as `.bookmarked` via
    /// `effectiveKind`) still surface in the same place users expect.
    @State private var selectedKind: SavedFindKind = .bookmarked
    @State private var showBulkRemoveConfirm: Bool = false
    /// Active category filter. `nil` is the "All" chip — every find
    /// flows into the grid. Otherwise only finds with a matching
    /// `sourceCategory` render.
    @State private var selectedCategory: SavedFindSourceCategory?

    /// Per-source filter — mutually exclusive with `selectedCategory`. Set
    /// when the user taps one of the source-app chips ("Snapchat",
    /// "Instagram", etc.) and filters `vm.resolved` by `sourceApp`.
    /// Tapping the same chip again clears it.
    @State private var selectedSource: PhotoSource?
    /// Last batch of finds the user just removed (single tap from a
    /// tile/preview = 1 entry, bulk = N). Held in memory only — when
    /// the user taps "Undo" in the bar below the grid, we restore
    /// these back into the store with their original ids + timestamps.
    /// Cleared on a 4s timeout, on app background, or on a fresh remove.
    @State private var pendingUndo: [SavedFind] = []
    /// Each undo batch gets a fresh id so a rapid second remove
    /// supersedes the prior bar (and cancels the old auto-dismiss
    /// task) instead of letting an in-flight `Task.sleep` clear the
    /// new bar.
    @State private var undoBatchId: UUID = UUID()
    /// Sort order for the grid. Default `newest` matches the prior
    /// implicit behavior (store returns newest-first); `oldest` and
    /// `byCategory` are user-selectable through the header Sort
    /// menu so power users can reorganize as their save list grows.
    @State private var sortOrder: SavedFindsSortOrder = .newest
    /// Guard against the "empty state flashes for one frame before the
    /// store finishes hydrating" sequence. Stays false until the first
    /// `vm.reload()` completes; the content switch falls back to a
    /// neutral loading state during that window instead of showing
    /// `Save your first find` to a user who already has saves.
    @State private var hasCompletedFirstLoad: Bool = false

    /// Stable display order for the category chips. The enum doesn't
    /// declare `CaseIterable` (the model file is locked for this work),
    /// so the order lives here. Categories are rendered in this sequence
    /// when present in the user's saves, which keeps "Duplicates" first
    /// (the highest-volume category) and groups photos before videos.
    private static let categoryOrder: [SavedFindSourceCategory] = [
        .duplicates,
        .similarPhotos,
        .similarScreenshots,
        .screenshots,
        .blurredPhotos,
        .otherPhotos,
        .similarVideos,
        .screenRecordings,
        .shortRecordings,
        .longVideos
    ]

    /// Categories that have at least one item in the user's resolved
    /// finds. Drives the chip row — chips for empty categories never
    /// surface, so the row scales naturally from "Duplicates only" to
    /// the full ten as users save more.
    private var visibleCategories: [SavedFindSourceCategory] {
        let present = Set(vm.resolved.map(\.sourceCategory))
        return Self.categoryOrder.filter { present.contains($0) }
    }

    /// True when the user has limited Photos access AND at least one
    /// save in the store. Under limited access, PhotoKit only returns
    /// assets in the granted set — saves outside it render `Color.clear`
    /// and get pruned from `resolved` by the tile's onUnloadable.
    /// Surfacing a banner gives the user an explicit "go grant full
    /// access" path instead of silently shrinking their grid.
    private var hasLimitedAccess: Bool {
        photoAuth == .limited && !savedFindsStore.items.isEmpty
    }

    /// Source-app chips visible in the filter row. Mirrors
    /// `visibleCategories`: only show a chip when the user actually has
    /// saves from that app. Ordered to match `PhotoSource.allCases`.
    private var visibleSources: [PhotoSource] {
        let present = Set(vm.resolved.compactMap(\.sourceApp))
        return PhotoSource.allCases.filter { present.contains($0) && $0.isExternal }
    }

    /// Finds after the active category/source filter AND the active sort
    /// order are applied. The grid + select-mode + bulk-remove paths
    /// all read from this so a single source of truth controls what
    /// the user sees.
    ///
    /// Category and source filters are mutually exclusive — tapping a
    /// source chip clears the category and vice versa.
    ///
    /// The `.isEmpty` fallback is a belt-and-suspenders guard: when a
    /// bulk-remove drains the active filter, `vm.resolved` updates
    /// one render before the chip-visibility .onChange resets the
    /// selection to nil. Falling back to `vm.resolved` for that single
    /// frame keeps the user from seeing a blank grid.
    private var filteredFinds: [SavedFind] {
        // Kind filter sits ABOVE the category/source filter so each
        // section (Hearted / Bookmarked) renders its own scoped grid.
        let kindScoped = vm.resolved.filter { $0.effectiveKind == selectedKind }
        let base: [SavedFind]
        if let selectedCategory {
            let matching = kindScoped.filter { $0.sourceCategory == selectedCategory }
            base = matching.isEmpty ? kindScoped : matching
        } else if let selectedSource {
            let matching = kindScoped.filter { $0.sourceApp == selectedSource }
            base = matching.isEmpty ? kindScoped : matching
        } else {
            base = kindScoped
        }
        return applySort(base)
    }

    /// Sort entry point so the grid, select-mode select-all, and the
    /// bulk action all see the same order. Pure on `base` so the
    /// resolved list stays untouched (the store sort is canonical
    /// newest-first and a different sort here is a view concern only).
    private func applySort(_ base: [SavedFind]) -> [SavedFind] {
        switch sortOrder {
        case .newest:
            return base.sorted { $0.savedAt > $1.savedAt }
        case .oldest:
            return base.sorted { $0.savedAt < $1.savedAt }
        case .byCategory:
            // Use the configured category display order so categories
            // group in a meaningful sequence rather than alphabetically.
            // Within a category, fall back to newest-first.
            let order = Dictionary(uniqueKeysWithValues:
                Self.categoryOrder.enumerated().map { ($1, $0) })
            return base.sorted { lhs, rhs in
                let lhsRank = order[lhs.sourceCategory] ?? Int.max
                let rhsRank = order[rhs.sourceCategory] ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.savedAt > rhs.savedAt
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Shared BitePal canvas — cool blue-lavender gradient
            // used by every secondary surface so navigating in/out
            // of Saved Finds doesn't change the ground tone.
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
                header

                // Recovery banner — surfaces when the on-disk JSON was
                // quarantined on a load. The store publishes the flag;
                // we surface a dismissible amber pill explaining what
                // happened so the user isn't silently wiped.
                if savedFindsStore.recoveredFromCorruption {
                    RecoveryBanner(onDismiss: {
                        HapticManager.shared.selection()
                        savedFindsStore.acknowledgeRecovery()
                    })
                }

                // Limited-access banner — surfaces when the user has
                // granted `.limited` Photos access and has saves on
                // disk. Some tiles will be hidden because PhotoKit
                // can't enumerate assets outside the granted set;
                // telling the user is friendlier than silently
                // shrinking the grid.
                if hasLimitedAccess {
                    LimitedAccessBanner()
                }

                categoryChips
                content
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85),
                       value: savedFindsStore.recoveredFromCorruption)
            .animation(.spring(response: 0.32, dampingFraction: 0.85),
                       value: hasLimitedAccess)

            // Bulk-remove action bar — only when selecting AND at least
            // one tile is checked. Mirrors the spring-in pattern from
            // MediaGridView so the bar lands with the same physical
            // weight users feel in Similar / Duplicates.
            if isSelecting && !selectedFindIds.isEmpty {
                ActionBar(
                    title: "Remove \(selectedFindIds.count) from Saved",
                    buttonTitle: "Remove",
                    buttonIcon: "bookmark.slash.fill",
                    isDestructive: true
                ) {
                    showBulkRemoveConfirm = true
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Undo bar — surfaces after every Saved Finds remove (single
            // or bulk) with a 4-second window to tap Undo. Suppressed
            // while the bulk-remove action bar is up so two bottom-
            // anchored controls never fight for the same lane.
            if !pendingUndo.isEmpty && !(isSelecting && !selectedFindIds.isEmpty) {
                undoBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: pendingUndo.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedFindIds.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelecting)
        .navigationBarHidden(true)
        .task {
            photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            await vm.reload()
            hasCompletedFirstLoad = true
            // Corruption-recovery is surfaced via the persistent
            // `RecoveryBanner` above the chips, not a transient toast.
            // The banner gives the user a stable dismiss affordance
            // that calls `acknowledgeRecovery()` only on explicit tap
            // — a 1.8s toast would blink past before the user
            // registers it.
        }
        .onAppear {
            vm.startObservingLibrary()
            // Re-poll auth on every appear — the user may have flipped
            // Photos permission in Settings while we were off-screen.
            // PhotoKit doesn't publish auth changes via Combine, so a
            // manual refresh is the cleanest signal.
            photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        .onDisappear { vm.stopObservingLibrary() }
        // Leaving select mode always clears the working set. Picks up
        // the case where the user backs out via "Cancel" or selects
        // every tile then bulk-removes (which then exits select mode).
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { selectedFindIds.removeAll() }
        }
        // The grid emptying out mid-session (bulk delete consumed
        // everything, or a library change pruned the list) should drop
        // the user back to browse mode rather than stranding them in
        // an empty select state.
        .onChange(of: vm.resolved.isEmpty) { _, isEmpty in
            if isEmpty { isSelecting = false }
        }
        // If the active category disappears from the user's saves
        // (last item in it got bulk-removed, or PhotoKit pruned it)
        // we don't want to strand the grid on an empty filter — drop
        // back to All so they immediately see what's left.
        .onChange(of: visibleCategories) { _, categories in
            if let selected = selectedCategory, !categories.contains(selected) {
                selectedCategory = nil
            }
        }
        // Same fallback for source-app chips — if the user bulk-removes
        // every Snapchat save while the Snapchat chip is active, drop to
        // All instead of stranding them on a blank grid.
        .onChange(of: visibleSources) { _, sources in
            if let selected = selectedSource, !sources.contains(selected) {
                selectedSource = nil
            }
        }
        // Selections are scoped to the current chip — switching
        // filters mid-select clears the working set so a bulk-remove
        // can never silently destroy items that aren't on screen.
        .onChange(of: selectedCategory) { _, _ in
            selectedFindIds.removeAll()
        }
        .onChange(of: selectedSource) { _, _ in
            selectedFindIds.removeAll()
        }
        // Warning haptic on the bulk-remove confirm alert appearing —
        // matches the destructive-confirm pattern landed in the haptics
        // overhaul (`HapticManager.destructiveConfirm()` is the same
        // notify(.warning) primitive).
        .onChange(of: showBulkRemoveConfirm) { _, isShown in
            if isShown { HapticManager.shared.destructiveConfirm() }
        }
        .alert(
            "Remove \(selectedFindIds.count) from Saved Finds?",
            isPresented: $showBulkRemoveConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                performBulkRemove()
            }
        } message: {
            Text("This only unsaves the items. Your original photos and videos stay in Photos.")
        }
        .beeToast($toast, topInset: 110)
        .fullScreenCover(item: Binding(
            get: { previewAssetId.map(PreviewTarget.init(assetId:)) },
            set: { previewAssetId = $0?.assetId }
        )) { target in
            // Look the find up by asset id so we can hand the preview a
            // context (mediaType + sourceCategory) and an unsave path
            // straight back to the ViewModel. Falls back to no-button if
            // the find disappeared between tap and present.
            let find = vm.resolved.first { $0.assetLocalIdentifier == target.assetId }
            ZoomablePreviewOverlay(
                assetIdentifier: target.assetId,
                saveContext: find.map {
                    SavedFindContext(
                        mediaType: $0.mediaType,
                        sourceCategory: $0.sourceCategory,
                        sourceApp: $0.sourceApp
                    )
                },
                onUnsave: find.map { resolvedFind in
                    {
                        vm.remove(resolvedFind)
                        previewAssetId = nil
                        triggerUndo(for: [resolvedFind])
                    }
                },
                // Tiny "Saved from X · Y ago" line under the header so
                // the user remembers WHERE each find came from. Only
                // surfaces on previews launched from this grid; cleanup-
                // screen previews leave caption nil because the user
                // already knows where they are.
                caption: find.map { Self.previewCaption(for: $0) }
            ) {
                previewAssetId = nil
            }
        }
        .alert(
            "Remove from Saved Finds?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingRemove = nil }
            Button("Remove", role: .destructive) {
                if let find = pendingRemove {
                    vm.remove(find)
                    HapticManager.shared.impact(.light)
                    triggerUndo(for: [find])
                }
                pendingRemove = nil
            }
        } message: {
            Text("This only unsaves the item. Your original photo or video stays in Photos.")
        }
    }

    // MARK: - Kind Segmented Control

    private var kindSegmentedControl: some View {
        HStack(spacing: 6) {
            ForEach(SavedFindKind.allCases, id: \.self) { kind in
                kindTab(kind)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(Color.white.opacity(0.8))
        )
        .overlay(
            Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func kindTab(_ kind: SavedFindKind) -> some View {
        let active = selectedKind == kind
        return Button {
            HapticManager.shared.selection()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selectedKind = kind
                selectedFindIds = []
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.sfSymbol)
                    .font(.system(size: 12, weight: .bold))
                Text(kind.displayName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(active ? .white : Color(hex: "0A0A0A"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(active ? Color(hex: "1C1917") : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "0A0A0A"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(isSelecting ? selectionTitle : "Saved Finds")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "0A0A0A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .animation(.easeOut(duration: 0.15), value: isSelecting)

                Spacer()

                if vm.count > 0 {
                    headerTrailingControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Subtitle row — count on the left, hint on the right.
            // Replaces the standalone honey pill in the previous header;
            // Cal-AI hierarchy keeps numbers monochrome and leaves
            // honey for the action (Save, active chip).
            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "6B7280"))
                .padding(.horizontal, 52)  // align with title baseline (chevron 36 + 12 spacing + 4)
                .padding(.bottom, 10)

            // Hearted / Bookmarked segmented control. Two sections —
            // entries are split by `effectiveKind`, so the legacy Save
            // pill (which writes `.bookmarked`) keeps surfacing in the
            // right tab.
            kindSegmentedControl
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: filteredFinds.count)
        }
    }

    private var headerSubtitle: String {
        if isSelecting {
            return "Tap tiles to choose what to remove."
        }
        let count = filteredFinds.count
        guard count > 0 else { return "Your best discoveries from cleanup." }
        return count == 1 ? "1 saved" : "\(count) saved"
    }

    /// While selecting, the title becomes a live count. Falls back to a
    /// neutral string when nothing is selected so the header doesn't read
    /// as a destructive number on its own.
    private var selectionTitle: String {
        selectedFindIds.isEmpty ? "Select" : "\(selectedFindIds.count) selected"
    }

    /// Right-side header chrome. Browse mode: count badge + a compact
    /// "Select" pill. Select mode: "All" toggle + "Cancel". Both pills
    /// share the existing honey-amber pill treatment used for the count
    /// badge so the visual language is consistent.
    @ViewBuilder
    private var headerTrailingControls: some View {
        if isSelecting {
            HStack(spacing: 8) {
                Button(action: toggleSelectAll) {
                    // Conventional toggle labels — the bare "All / None"
                    // pair read as ambiguous (None of what? All of
                    // what?) when the pill is the sole header chrome.
                    // "Deselect All" when everything is selected,
                    // "Select All" otherwise — same wording the
                    // SimilarPhotosView / Duplicate / Screenshot pills
                    // use, so the muscle memory is consistent across
                    // every multi-select surface in the app.
                    Text(isAllSelected ? "Deselect All" : "Select All")
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.categoryHoney))
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.shared.selection()
                    isSelecting = false
                } label: {
                    Text("Cancel")
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundColor(Color(hex: "0A0A0A"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 8) {
                sortMenu

                Button {
                    HapticManager.shared.selection()
                    isSelecting = true
                } label: {
                    Text(BCLoc.select.tr)
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundColor(Color(hex: "0A0A0A"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Compact circular Menu button — pairs with the count badge in
    /// browse mode and lets the user reorder the grid without leaving
    /// the screen. Hidden in select mode so the destructive flow stays
    /// uncluttered.
    private var sortMenu: some View {
        Menu {
            ForEach(SavedFindsSortOrder.allCases, id: \.self) { order in
                Button {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        sortOrder = order
                    }
                } label: {
                    if sortOrder == order {
                        Label(order.displayName, systemImage: "checkmark")
                    } else {
                        Text(order.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(Color(hex: "0A0A0A"))
                .frame(width: 32, height: 28)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
        .accessibilityLabel("Sort, currently \(sortOrder.displayName)")
    }

    /// "All selected" is computed against the *currently visible* finds —
    /// when a category chip is active the user's mental model is "select
    /// everything I can see," not "everything in the store." Selections
    /// from a different filter stay parked in `selectedFindIds` so
    /// flipping chips is additive rather than destructive.
    private var isAllSelected: Bool {
        !filteredFinds.isEmpty && filteredFinds.allSatisfy { selectedFindIds.contains($0.id) }
    }

    private func toggleSelectAll() {
        HapticManager.shared.selection()
        let visibleIds = filteredFinds.map(\.id)
        if isAllSelected {
            selectedFindIds.subtract(visibleIds)
        } else {
            selectedFindIds.formUnion(visibleIds)
        }
    }

    private func performBulkRemove() {
        // Belt-and-suspenders: only remove finds that are *both* selected
        // AND currently visible under the active chip filter. The
        // `.onChange(of: selectedCategory)` clears selections on filter
        // flips, so this should be a no-op in practice — but if any
        // future code path leaks a cross-filter id into `selectedFindIds`
        // we want bulk-remove to refuse to silently destroy items the
        // user can't see, not relay on a single onChange to gate it.
        let visibleIds = Set(filteredFinds.map(\.id))
        let safeIds = selectedFindIds.intersection(visibleIds)
        let toRemove = vm.resolved.filter { safeIds.contains($0.id) }
        for find in toRemove {
            vm.remove(find)
        }
        selectedFindIds.removeAll()
        isSelecting = false
        triggerUndo(for: toRemove)
    }

    // MARK: - Undo bar
    //
    // Surfaces a "Removed N · Undo" pill at the bottom of the screen for
    // 4 seconds after every remove (single or bulk). Tap "Undo" → the
    // batch is restored via `vm.restore(_:)`, keeping the original ids
    // + savedAt timestamps so the grid re-positions tiles instead of
    // surfacing them as fresh saves. Auto-dismiss is tied to the
    // current batch id so a rapid second remove cleanly supersedes
    // the first bar.

    /// Stage a removed batch into the Undo bar. Schedules an auto-clear
    /// after 4s gated by `undoBatchId` so a fresh remove cancels the
    /// previous timeout.
    private func triggerUndo(for finds: [SavedFind]) {
        guard !finds.isEmpty else { return }
        pendingUndo = finds
        let batchId = UUID()
        undoBatchId = batchId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if undoBatchId == batchId {
                pendingUndo = []
            }
        }
    }

    /// Restore the staged batch back into the store and dismiss the bar.
    private func performUndo() {
        guard !pendingUndo.isEmpty else { return }
        HapticManager.shared.undoAction()
        vm.restore(pendingUndo)
        let restored = pendingUndo.count
        pendingUndo = []
        toast = BeeToast(
            message: restored == 1 ? "Restored 1 saved find" : "Restored \(restored) saved finds",
            icon: "bookmark.fill"
        )
    }

    private var undoBar: some View {
        let count = pendingUndo.count
        return HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(.white.opacity(0.92))

            Text(count == 1 ? "1 removed" : "\(count) removed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: performUndo) {
                Text("UNDO")
                    .font(.custom("Poppins-Bold", size: 12.5))
                    .tracking(0.8)
                    .foregroundColor(Color(hex: "1F1F1F"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.categoryHoney))
            }
            .buttonStyle(TilePressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous).fill(Color.black.opacity(0.86))
        )
        .overlay(
            Capsule(style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 6)
        .compositingGroup()
    }

    // MARK: - Category Chips
    //
    // Sticky row that lives between header and grid. Renders nothing
    // until the user has saves from more than one category — a single
    // category needs no filter, and an empty store is handled by the
    // empty state. While selecting, the chips remain interactive so
    // the user can scope a bulk action to a single category.

    @ViewBuilder
    private var categoryChips: some View {
        // Show the chip row when ANY scoping is possible: more than one
        // category present, OR at least one source-app chip available.
        // Empty store / single-category-no-source still hides the row.
        let totalScopes = visibleCategories.count + visibleSources.count
        if totalScopes > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(
                        title: "All",
                        isActive: selectedCategory == nil && selectedSource == nil
                    ) {
                        if selectedCategory != nil || selectedSource != nil {
                            HapticManager.shared.selection()
                            selectedCategory = nil
                            selectedSource = nil
                        }
                    }

                    // Category chips — text-only.
                    ForEach(visibleCategories, id: \.self) { category in
                        chip(
                            title: category.displayName,
                            isActive: selectedCategory == category
                        ) {
                            HapticManager.shared.selection()
                            // Re-tapping the active chip drops back to
                            // All — gives the user a one-tap escape
                            // without forcing a trip to the leading
                            // chip. Tapping any category chip clears
                            // the source filter (mutually exclusive).
                            selectedCategory = (selectedCategory == category) ? nil : category
                            selectedSource = nil
                        }
                    }

                    // Source-app chips — leading SocialSourceBadge so the
                    // user can identify Snapchat / Instagram / etc. at
                    // a glance without reading the label.
                    ForEach(visibleSources, id: \.self) { source in
                        sourceChip(
                            source: source,
                            isActive: selectedSource == source
                        ) {
                            HapticManager.shared.selection()
                            selectedSource = (selectedSource == source) ? nil : source
                            selectedCategory = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.bottom, 10)
            .animation(.easeOut(duration: 0.18), value: selectedCategory)
            .animation(.easeOut(duration: 0.18), value: selectedSource)
        }
    }

    /// Source-app chip variant — same capsule treatment as the text-only
    /// `chip` helper, but with a leading `SocialSourceBadge` glyph for
    /// fast app identification.
    private func sourceChip(
        source: PhotoSource,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SocialSourceBadge(source: source, size: 16)
                Text(source.displayName)
                    .font(.custom("Poppins-Bold", size: 12.5))
                    .foregroundColor(isActive ? .white : Color(hex: "1C1917"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? Color.categoryHoney : Color(hex: "F1F1EC"))
            )
        }
        .buttonStyle(TilePressStyle())
    }

    private func chip(
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Poppins-Bold", size: 12.5))
                .foregroundColor(isActive ? .white : Color(hex: "1C1917"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    // Flat capsule, no gradient, no border. Honey only
                    // on the active state — every other chip is neutral
                    // ink on a soft warm-cream surface (Cal-AI tonal).
                    Capsule().fill(isActive ? Color.categoryHoney : Color(hex: "F1F1EC"))
                )
                .scaleEffect(isActive ? 1.0 : 1.0)
        }
        .buttonStyle(TilePressStyle())
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if (vm.isLoading && vm.resolved.isEmpty) || !hasCompletedFirstLoad {
            // Neutral loading state during first hydration. Without
            // this gate the empty state flashes for one frame between
            // `.task` firing and `vm.reload()` populating `resolved`,
            // which reads as "your saves are gone" to a user who has
            // dozens of them on disk.
            Spacer()
            ProgressView().tint(.categoryHoney)
            Spacer()
        } else if vm.resolved.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            // Looping Save-pill demo communicates the mechanic faster
            // than copy ever could — the user sees the pill flip in
            // real time and knows exactly what affordance to look for.
            SavePillLoopDemo()
                .padding(.bottom, 4)

            Text("Save your first find")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "0A0A0A"))

            Text("Tap **Save** while reviewing photos in Duplicates, Similar Photos, Screenshots or any video category to bookmark them here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "6B7280"))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(filteredFinds) { find in
                    SavedFindTile(
                        find: find,
                        isSelecting: isSelecting,
                        isSelected: selectedFindIds.contains(find.id),
                        onTap: { handleTileTap(find) },
                        onRemove: { pendingRemove = find },
                        // PhotoKit can't resolve this asset — hide the
                        // tile but DON'T delete the bookmark. Under
                        // `.limited` Photos access the asset may exist
                        // outside the granted set, and `vm.remove`
                        // would nuke it from disk permanently. `dropFromResolvedOnly`
                        // is the view-only prune: tile disappears, store
                        // is untouched, next reload with full access
                        // resurrects it.
                        onUnloadable: { vm.dropFromResolvedOnly(find) }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, isSelecting && !selectedFindIds.isEmpty ? 140 : 120)
            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: filteredFinds.map(\.id))
        }
        .refreshable {
            await vm.reload()
        }
    }

    /// Builds the "Saved from X · Y ago" line for the preview overlay.
    /// Pulled out as a static so it can run before the closure that
    /// owns `find` evaluates — keeps the `caption:` argument site clean.
    ///
    /// When the asset has app provenance (Snapchat / Instagram / etc.)
    /// it leads the line so users instantly see "where this came from"
    /// before the cleanup-category context.
    private static func previewCaption(for find: SavedFind) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        let relative = fmt.localizedString(for: find.savedAt, relativeTo: Date())
        let prefix: String
        if let source = find.sourceApp, source.isExternal {
            prefix = "Saved from \(source.displayName) · \(find.sourceCategory.displayName)"
        } else {
            prefix = "Saved from \(find.sourceCategory.displayName)"
        }
        return "\(prefix) · \(relative)"
    }

    /// In select mode, tile tap toggles the selection set. Outside select
    /// mode, it opens the preview the same way it always did.
    private func handleTileTap(_ find: SavedFind) {
        if isSelecting {
            HapticManager.shared.selection()
            if selectedFindIds.contains(find.id) {
                selectedFindIds.remove(find.id)
            } else {
                selectedFindIds.insert(find.id)
            }
        } else {
            HapticManager.shared.selection()
            previewAssetId = find.assetLocalIdentifier
        }
    }
}

// MARK: - Saved Find Tile

private struct SavedFindTile: View {
    let find: SavedFind
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    /// Called by `PhotoThumbnailView` when PhotoKit can't resolve the
    /// underlying asset — wired by the parent to drop the find from the
    /// resolved set so deleted-asset cells don't leave invisible ghost
    /// tiles in the grid (previously rendered as `Color.clear` and
    /// looked like missing data).
    let onUnloadable: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                PhotoThumbnailView(
                    assetIdentifier: find.assetLocalIdentifier,
                    size: CGSize(width: 240, height: 240),
                    onUnloadable: onUnloadable
                )
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Selection-mode dim — fades in as a thin ink veil so a
                // selected tile reads as actively included in the
                // pending destructive action.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(isSelected ? 0.32 : 0))
                    .allowsHitTesting(false)

                if find.mediaType == .video {
                    // Compact play glyph in the corner. No "Video" text —
                    // the play triangle reads instantly and frees the
                    // tile's visual budget for the photo itself.
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .padding(8)
                }

                // Top-right corner stack: source-app badge always shown
                // (renders nothing for nil / .camera), selection chip drops
                // below it when the grid enters select mode. Same pattern
                // as MediaGridView+Grid so users see consistent provenance
                // signals across both surfaces.
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Spacer()
                        SocialSourceBadge(source: find.sourceApp, size: 20)
                    }
                    if isSelecting {
                        HStack {
                            Spacer()
                            selectionChip
                        }
                    }
                    Spacer()
                }
                .padding(8)
                // Always pass taps through to the parent Button — the chip
                // is decorative; selection toggles via the host tile tap.
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        // Border shifts white (resting) → black (picked
                        // for removal). Replaces the previous gold
                        // honey selection ring; reads cleaner against
                        // the photo content and ties to the new red
                        // selection chip below for a single high-
                        // contrast destructive-action language.
                        isSelected ? Color.black : Color.white,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        // Cal-AI clean press feedback via ButtonStyle (no parallel
        // DragGesture — that pattern dropped taps inside the scroll
        // view on tightly-packed grids).
        .buttonStyle(TilePressStyle())
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.18), value: isSelecting)
        // Suppress the per-tile context menu while selecting — the user
        // is already in a bulk destructive flow; firing a single-item
        // confirm sheet on long-press would be confusing.
        .contextMenu {
            if !isSelecting {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Saved Finds", systemImage: "bookmark.slash")
                }
            }
        }
    }

    private var selectionChip: some View {
        ZStack {
            Circle()
                // Selection chip turns RED on pick — replaces the gold
                // honey treatment. Red signals "marked for removal"
                // unambiguously and matches the destructive CTA at the
                // bottom of the screen.
                .fill(isSelected ? Color.destructive : Color.black.opacity(0.42))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.6 : 0.85), lineWidth: 1.5)
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 1)
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                .interactiveSpring(response: 0.22, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

// MARK: - Save pill loop demo
//
// Empty-state visual aid: a non-interactive Save pill that flips
// `Save → Saved` and back every ~2.4 seconds, mirroring exactly what
// the real SaveFindButton looks like on a media surface. New users
// learn the affordance by recognition rather than by reading prose,
// which is what Cal AI / Granola / Headway-tier onboarding does.

private struct SavePillLoopDemo: View {
    @State private var isSaved: Bool = false
    @State private var bounceTrigger: Int = 0

    private let cycle: TimeInterval = 2.4

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12.5, weight: .bold))
                .symbolEffect(.bounce, value: bounceTrigger)

            Text(isSaved ? "Saved" : "Save")
                .font(.custom("Poppins-Bold", size: 12.5))
                .tracking(0.15)
        }
        .foregroundStyle(isSaved ? .white : Color(hex: "1C1917"))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(
                isSaved
                    ? AnyShapeStyle(Color.categoryHoney)
                    : AnyShapeStyle(Color.white)
            )
        )
        .overlay(
            Capsule(style: .continuous).stroke(
                isSaved ? Color.white.opacity(0.18) : Color.black.opacity(0.06),
                lineWidth: 0.6
            )
        )
        .shadow(
            color: Color.black.opacity(isSaved ? 0.10 : 0.06),
            radius: 8, x: 0, y: 3
        )
        .scaleEffect(isSaved ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.28), value: isSaved)
        .onAppear {
            startLoop()
        }
    }

    private func startLoop() {
        Task { @MainActor in
            // Initial pause so the user can register the unsaved state
            // before the first flip.
            try? await Task.sleep(nanoseconds: 700_000_000)
            while !Task.isCancelled {
                isSaved.toggle()
                if isSaved { bounceTrigger &+= 1 }
                try? await Task.sleep(nanoseconds: UInt64(cycle * 1_000_000_000))
            }
        }
    }
}

// MARK: - Recovery banner
//
// Surfaces above the chips when `SavedFindsStore.recoveredFromCorruption`
// is true. Replaces the previous transient toast — a 1.8s toast was too
// fast for the user to register "your bookmarks were quarantined";
// a dismissible amber banner stays put until they acknowledge.

private struct RecoveryBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "B45309"))

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved Finds recovered")
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundColor(Color(hex: "0A0A0A"))
                Text("A storage error meant we had to start fresh. Some bookmarks may be missing.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "6B7280"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "6B7280"))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "FEF3C7"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "B45309").opacity(0.18), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Limited-access banner
//
// Surfaces above the chips when the user has granted `.limited` Photos
// access AND has saved finds on disk. Without this, tiles outside the
// granted set just vanish silently — the user reads it as "my saves
// disappeared" rather than "the OS isn't letting BeeClean see them."

private struct LimitedAccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "1D4ED8"))

            VStack(alignment: .leading, spacing: 2) {
                Text("Some saves are hidden")
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundColor(Color(hex: "0A0A0A"))
                Text("BeeClean only sees photos you selected. Grant full access to see all your saves.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "6B7280"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                HapticManager.shared.selection()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open")
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: "1D4ED8")))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "DBEAFE"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "1D4ED8").opacity(0.16), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Sort order
//
// Drives the SavedFindsView Sort menu. `byCategory` uses the static
// category order declared on `SavedFindsView` so groupings read in
// the same priority the chip row uses (Duplicates → Photos → Videos).

enum SavedFindsSortOrder: String, CaseIterable, Hashable {
    case newest
    case oldest
    case byCategory

    var displayName: String {
        switch self {
        case .newest:     return "Newest first"
        case .oldest:     return "Oldest first"
        case .byCategory: return "By category"
        }
    }
}
