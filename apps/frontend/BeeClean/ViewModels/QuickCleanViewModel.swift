import SwiftUI

// MARK: - Swipe Action (for undo history)
struct SwipeAction {
    let messageId: String
    let direction: SwipeDirection
}

// MARK: - Sender Clean Status
enum SenderCleanStatus {
    case active, trashed, deleted
}

// MARK: - Trashed Sender Info (for display in trash sheet)
struct TrashedSenderInfo: Identifiable {
    let email: String
    let name: String
    let count: Int

    var id: String { email }
}

// MARK: - Quick Clean ViewModel
@MainActor
class QuickCleanViewModel: ObservableObject {
    @Published var messages: [EmailMessage] = []
    @Published var senderStatus: [String: SenderCleanStatus] = [:]
    @Published var trashedMessageIds: Set<String> = []
    @Published var currentIndex: Int = 0
    @Published var isDeleting = false
    @Published var deleteProgress: Int = 0
    @Published var totalToDelete: Int = 0
    @Published var isLoadingMessages = false
    @Published var loadError: String?

    let category: GmailCategory
    let scope: String
    private(set) var swipeHistory: [SwipeAction] = []
    private var lastTrashedEmail: String?

    @Published var isLoadingMore = false
    private var nextPageToken: String?
    private var isBackgroundLoading = false

    // Persistent dedup set — O(1) lookups, never rebuilt from scratch
    private var messageIdSet: Set<String> = []

    // Pre-computed sender info cache — avoids O(n²) scans
    private var senderNameCache: [String: String] = [:] // email -> name
    private var senderCountCache: [String: Int] = [:]   // email -> count

    var isComplete: Bool { currentIndex >= messages.count && !isLoadingMore && nextPageToken == nil }
    var canUndo: Bool { !swipeHistory.isEmpty }

    var trashCount: Int {
        trashedMessageIds.count
    }

    /// O(1) per sender — uses pre-built caches instead of scanning all messages
    var trashedSenders: [TrashedSenderInfo] {
        senderStatus.compactMap { email, status in
            guard status == .trashed,
                  let name = senderNameCache[email] else { return nil }
            return TrashedSenderInfo(
                email: email,
                name: name,
                count: senderCountCache[email] ?? 0
            )
        }
    }

    init(category: GmailCategory, scope: String) {
        self.category = category
        self.scope = scope
    }

    func loadMessages() async {
        isLoadingMessages = true
        loadError = nil

        // ── INSTANT PATH: grab cached messages from the category detail view ──
        if let cached = EmailService.shared.cachedMessages(for: category.id), !cached.messages.isEmpty {
            messages = cached.messages
            messageIdSet = Set(cached.messages.map { $0.id })
            nextPageToken = cached.nextPageToken
            updateSenderCaches(from: cached.messages)
            isLoadingMessages = false
            // Continue loading more in background
            loadMoreInBackground()
            return
        }

        // ── Fallback: fetch first small batch ──
        let result = await EmailService.shared.fetchMessages(
            category: category.id, scope: scope, maxResults: 25
        )
        messages = result.messages
        messageIdSet = Set(result.messages.map { $0.id })
        nextPageToken = result.nextPageToken
        updateSenderCaches(from: result.messages)
        if messages.isEmpty, let serviceError = EmailService.shared.error {
            loadError = serviceError
        }
        isLoadingMessages = false
        loadMoreInBackground()
    }

    /// Continuously loads pages in the background so the user never waits.
    private func loadMoreInBackground() {
        guard !isBackgroundLoading, let token = nextPageToken else { return }
        isBackgroundLoading = true
        isLoadingMore = true
        Task {
            var currentToken: String? = token
            while let pageToken = currentToken {
                let more = await EmailService.shared.fetchMoreMessages(
                    category: category.id, scope: scope, pageToken: pageToken, maxResults: 100
                )
                // O(1) dedup using persistent Set
                let newMessages = more.messages.filter { !messageIdSet.contains($0.id) }
                for msg in newMessages { messageIdSet.insert(msg.id) }
                messages.append(contentsOf: newMessages)
                updateSenderCaches(from: newMessages)
                currentToken = more.nextPageToken
                nextPageToken = more.nextPageToken

                // Memory backpressure: pause if user is far behind
                let buffered = messages.count - currentIndex
                if buffered > 500 && currentToken != nil {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            isBackgroundLoading = false
            isLoadingMore = false
        }
    }

    /// Prefetch more when user is getting close to the end
    private func prefetchIfNeeded() {
        let remaining = messages.count - currentIndex
        if remaining < 50, nextPageToken != nil, !isBackgroundLoading {
            loadMoreInBackground()
        }
    }

    /// Incrementally update sender name/count caches — O(n) for new messages only
    private func updateSenderCaches(from newMessages: [EmailMessage]) {
        for msg in newMessages {
            if senderNameCache[msg.senderEmail] == nil {
                senderNameCache[msg.senderEmail] = msg.senderName
            }
            senderCountCache[msg.senderEmail, default: 0] += 1
        }
    }

    func swipeLeft() {
        guard currentIndex < messages.count else { return }
        let message = messages[currentIndex]
        trashedMessageIds.insert(message.id)
        senderStatus[message.senderEmail] = .trashed
        lastTrashedEmail = message.senderEmail
        swipeHistory.append(SwipeAction(messageId: message.id, direction: .left))
        currentIndex += 1
        prefetchIfNeeded()
    }

    func swipeRight() {
        guard currentIndex < messages.count else { return }
        let message = messages[currentIndex]
        swipeHistory.append(SwipeAction(messageId: message.id, direction: .right))
        currentIndex += 1
        prefetchIfNeeded()
    }

    func undoLast() {
        guard let last = swipeHistory.popLast() else { return }
        currentIndex -= 1
        if last.direction == .left {
            trashedMessageIds.remove(last.messageId)
            // Only restore sender status if no other messages from that sender are trashed
            if currentIndex < messages.count {
                let senderEmail = messages[currentIndex].senderEmail
                let hasOtherTrashed = messages.contains { msg in
                    msg.senderEmail == senderEmail && trashedMessageIds.contains(msg.id)
                }
                if !hasOtherTrashed {
                    senderStatus.removeValue(forKey: senderEmail)
                }
            }
        }
    }

    /// Undo trash for a specific sender (from undo toast -- does NOT rewind card index)
    func undoTrash(email: String) {
        let idsToRemove = trashedMessageIds.filter { id in
            // Use index lookup for the message — faster than scanning all messages
            messages.first(where: { $0.id == id })?.senderEmail == email
        }
        trashedMessageIds.subtract(idsToRemove)
        senderStatus.removeValue(forKey: email)
    }

    /// Restore sender from trash sheet
    func restoreSender(email: String) {
        let idsToRemove = trashedMessageIds.filter { id in
            messages.first(where: { $0.id == id })?.senderEmail == email
        }
        trashedMessageIds.subtract(idsToRemove)
        senderStatus.removeValue(forKey: email)
    }

    /// Permanently trash a single sender's swiped messages via backend
    func deleteSenderForever(email: String) async {
        let ids = trashedMessageIds.filter { id in
            messages.first(where: { $0.id == id })?.senderEmail == email
        }
        guard !ids.isEmpty else { return }
        isDeleting = true
        totalToDelete = 1
        deleteProgress = 0
        _ = await EmailService.shared.trashMessages(messageIds: Array(ids))
        senderStatus[email] = .deleted
        deleteProgress = 1
        // No manual stats/Bee call here: trashMessagesDetailed is the
        // single wiring point and feeds HiveStatsManager + BeeViewModel
        // for every email trash flow. Adding one here would double-count.
        isDeleting = false
    }

    /// Permanently trash all swiped messages via backend
    func emptyTrash() async {
        let ids = Array(trashedMessageIds)
        guard !ids.isEmpty else { return }
        isDeleting = true
        totalToDelete = ids.count
        deleteProgress = 0

        // Batch in chunks of 50 to avoid overwhelming the API
        let chunkSize = 50
        var totalDeleted = 0
        for chunk in stride(from: 0, to: ids.count, by: chunkSize) {
            let end = min(chunk + chunkSize, ids.count)
            let batch = Array(ids[chunk..<end])
            let deleted = await EmailService.shared.trashMessages(messageIds: batch)
            deleteProgress += deleted
            totalDeleted += deleted
        }

        // Mark all trashed senders as deleted
        for sender in trashedSenders {
            senderStatus[sender.email] = .deleted
        }

        // trashMessages → trashMessagesDetailed already feeds stats and
        // the Bee mascot once per batch, so no second call here.

        isDeleting = false
    }

    /// The email of the last trashed sender (for undo toast)
    func getLastTrashedEmail() -> String? {
        return lastTrashedEmail
    }
}
