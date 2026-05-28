import Foundation

// MARK: - Email Service
@MainActor
class EmailService: ObservableObject {
    static let shared = EmailService()
    
    @Published var categories: [GmailCategory] = []
    @Published var senders: [EmailSender] = []
    @Published var totalSenderEmails: Int = 0
    @Published var totalEmailCount: Int = 0

    // MARK: - Message Cache (category.id -> cached result)
    struct CachedMessages: Equatable {
        var messages: [EmailMessage]
        var nextPageToken: String?
        var filteredCount: Int?
        var fetchedAt: Date
    }
    @Published var messageCache: [String: CachedMessages] = [:]
    var prefetchTasks: [String: Task<Void, Never>] = [:]
    /// Background polling tasks that keep the message cache hot while the
    /// backend's wave-based scan fills in. Keyed by category id; one task
    /// per category at a time so we don't pile up requests.
    var realtimePollTasks: [String: Task<Void, Never>] = [:]

    func cachedMessages(for categoryID: String) -> CachedMessages? {
        messageCache[categoryID]
    }

    /// Prefetch all categories in the background — lightweight (25 msgs each, staggered).
    /// Just enough for instant first-screen render. Avoids hammering Gmail API.
    func prefetchAllCategories(scope: String) {
        // Single coordinated task to stagger requests and avoid rate limiting
        let categoriesToPrefetch = categories.filter { cat in
            if let cached = messageCache[cat.id], Date().timeIntervalSince(cached.fetchedAt) < 120 { return false }
            if prefetchTasks[cat.id] != nil { return false }
            return true
        }
        guard !categoriesToPrefetch.isEmpty else { return }

        for category in categoriesToPrefetch {
            let id = category.id
            prefetchTasks[id] = Task { [weak self] in
                guard let self else { return }
                let result = await self.fetchMessages(category: id, scope: scope, filters: nil, maxResults: 25)
                if let existing = self.messageCache[id], existing.messages.count > result.messages.count {
                    self.prefetchTasks[id] = nil
                    return
                }
                if !result.messages.isEmpty {
                    self.messageCache[id] = CachedMessages(
                        messages: result.messages,
                        nextPageToken: result.nextPageToken,
                        filteredCount: result.filteredCount,
                        fetchedAt: Date()
                    )
                }
                self.prefetchTasks[id] = nil
            }
        }
    }

    /// Cancel any in-flight background prefetches. Call this when the user
    /// leaves the Email flow (tab switch, navigation pop) so pending Gmail
    /// API fetches don't keep eating CPU + network after the UI is gone.
    /// Without this, the tab-switch animation has to compete with N
    /// concurrent network tasks and feels laggy.
    func cancelAllPrefetches() {
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
        for (_, task) in realtimePollTasks {
            task.cancel()
        }
        realtimePollTasks.removeAll()
        scanningCategoryIDs.removeAll()
    }

    /// Refresh a single category's cache silently in the background.
    /// Will NOT overwrite a cache that has been extended by pagination (more messages than a single page).
    func refreshCategorySilently(categoryID: String, scope: String) {
        prefetchTasks[categoryID]?.cancel()
        prefetchTasks[categoryID] = Task { [weak self] in
            guard let self else { return }
            let result = await self.fetchMessages(category: categoryID, scope: scope, filters: nil, maxResults: 50)
            if let existing = self.messageCache[categoryID], existing.messages.count > result.messages.count {
                self.prefetchTasks[categoryID] = nil
                return
            }
            if !result.messages.isEmpty {
                self.messageCache[categoryID] = CachedMessages(
                    messages: result.messages,
                    nextPageToken: result.nextPageToken,
                    filteredCount: result.filteredCount,
                    fetchedAt: Date()
                )
            }
            self.prefetchTasks[categoryID] = nil
        }
    }

    /// Invalidate cache (called after delete/trash operations).
    func invalidateCache(categoryID: String? = nil) {
        if let id = categoryID {
            messageCache.removeValue(forKey: id)
        } else {
            messageCache.removeAll()
        }
    }
    @Published var isLoading = false
    @Published var isSendersLoading = false
    @Published var error: String?

    /// Categories whose first-page message cache is currently being filled
    /// by the backend's wave-based progressive scan. Views observe this to
    /// show a live "Scanning..." indicator while data streams in. Mirrors
    /// the `scanning` flag in /senders polling — but per-category.
    @Published var scanningCategoryIDs: Set<String> = []
    /// True while /email/categories is itself scanning (count revalidation).
    @Published var isCategoriesScanning: Bool = false

    /// The current kept-sender set. Mirrors `LocalKeptStore.shared.emailSenders`
    /// so Views that observe `EmailService` still get change notifications.
    /// Lives on the main class because Swift extensions cannot hold stored
    /// properties — read/write helpers stay in `+Messages.swift`.
    @Published var keptSenderEmails: Set<String> = []

    /// Tracks the last known Gmail historyId for incremental sync. Lives on
    /// the main class — read/written by helpers in `+API.swift`.
    @Published var lastHistoryId: String?
    
    let baseURL = BackendConfig.baseURL
    
    init() {
        // Hydrate kept-sender set from on-device storage so the very first
        // /email/senders response is already filtered.
        keptSenderEmails = LocalKeptStore.shared.ids(in: .emailSenders)
    }
    
}
