import Foundation
import Photos
import Vision
import CoreLocation
import MapKit

enum AISearchError: Error, LocalizedError {
    case photoLibraryAccessDenied
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photo library access is required to search your photos"
        case .searchFailed(let reason):
            return "Search failed: \(reason)"
        }
    }
}

@MainActor
class AIService: ObservableObject {
    static let shared = AIService()

    @Published var messages: [AIMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {
        messages = [
            AIMessage(
                role: .assistant,
                content: "Hey! I'm Bee 🐝 I know your photo library inside and out. What are we looking for today?"
            )
        ]
    }

    func sendMessage(_ text: String) async {
        // 1. Classify intent on-device (instant, deterministic)
        let intent = QueryClassifier.classify(text, previousMessages: messages)

        // 2. Append user message
        let userMessage = AIMessage(role: .user, content: text)
        messages.append(userMessage)

        // 3. Branch based on intent
        switch intent {
        case .photoSearch:
            await handlePhotoSearch(text: text)
        case .conversation:
            await handleConversation(text: text)
        case .followUp:
            await handleFollowUp(text: text)
        }
    }

    // MARK: - Intent Handlers

    /// Handle photo search queries: parse, search, show results
    private func handlePhotoSearch(text: String) async {
        let locations = await knownLocations()
        let parsed = QueryParser.parse(text, knownLocations: locations)

        // Capture the originating session id BEFORE the await. If the
        // user switches sessions during the search, the response would
        // otherwise be silently dropped (the in-memory `messages` array
        // gets swapped out, so updateMessage's id lookup no-ops).
        // `commitMessage` below routes the late response to the right
        // session in ChatHistoryService when this happens.
        let originatingSessionId = ChatHistoryService.shared.currentSessionId

        let assistantId = UUID()
        let placeholder = AIMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            actions: [parsed.action],
            state: .loading
        )
        messages.append(placeholder)

        do {
            let assetIds = try await executeAction(parsed.action)
            let reply = TemplateReplyService.shared.reply(for: ReplyContext(
                intent: .photoSearch,
                action: parsed.action.type,
                resultCount: assetIds.count,
                contentQuery: parsed.action.contentQuery,
                location: parsed.action.location,
                datePhrase: parsed.extractedComponents.datePhrase,
                dateRange: parsed.action.dateRange,
                originalQuery: text
            ))
            commitMessage(id: assistantId, originatingSessionId: originatingSessionId) { msg in
                msg.content = reply
                msg.assetIds = assetIds
                msg.state = .complete
            }
        } catch {
            let errorMsg = (error as? AISearchError)?.localizedDescription
                ?? "Something went wrong: \(error.localizedDescription)"
            commitMessage(id: assistantId, originatingSessionId: originatingSessionId) { msg in
                msg.state = .failed(errorMsg)
            }
        }
    }

    /// Handle conversation queries: just reply, no search
    private func handleConversation(text: String) async {
        let originatingSessionId = ChatHistoryService.shared.currentSessionId
        let assistantId = UUID()
        messages.append(AIMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            actions: [],
            state: .loading
        ))

        let reply = TemplateReplyService.shared.reply(for: ReplyContext(
            intent: .conversation, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: text
        ))
        commitMessage(id: assistantId, originatingSessionId: originatingSessionId) { msg in
            msg.content = reply
            msg.state = .complete
        }
    }

    /// Handle follow-up queries: reply about previous results, no new search
    private func handleFollowUp(text: String) async {
        let originatingSessionId = ChatHistoryService.shared.currentSessionId
        let assistantId = UUID()
        messages.append(AIMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            actions: [],
            state: .loading
        ))

        let reply = TemplateReplyService.shared.reply(for: ReplyContext(
            intent: .followUp, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: text
        ))
        commitMessage(id: assistantId, originatingSessionId: originatingSessionId) { msg in
            msg.content = reply
            msg.state = .complete
        }
    }

    /// Commit a late-binding response from an async handler. If the user
    /// hasn't switched sessions since the message was sent, behave like
    /// `updateMessage` (in-place mutate the in-memory `messages` array,
    /// which the SwiftUI grid reflects immediately). If they HAVE switched
    /// — the originating session no longer matches the current session
    /// id — route the update through ChatHistoryService so the response
    /// lands in the session that owns the original send instead of being
    /// silently dropped. The `messages` array is then carrying B's chat;
    /// updating it would either no-op (id not found) or worse, mutate the
    /// wrong session, so we surgically write into A's persisted messages.
    private func commitMessage(
        id: UUID,
        originatingSessionId: UUID?,
        _ mutator: (inout AIMessage) -> Void
    ) {
        let currentSessionId = ChatHistoryService.shared.currentSessionId
        if originatingSessionId == currentSessionId {
            // Same session (or both nil — fresh chat that's still fresh).
            // In-place mutate the in-memory array.
            updateMessage(id: id, mutator)
            return
        }
        // User switched sessions while the async work was in flight.
        // Route the response to the originating session so the user
        // sees their answer when they navigate back instead of a
        // permanent "loading" placeholder.
        if let originatingSessionId {
            ChatHistoryService.shared.applyMessageUpdate(
                id: id,
                inSession: originatingSessionId,
                mutator
            )
        }
        // If originatingSessionId is nil (the send started before any
        // session existed) and the user has since created/loaded one,
        // there's nothing to update — drop. This branch should be rare:
        // the first user message always creates a session via
        // syncCurrent inside the same MainActor frame.
    }

    func clearChat() {
        messages = [
            AIMessage(
                role: .assistant,
                content: "Hey! I'm Bee 🐝 I know your photo library inside and out. What are we looking for today?"
            )
        ]
        error = nil
    }

    /// Replace current chat state with a previously saved session.
    func loadMessages(_ newMessages: [AIMessage]) {
        messages = newMessages
        error = nil
    }

    // MARK: - Private Helpers

    func updateMessage(id: UUID, _ mutator: (inout AIMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutator(&messages[index])
    }

    private var _cachedLocations: [String]?

    private func knownLocations() async -> [String] {
        if let cached = _cachedLocations {
            return cached
        }

        // TODO: Wire to PhotoKitService.shared.knownLocations() once implemented
        // For now, return empty array (location-based queries won't match)
        let locations: [String] = []
        _cachedLocations = locations
        return locations
    }

    /// Execute an AI action by querying the on-device photo library directly.
    func executeAction(_ action: AIAction) async throws -> [String] {
        // Ensure photo library access before any search
        let photoKit = PhotoKitService.shared
        let status = photoKit.authorizationStatus
        if status != .authorized && status != .limited {
            let granted = await photoKit.requestAuthorization()
            if !granted {
                print("[AISearch] Photo library access denied")
                throw AISearchError.photoLibraryAccessDenied
            }
        }

        let dateRange = action.dateRange
        let mediaType = action.mediaType
        let limit = action.limit ?? 100
        let actionType = action.type
        let contentQuery = action.contentQuery

        // MainActor-bound cases
        switch actionType {
        case .findDuplicates:
            return await fetchDuplicateAssetIds(limit: limit)
        case .cleanupSuggestion:
            return [] // The AI reply text IS the suggestion
        case .indexPhotos:
            // Trigger the embedding indexing pipeline in the background
            Task { await PhotoIndexingService.shared.runFullIndexWithEmbeddings() }
            return []
        case .findByLocation:
            return await fetchByLocation(query: action.location ?? "", limit: limit)
        case .findByContent:
            print("[AISearch] findByContent — query: \"\(contentQuery ?? "")\"")
            return await SearchRouter.searchByContent(
                query: contentQuery ?? "",
                limit: limit
            ) {
                // `fetchByContent` is now async — runs a `TaskGroup` of
                // 4 in parallel scoring tasks instead of blocking GCD
                // threads on `requestImage(isSynchronous: true)`. The
                // `Task.detached` wrapper still hops off the main
                // actor for the kickoff, but the scoring itself is
                // structured concurrency now.
                await Task.detached {
                    await Self.fetchByContent(query: contentQuery ?? "", dateRange: dateRange, limit: limit)
                }.value
            }
        default:
            break
        }

        return await Task.detached {
            switch actionType {
            case .findByDate:
                return Self.fetchByDate(dateRange: dateRange, limit: limit)
            case .findScreenshots:
                return Array(photoKit.fetchScreenshots().prefix(limit).map(\.assetId))
            case .findLargest:
                return Self.fetchLargest(mediaType: mediaType, limit: limit)
            default:
                return []
            }
        }.value
    }

    /// Returns non-best asset IDs from cached duplicate groups (confidence >= 0.85).
    func fetchDuplicateAssetIds(limit: Int) async -> [String] {
        let cachedGroups = await SimilarPersistence.loadCachedGroups()
        let dupGroups = cachedGroups.filter { $0.confidence >= 0.85 }
        var ids: [String] = []
        for group in dupGroups {
            for item in group.items {
                ids.append(item.assetId)
                if ids.count >= limit { return ids }
            }
        }
        return ids
    }

}
