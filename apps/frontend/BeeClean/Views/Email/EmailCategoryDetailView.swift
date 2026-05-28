import SwiftUI
import RevenueCatUI

// MARK: - Email Category Detail View
struct EmailCategoryDetailView: View {
    let category: GmailCategory
    let scope: String
    let initialFilters: EmailFilters

    @ObservedObject var emailService = EmailService.shared
    @StateObject var undoMgr = EmailUndoManager()
    @State var messages: [EmailMessage] = []
    @State var isLoading = false
    @State var isLoadingMore = false
    /// True while `loadAllPages()` is draining every page in the background.
    /// Scroll-triggered `loadMore()` calls suppress themselves while this is
    /// set, so they don't race with the drainer and force it into the
    /// same-token bail (the bug that capped filtered queries at 201).
    @State var isDrainingAllPages = false
    @State var errorMessage: String?
    @State var selectedMessages: Set<String> = []
    @State var isDeleting = false
    @State var selectedEmailForDetail: EmailMessage?
    @State var nextPageToken: String?
    @State var showFilters = false
    @State var filters: EmailFilters
    @State var totalEstimate: Int
    @State var filteredCount: Int? = nil
    @State var lastDeletedMessages: [EmailMessage] = []
    @State var searchText: String = ""
    @State var showQuickClean = false
    @State var showFeatureGate = false
    @State var showPaywall = false
    @StateObject var actionFlow = ActionFlowCoordinator()
    @State var scrollProgress: CGFloat = 0
    @State var needsSignIn: Bool = false
    @State var isSigningIn: Bool = false
    @StateObject var quickCleanVM: QuickCleanViewModel
    @Environment(\.dismiss) var dismiss

    init(category: GmailCategory, scope: String = "inbox", initialFilters: EmailFilters = EmailFilters()) {
        self.category = category
        self.scope = scope
        self.initialFilters = initialFilters
        _filters = State(initialValue: initialFilters)
        // Seed the total from the prefetched category count so the Quick
        // Clean CTA renders on the first frame with real numbers — no
        // layout jump when messages finish loading.
        _totalEstimate = State(initialValue: category.count)
        _quickCleanVM = StateObject(wrappedValue: QuickCleanViewModel(category: category, scope: scope))
    }

    var categoryDisplayName: String {
        category.name == "Social" ? "Social Media" : category.name
    }

    var categoryColor: Color { category.tintColor }

    var hasActiveFilters: Bool {
        filters.olderThan != nil ||
        filters.readOnly ||
        filters.unreadOnly ||
        // `excludeStarred` defaults to TRUE in `EmailFilters` — meaning
        // starred mails are protected by default. The user toggling
        // "Delete starred mails" ON sets it to FALSE, which IS a real
        // filter change and must bypass the cached (default-protected)
        // results. Without this clause, the toggle had no observable
        // effect because `loadMessages` returned the cached list early.
        !filters.excludeStarred ||
        !filters.senderContains.isEmpty ||
        !filters.subjectContains.isEmpty ||
        filters.hasAttachments != nil ||
        filters.sizeFilter != .any ||
        !filters.excludeKeywords.isEmpty ||
        !filters.targetKeywords.isEmpty
    }

    /// Cached filtered list. Recomputed on `.onChange` of `messages` or
    /// `searchText` only — previously the computed property re-filtered
    /// + 4× `.lowercased()` per render, and scroll progress changes were
    /// re-firing it dozens of times per second.
    @State var visibleMessages: [EmailMessage] = []

    /// Cached pagination trigger Set. Was rebuilt inside `ForEach.onAppear`
    /// on every scroll — now updated only when `messages` actually changes.
    @State var paginationTriggerIds: Set<String> = []

    /// In-flight search task. Cancelled on every keystroke so a 1000-message
    /// inbox doesn't fire 5 concurrent .lowercased() walks while the user
    /// types "promo" — only the latest debounce-window winner runs to
    /// completion.
    @State var searchTask: Task<Void, Never>?

    func recomputeVisibleMessages() {
        searchTask?.cancel()

        // Empty query → instant assign on main, no background hop. Keeps
        // the "clear search" UX snappy.
        if searchText.isEmpty {
            visibleMessages = messages
            return
        }

        // Snapshot the inputs so the off-main filter sees a stable view of
        // the data even if `messages` mutates while we're filtering.
        let query = searchText
        let snapshot = messages

        searchTask = Task {
            // 150ms debounce — five keystrokes in 100ms only fire ONE
            // filter pass instead of five.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let filtered: [EmailMessage] = await Task.detached(priority: .userInitiated) {
                let q = query.lowercased()
                return snapshot.filter {
                    $0.senderName.lowercased().contains(q) ||
                    $0.senderEmail.lowercased().contains(q) ||
                    $0.subject.lowercased().contains(q) ||
                    $0.snippet.lowercased().contains(q)
                }
            }.value

            guard !Task.isCancelled else { return }
            visibleMessages = filtered
        }
    }

    func recomputePaginationTriggers() {
        paginationTriggerIds = messages.count > 10
            ? Set(messages.suffix(10).map(\.id))
            : Set(messages.map(\.id))
    }

    var body: some View {
        ZStack {
            glassBackdrop

            VStack(spacing: 0) {
                headerSection

                ZStack {
                    if isLoading {
                        loadingSkeleton
                            .transition(.opacity)
                    } else if let error = errorMessage {
                        errorState(error)
                            .transition(.opacity)
                    } else if messages.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        emailList
                            .transition(.opacity)
                            .overlay(alignment: .trailing) {
                                if messages.count > 15 {
                                    emailScrollScrubber
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
            }

            // Delete bar
            if !selectedMessages.isEmpty && !isLoading {
                VStack {
                    Spacer()
                    CategoryDetailDeleteBar(
                        selectedCount: selectedMessages.count,
                        isDeleting: isDeleting,
                        onDelete: {
                            if SubscriptionService.shared.isPro {
                                let count = selectedMessages.count
                                Task {
                                    await actionFlow.execute(section: .email, actionType: .clean, itemCount: count) {
                                        await deleteSelectedMessages()
                                        return ActionResult(
                                            section: .email, actionType: .clean,
                                            itemsProcessed: count, bytesFreed: nil,
                                            bytesSaved: nil, originalBytes: nil, compressedBytes: nil,
                                            timestamp: Date(),
                                            breakdown: [category.name: count],
                                            topSenders: nil
                                        )
                                    }
                                }
                            } else {
                                showFeatureGate = true
                            }
                        },
                        onDeselect: { withAnimation(.easeOut(duration: 0.2)) { selectedMessages.removeAll() } }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        }
        .animation(.easeOut(duration: 0.2), value: selectedMessages.isEmpty)
        .navigationBarHidden(true)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
        .undoToast(undoMgr)
        // Keep the cached `visibleMessages` and `paginationTriggerIds`
        // in sync with their inputs. Recomputed only on actual change,
        // not on every body render — fixes scroll jank where the prior
        // computed properties ran filter+lowercased on every tick.
        .onChange(of: messages) { _, _ in
            recomputeVisibleMessages()
            recomputePaginationTriggers()
        }
        .onChange(of: searchText) { _, _ in
            recomputeVisibleMessages()
        }
        .onAppear {
            recomputeVisibleMessages()
            recomputePaginationTriggers()
        }
        .sheet(isPresented: $showFeatureGate) {
            GateCoordinator(
                config: .config(for: .email),
                selectedCount: selectedMessages.count,
                onActionApproved: { _ in
                    let count = selectedMessages.count
                    Task {
                        await actionFlow.execute(section: .email, actionType: .clean, itemCount: count) {
                            await deleteSelectedMessages()
                            return ActionResult(
                                section: .email, actionType: .clean,
                                itemsProcessed: count, bytesFreed: nil,
                                bytesSaved: nil, originalBytes: nil, compressedBytes: nil,
                                timestamp: Date(),
                                breakdown: [category.name: count],
                                topSenders: nil
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
        .sheet(isPresented: $showFilters) {
            FiltersView(
                filters: $filters,
                categoryHint: categoryDisplayName,
                categoryTotal: totalEstimate
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onDisappear { Task { await loadMessages() } }
        }
        .fullScreenCover(isPresented: $showQuickClean) {
            QuickCleanSwipeView(vm: quickCleanVM)
        }
        .navigationDestination(item: $selectedEmailForDetail) { message in
            EmailDetailView(message: message, categoryName: categoryDisplayName)
        }
        .task {
            // Keep the estimate in sync if the category count changes while
            // the detail view is open (e.g. the category list refreshed).
            if category.count > totalEstimate {
                totalEstimate = category.count
            }
            await loadMessages()
        }
        // Auto-refresh removed: the user explicitly asked for "stay loaded,
        // no refresh once email is loaded". Counts and message lists update
        // only on first load, on pull-to-refresh, and after explicit user
        // actions (delete, mark-read). The 60-second silent refresh that
        // used to live here was the source of mid-scroll list shuffling
        // and unsolicited list reloads when returning from another tab.
        .onChange(of: emailService.messageCache[category.id]?.fetchedAt) { _, _ in
            // Lightweight: only fires when THIS category's cache timestamp changes.
            // No full dictionary diffing — just compares one optional Date.
            guard !hasActiveFilters,
                  let cached = emailService.messageCache[category.id],
                  cached.messages.count >= messages.count else { return }
            if cached.messages.count != messages.count ||
               cached.messages.first?.id != messages.first?.id {
                messages = cached.messages
                nextPageToken = cached.nextPageToken
                filteredCount = cached.filteredCount
            }
        }
    }

}
