import SwiftUI
import Contacts
import RevenueCatUI

// MARK: - Contact List View
struct ContactListView: View {
    let category: ContactCategory
    @ObservedObject var viewModel = ContactsViewModel.shared
    @Environment(\.dismiss) var dismiss

    @State var selectedContacts: Set<String> = []
    @State var searchText = ""
    @State var showDeleteConfirm = false
    @State var showMergeAllConfirm = false
    @State var isDeleting = false
    @State var isMergingAll = false
    @State var mergeAllResult: (merged: Int, deleted: Int)?
    @State var selectedForDetail: AppContact?
    @State var shareURL: URL?
    @State var showShareSheet = false
    @State var showMergePreview = false
    @State var showFeatureGate = false
    @State var showPaywall = false
    @StateObject var actionFlow = ActionFlowCoordinator()
    @State var featureGateAction: FeatureGateAction = .delete
    @State var displayLimit: Int = 500
    @State var isLoadingMore = false
    /// A-Z section jump target. Lives in the main struct body because
    /// `@State` is a stored property and Swift extensions can't hold them.
    @State var scrollTarget: String?

    static let batchSize = 500

    // Cached lists. Body previously re-ran flatMap + viewModel.search() on
    // every read, and read `allCategoryContacts` / `contacts` / `hasMore`
    // 4–6× per layout pass — for a 1000-contact library that's 5+ filter
    // walks per scroll frame. Now we recompute only when an input
    // (category source, searchText, displayLimit) actually changes, via
    // `.task(id: cacheInputs)` below.
    @State var allCategoryContacts: [AppContact] = []
    @State var contacts: [AppContact] = []

    /// Composite identity of every input that drives `allCategoryContacts`
    /// + `contacts`. Cheap to compute (count + length comparison) and used
    /// as the `.task(id:)` key so a single helper recomputes both caches
    /// the moment any input changes.
    var cacheInputs: String {
        let baseCount: Int
        switch category {
        case .duplicates: baseCount = viewModel.duplicateGroups.count
        case .incomplete: baseCount = viewModel.incompleteContacts.count
        case .backups: baseCount = 0
        case .all: baseCount = viewModel.allContacts.count
        }
        return "\(baseCount)|\(displayLimit)|\(searchText)"
    }

    var hasMore: Bool {
        contacts.count < allCategoryContacts.count
    }

    func recomputeContactCaches() {
        let base: [AppContact]
        switch category {
        case .duplicates:
            base = viewModel.duplicateGroups.flatMap { $0.contacts }
        case .incomplete:
            base = viewModel.incompleteContacts
        case .backups:
            base = []
        case .all:
            base = viewModel.allContacts
        }

        if searchText.isEmpty {
            allCategoryContacts = base
            contacts = Array(base.prefix(displayLimit))
        } else {
            let filtered = viewModel.search(query: searchText, in: base)
            allCategoryContacts = filtered
            // When searching, show every result regardless of displayLimit —
            // search hits are usually small enough that batching adds
            // friction without a perf win.
            contacts = filtered
        }
    }

    func loadMore() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                displayLimit += Self.batchSize
            }
            isLoadingMore = false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Bitepal cool-gray gradient — same canvas as ContactsView
                // and the Compress / Email tabs so navigating in stays
                // continuous.
                BitepalCanvas()

                VStack(spacing: 0) {
                    // Custom header — Bitepal lavender-pill back button +
                    // matching Select All pill so the chrome reads as one
                    // family with Settings / Compress / Email.
                    HStack {
                        Button {
                            // Eager nav-bar release before dismiss so the
                            // bar is rendered BEFORE the fullScreenCover
                            // slide-down animation kicks in. The
                            // `.hidesBottomNavBar()` modifier's
                            // `.task` cancellation only fires AFTER the
                            // dismiss animation completes (~0.35s), which
                            // gave the user a visible blank where the bar
                            // should have been every time they exited
                            // Duplicates / Incomplete / All / Backups.
                            // The modifier's later release that fires
                            // when the view actually leaves the
                            // hierarchy is harmless — releaseHide()
                            // clamps at zero.
                            BottomNavBarVisibility.shared.releaseHide()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: "1C1917"))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color(hex: "EEEDF3")))
                                .contentShape(Rectangle())
                        }

                        Spacer()

                        toolbarSelectAllButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    // Big bold title + smart count
                    //
                    // Subtitle pattern mirrors the photo cleanup header:
                    //   • idle:        "358 Contacts" / "28 Contacts"
                    //   • selecting:   "358 Contacts · 257 selected"
                    // The "selected" suffix is highlighted in red so the user
                    // sees how much will be affected by the bottom CTA at
                    // a glance — same visual language as Similar Photos.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.custom("Poppins-Bold", size: 30))
                            .foregroundColor(Color(hex: "1C1917"))

                        HStack(spacing: 6) {
                            Text(category == .duplicates && !viewModel.duplicateGroups.isEmpty
                                 ? "\(viewModel.duplicateCount) duplicate\(viewModel.duplicateCount == 1 ? "" : "s") in \(viewModel.duplicateGroupCount) group\(viewModel.duplicateGroupCount == 1 ? "" : "s")"
                                 : "\(allCategoryContacts.count) contact\(allCategoryContacts.count == 1 ? "" : "s")")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "A1A1AA"))

                            if !selectedContacts.isEmpty {
                                Text("·")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "C8C8CC"))
                                Text("\(selectedContacts.count) selected")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "DC2626"))
                                    .contentTransition(.numericText(countsDown: false))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Content — duplicates use the same letter-badge dictionary
                    // layout as Incomplete so the two screens look and scan
                    // identically. Group-aware merge logic still works because
                    // `viewModel.duplicateGroups` is the source of truth for
                    // merge preview; the UI just selects contacts individually.
                    if viewModel.isLoading && contacts.isEmpty {
                        loadingView
                    } else if contacts.isEmpty {
                        emptyView
                    } else if category == .duplicates && searchText.isEmpty {
                        // Duplicates render as group sections so each
                        // cluster shows WHO matched WHOM and on WHICH
                        // phone — the per-group "Select All" + matched-
                        // phone highlight only make sense in this layout.
                        // Falls back to the flat scroll list when the
                        // user is searching (per-group context loses
                        // meaning across an arbitrary text filter).
                        duplicateGroupList
                    } else if (category == .all || category == .incomplete) && searchText.isEmpty {
                        dictionaryContactList
                    } else {
                        contactScrollList
                    }
                }

                // Pinned bottom CTA — mirrors the photo cleanup design.
                // For duplicates we still surface "Combine Selected" above
                // the destructive delete so the merge path stays one tap
                // away. The CTA sits inside a backdrop strip that masks
                // the scroll content underneath — without the strip, the
                // last contact rows visibly bled UNDER the floating
                // pill (user reported "S" letter peeking out below the
                // button), which read as broken layering.
                if !selectedContacts.isEmpty && !isDeleting {
                    VStack(spacing: 0) {
                        Spacer()
                        bottomCTABackdrop {
                            if category == .duplicates {
                                mergePreviewBar
                            } else {
                                primaryDeleteCTA
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 38)
                                    .padding(.top, 12)
                            }
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
        }
        .alert("Delete \(selectedContacts.count) Contact\(selectedContacts.count == 1 ? "" : "s")?",
               isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                // Routed through the viewModel's stored Task instead of
                // a bare `Task { … }`. Sheet dismissal mid-delete now
                // calls `viewModel.cancelInFlight()` from .onDisappear,
                // so a 1000-contact delete pass can't keep firing
                // `loadContacts` after the user navigates away.
                viewModel.runBulk { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the selected contacts from your device. This cannot be undone.")
        }
        .sheet(item: $selectedForDetail) { contact in
            ContactDetailView(contact: contact)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .fullScreenCover(isPresented: $showMergePreview) {
            // `.fullScreenCover` not `.sheet` — sheets on iOS 16+ paint
            // a `.regularMaterial` system background that shows through
            // the BitepalCanvas, which the user spotted as a hard
            // light/dark color split at the bottom of the empty-state
            // and merge-preview screens. fullScreenCover gives the
            // view the whole screen including all safe areas, so the
            // canvas extends edge-to-edge.
            MergePreviewView(
                groups: viewModel.duplicateGroups.filter { group in
                    group.contacts.contains { selectedContacts.contains($0.id) }
                },
                // Bind, don't copy — see MergePreviewView for the
                // selection-drift bug this binding closes.
                selectedIds: $selectedContacts,
                onMerge: {
                    // Build the per-group selection map the new partial-
                    // merge API expects, then route through it.
                    var map: [String: Set<String>] = [:]
                    for group in viewModel.duplicateGroups {
                        let inGroup = Set(group.contacts.map(\.id))
                            .intersection(selectedContacts)
                        if inGroup.count >= 2 {
                            map[group.id] = inGroup
                        }
                    }
                    let result = await viewModel.mergeSelectedContactsByGroup(map)
                    viewModel.pruneSelection(&selectedContacts)
                    return result
                }
            )
        }
        .alert("Merge All \(viewModel.duplicateGroups.count) Groups?", isPresented: $showMergeAllConfirm) {
            Button("Merge All", role: .destructive) {
                // See the delete branch above — same rationale. Bulk
                // merges over a 1000-contact address book can run for
                // 10+ seconds; we don't want a sheet dismiss to orphan
                // the work or to leave a half-finished CNSaveRequest
                // writing back through @Published bindings.
                viewModel.runBulk { await performMergeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will keep the first contact in each duplicate group and merge info from the others into it. The duplicates will be permanently deleted.")
        }
        // `.preferredColorScheme` only takes effect on the *outermost*
        // view of a presentation. Pair it with `.environment(\.colorScheme, .light)`
        // so any descendant reading `@Environment(\.colorScheme)`
        // (BitepalCanvas's gradient stops, GlassPanel's material tint,
        // contactGlass border opacity, etc.) sees `.light` directly
        // instead of inheriting the system's dark mode through the
        // fullScreenCover boundary. Without this pair, the user's
        // device-level Dark Mode setting bled into the cover and the
        // whole screen rendered as the dark navy in their screenshot.
        .sheet(isPresented: $showFeatureGate) {
            GateCoordinator(
                config: .config(for: .contacts),
                selectedCount: selectedContacts.count,
                onActionApproved: { _ in
                    // Gate approved — proceed to the gated action
                    if featureGateAction == .merge {
                        showMergePreview = true
                    } else {
                        showDeleteConfirm = true
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
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .swipeToDismiss()
        .hidesBottomNavBar()
        // Single recompute trigger keyed on the composite of every cache
        // input. Body reads `allCategoryContacts` / `contacts` / `hasMore`
        // many times per layout pass — recomputing only when this string
        // identity actually changes drops a 1000-contact list from N
        // filter walks per scroll frame to one walk per real change.
        .task(id: cacheInputs) {
            recomputeContactCaches()
        }
        .onDisappear {
            // Sheet dismissed — kill any in-flight bulk merge / delete
            // routed through `viewModel.runBulk(_:)`. The user gets back
            // to whatever surface they navigated to with a clean
            // @Published state instead of late-arriving writes from a
            // CNSaveRequest that completed after we left.
            viewModel.cancelInFlight()
        }
    }

}

// MARK: - Feature Gate Action
enum FeatureGateAction {
    case delete, merge
}

// MARK: - ContactListView: Search + Stats
// MARK: - ContactListView: Actions
extension ContactListView {

    // MARK: - Actions
    func performDelete() async {
        isDeleting = true
        let success = await viewModel.deleteContacts(ids: selectedContacts)
        isDeleting = false
        if success {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedContacts.removeAll()
            }
        } else {
            viewModel.pruneSelection(&selectedContacts)
        }
    }

    func performMergeAll() async {
        let groupCount = viewModel.duplicateGroups.count
        await actionFlow.execute(section: .contacts, actionType: .merge, itemCount: groupCount) {
            let result = await viewModel.mergeAll()
            viewModel.pruneSelection(&selectedContacts)
            return ActionResult(
                section: .contacts, actionType: .merge,
                itemsProcessed: result.merged, bytesFreed: nil,
                bytesSaved: nil, originalBytes: nil, compressedBytes: nil,
                timestamp: Date(),
                breakdown: ["deleted": result.deleted],
                topSenders: nil
            )
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Contact Avatar Image
//
// Decodes thumbnail JPEG/PNG data ONCE off the main thread instead of
// re-decoding on every body re-render. The previous inline
// `UIImage(data:)` ran on the main thread for every visible contact row
// and re-fired whenever the parent re-rendered (selection, filter, etc.),
// causing scroll-stutter on long contact lists.
struct ContactAvatarImage: View {
    let data: Data
    let size: CGFloat
    @State var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: size, height: size)
            }
        }
        .task(id: data) {
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            await MainActor.run { self.image = decoded }
        }
    }
}

#Preview("Duplicates") {
    ContactListView(category: .duplicates)
        .preferredColorScheme(.light)
}

#Preview("All Contacts") {
    ContactListView(category: .all)
        .preferredColorScheme(.light)
}

#Preview("Incomplete") {
    ContactListView(category: .incomplete)
        .preferredColorScheme(.light)
}
