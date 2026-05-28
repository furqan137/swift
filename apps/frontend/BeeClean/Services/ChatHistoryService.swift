import Foundation

@MainActor
final class ChatHistoryService: ObservableObject {
    static let shared = ChatHistoryService()

    @Published private(set) var sessions: [ChatSession] = []

    /// ID of the currently active session. Nil = fresh chat, not yet persisted.
    var currentSessionId: UUID?

    private let storageKey = "ask_bee_chat_history_v1"
    private let maxUnpinnedSessions = 50

    /// Debounced upload tasks keyed by session ID, so rapid-fire message edits
    /// collapse into a single PUT after the user stops typing.
    private var pendingUploads: [UUID: Task<Void, Never>] = [:]
    private let uploadDebounceNanoseconds: UInt64 = 800_000_000 // 0.8s

    private var hasHydratedFromServer = false

    private init() {
        load()
        Task { await refreshFromServer() }
    }

    // MARK: - Public API

    /// Sync the current in-memory chat to the history store.
    /// Creates a new session on first user message, updates it thereafter.
    func syncCurrent(messages: [AIMessage]) {
        // Only persist chats that contain a user message
        guard messages.contains(where: { $0.role == .user }) else { return }

        // Sanitize in-flight states to prevent zombie loading states on reload
        let sanitized = messages.map { msg -> AIMessage in
            var copy = msg
            switch copy.state {
            case .complete, .failed:
                break  // Already terminal, keep as-is
            case .loading:
                // Convert in-flight state to failed (won't complete after reload)
                copy.state = .failed("Interrupted")
            }
            return copy
        }

        let updatedSession: ChatSession

        if let currentId = currentSessionId,
           let idx = sessions.firstIndex(where: { $0.id == currentId }) {
            sessions[idx].messages = sanitized
            sessions[idx].updatedAt = Date()
            sessions[idx].title = ChatSession.titleFrom(messages: messages)
            updatedSession = sessions[idx]
        } else {
            let session = ChatSession(
                title: ChatSession.titleFrom(messages: messages),
                messages: sanitized
            )
            currentSessionId = session.id
            sessions.insert(session, at: 0)
            updatedSession = session
        }

        trimIfNeeded()
        save()
        scheduleUpload(for: updatedSession)
    }

    /// Begin a new chat — the next `syncCurrent` will start a fresh session.
    func startNewChat() {
        currentSessionId = nil
    }

    /// Apply an in-place update to a single message inside a specific
    /// session. Used when an async AI response lands *after* the user
    /// switched to a different session — without this, the late
    /// `updateMessage(id:)` in AIService looks up the assistant id in
    /// the now-swapped-in messages array, doesn't find it, and silently
    /// no-ops. The user sees their question in the old session but
    /// never the response. This API routes the late response to the
    /// originating session so the dropped reply is recovered into its
    /// rightful place + persisted.
    @discardableResult
    func applyMessageUpdate(
        id: UUID,
        inSession sessionId: UUID,
        _ mutator: (inout AIMessage) -> Void
    ) -> Bool {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == id })
        else { return false }
        mutator(&sessions[sessionIdx].messages[msgIdx])
        sessions[sessionIdx].updatedAt = Date()
        save()
        scheduleUpload(for: sessions[sessionIdx])
        return true
    }

    /// Drop the debounce and push every pending upload to the server now.
    /// Called from view-layer scene-phase handlers when the app is about
    /// to be inactive — the 800ms debounce window can otherwise mean a
    /// type-then-quit user's freshest edits never reach the server. The
    /// local UserDefaults cache is already written synchronously via
    /// `save()`, so single-device users are unaffected; this closes the
    /// cross-device sync gap.
    func flushPendingUploads() {
        let pendingIds = Array(pendingUploads.keys)
        for id in pendingIds {
            pendingUploads[id]?.cancel()
            pendingUploads.removeValue(forKey: id)
            guard let session = sessions.first(where: { $0.id == id }) else { continue }
            Task { await ChatAPIService.shared.upsert(session) }
        }
    }

    /// Restore a session. Returns its messages and marks it as current.
    func loadSession(_ id: UUID) -> [AIMessage]? {
        guard let session = sessions.first(where: { $0.id == id }) else { return nil }
        currentSessionId = id
        return session.messages
    }

    func togglePin(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned.toggle()
        let updated = sessions[idx]
        save()
        // Pin toggles are instant — skip the debounce.
        Task { await ChatAPIService.shared.upsert(updated) }
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if currentSessionId == id {
            currentSessionId = nil
        }
        pendingUploads[id]?.cancel()
        pendingUploads.removeValue(forKey: id)
        save()
        Task { await ChatAPIService.shared.delete(id) }
    }

    /// Pull the authoritative list from the server and merge into local state.
    /// Called once at launch; callers can invoke manually for pull-to-refresh.
    func refreshFromServer() async {
        guard let remote = await ChatAPIService.shared.fetchAll() else { return }

        // Merge: server is the source of truth, but we keep any local-only
        // sessions that haven't uploaded yet (e.g. offline drafts).
        let remoteIds = Set(remote.map(\.id))
        let localOnly = sessions.filter { !remoteIds.contains($0.id) }
        sessions = (remote + localOnly).sorted { $0.updatedAt > $1.updatedAt }
        hasHydratedFromServer = true
        save()

        // Push any local-only sessions that never made it up.
        for session in localOnly where session.messages.contains(where: { $0.role == .user }) {
            scheduleUpload(for: session)
        }
    }

    // MARK: - Computed

    var pinnedSessions: [ChatSession] {
        sessions.filter(\.isPinned).sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentSessions: [ChatSession] {
        sessions.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Remote sync

    private func scheduleUpload(for session: ChatSession) {
        pendingUploads[session.id]?.cancel()
        let id = session.id
        pendingUploads[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.uploadDebounceNanoseconds ?? 800_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            // Re-read the latest version before uploading — the session may
            // have been mutated again during the debounce window.
            guard let latest = self.sessions.first(where: { $0.id == id }) else { return }
            await ChatAPIService.shared.upsert(latest)
            self.pendingUploads.removeValue(forKey: id)
        }
    }

    // MARK: - Persistence (offline cache)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let wrapped = try JSONDecoder().decode([FailableDecodable<ChatSession>].self, from: data)
            sessions = wrapped.enumerated().compactMap { index, item in
                if let session = item.value { return session }
                print("[ChatHistory] load: dropped session at index \(index) — \(item.error?.localizedDescription ?? "unknown")")
                return nil
            }
        } catch {
            print("[ChatHistory] Failed to decode session array: \(error)")
            sessions = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[ChatHistory] Failed to encode: \(error)")
        }
    }

    private func trimIfNeeded() {
        let pinned = sessions.filter(\.isPinned)
        let unpinned = sessions.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
        if unpinned.count > maxUnpinnedSessions {
            sessions = pinned + Array(unpinned.prefix(maxUnpinnedSessions))
        }
    }
}
