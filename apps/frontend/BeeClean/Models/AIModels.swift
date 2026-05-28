import Foundation

// MARK: - Action Types
enum AIActionType: String, Codable, CaseIterable {
    case findByDate = "FIND_BY_DATE"
    case findByLocation = "FIND_BY_LOCATION"
    case findByContent = "FIND_BY_CONTENT"
    case findLargest = "FIND_LARGEST"
    case findDuplicates = "FIND_DUPLICATES"
    case findScreenshots = "FIND_SCREENSHOTS"
    case cleanupSuggestion = "CLEANUP_SUGGESTION"
    case indexPhotos = "INDEX_PHOTOS"

    var displayName: String {
        switch self {
        case .findByDate: return "Find by Date"
        case .findByLocation: return "Find by Location"
        case .findByContent: return "Find by Content"
        case .findLargest: return "Find Largest"
        case .findDuplicates: return "Find Duplicates"
        case .findScreenshots: return "Find Screenshots"
        case .cleanupSuggestion: return "Cleanup Suggestion"
        case .indexPhotos: return "Indexing Photos"
        }
    }

    var iconName: String {
        switch self {
        case .findByDate: return "calendar"
        case .findByLocation: return "mappin.circle"
        case .findByContent: return "magnifyingglass"
        case .findLargest: return "arrow.up.circle"
        case .findDuplicates: return "doc.on.doc"
        case .findScreenshots: return "camera.viewfinder"
        case .cleanupSuggestion: return "sparkles"
        case .indexPhotos: return "brain"
        }
    }
}

// MARK: - Action
struct AIAction: Codable, Identifiable {
    var id: String { "\(type.rawValue)-\(description.hashValue)" }

    let type: AIActionType
    let description: String
    let dateRange: AIDateRange?
    let location: String?
    let contentQuery: String?
    let mediaType: String?
    let limit: Int?
    let labels: [String]?

    var displayDescription: String {
        if let loc = location { return "Search photos from \(loc)" }
        if let query = contentQuery { return "Search for \"\(query)\"" }
        return description
    }

    enum CodingKeys: String, CodingKey {
        case type, description, dateRange, location
        case contentQuery, mediaType, limit, labels
    }

    init(type: AIActionType, description: String, dateRange: AIDateRange? = nil, location: String? = nil, contentQuery: String? = nil, mediaType: String? = nil, limit: Int? = nil, labels: [String]? = nil) {
        self.type = type
        self.description = description
        self.dateRange = dateRange
        self.location = location
        self.contentQuery = contentQuery
        self.mediaType = mediaType
        self.limit = limit
        self.labels = labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AIActionType.self, forKey: .type)
        description = (try? container.decode(String.self, forKey: .description)) ?? type.displayName

        dateRange = try? container.decodeIfPresent(AIDateRange.self, forKey: .dateRange)
        location = try? container.decodeIfPresent(String.self, forKey: .location)
        contentQuery = try? container.decodeIfPresent(String.self, forKey: .contentQuery)
        mediaType = try? container.decodeIfPresent(String.self, forKey: .mediaType)
        limit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        labels = try? container.decodeIfPresent([String].self, forKey: .labels)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(dateRange, forKey: .dateRange)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(contentQuery, forKey: .contentQuery)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

struct AIDateRange: Codable {
    let start: String?
    let end: String?
}

// MARK: - Message
enum AIMessageRole: String, Codable {
    case user
    case assistant
}

enum AIMessageState: Codable, Equatable {
    case loading
    case complete
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case type
        case errorMessage
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .loading:
            try container.encode("loading", forKey: .type)
        case .complete:
            try container.encode("complete", forKey: .type)
        case .failed(let error):
            try container.encode("failed", forKey: .type)
            try container.encode(error, forKey: .errorMessage)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "loading":
            self = .loading
        // Backwards compatibility: old states map to loading
        case "resultsPending", "replyPending":
            self = .loading
        case "complete":
            self = .complete
        case "failed":
            // Graceful fallback: corrupt errorMessage → "Unknown error"
            let error = (try? container.decode(String.self, forKey: .errorMessage)) ?? "Unknown error"
            self = .failed(error)
        default:
            // Unknown state type → default to complete
            self = .complete
        }
    }
}

struct AIMessage: Identifiable, Codable {
    let id: UUID
    let role: AIMessageRole
    var content: String
    var actions: [AIAction]
    let clarifyingQuestion: String?
    let timestamp: Date
    var assetIds: [String]?
    var state: AIMessageState

    enum CodingKeys: String, CodingKey {
        case id, role, content, actions, clarifyingQuestion, timestamp, assetIds, state
    }

    init(id: UUID = UUID(), role: AIMessageRole, content: String, actions: [AIAction] = [], clarifyingQuestion: String? = nil, assetIds: [String]? = nil, state: AIMessageState = .complete) {
        self.id = id
        self.role = role
        self.content = content
        self.actions = actions
        self.clarifyingQuestion = clarifyingQuestion
        self.timestamp = Date()
        self.assetIds = assetIds
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AIMessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        clarifyingQuestion = try? container.decodeIfPresent(String.self, forKey: .clarifyingQuestion)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        assetIds = try? container.decodeIfPresent([String].self, forKey: .assetIds)
        // Graceful fallback: missing state → .complete
        state = (try? container.decode(AIMessageState.self, forKey: .state)) ?? .complete

        // Resilient: a single corrupt action drops just that action, not the message
        let messageId = id
        let wrapped = (try? container.decode([FailableDecodable<AIAction>].self, forKey: .actions)) ?? []
        actions = wrapped.enumerated().compactMap { index, item in
            if let action = item.value { return action }
            print("[ChatHistory] AIMessage \(messageId): dropped action at index \(index) — \(item.error?.localizedDescription ?? "unknown")")
            return nil
        }
    }
}

// MARK: - Request / Response
struct AIChatRequestBody: Codable {
    let message: String
    let conversationHistory: [AIConversationEntry]?
    let context: AIContext?
}

struct AIChatResponseBody: Codable {
    let reply: String
    let actions: [AIAction]
    let clarifyingQuestion: String?

    enum CodingKeys: String, CodingKey {
        case reply, actions, clarifyingQuestion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = (try? container.decode(String.self, forKey: .reply)) ?? ""
        clarifyingQuestion = try? container.decodeIfPresent(String.self, forKey: .clarifyingQuestion)

        // Decode actions one-by-one so a single bad action doesn't kill the whole response
        let wrapped = (try? container.decode([FailableDecodable<AIAction>].self, forKey: .actions)) ?? []
        actions = wrapped.compactMap(\.value)
    }
}

/// Wrapper that never throws — stores nil if the inner decode fails.
/// Used in both the API response path and the chat history persistence path.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    let error: Error?
    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
            error = nil
        } catch {
            value = nil
            self.error = error
        }
    }
}

struct AIConversationEntry: Codable {
    let role: String
    let content: String
}

struct AIContext: Codable {
    let totalPhotos: Int?
    let totalVideos: Int?
    let totalScreenshots: Int?
    let storageUsedMB: Int?
    let duplicateGroupsCount: Int?
    let duplicateToCleanCount: Int?
    let similarGroupsCount: Int?
    let screenRecordingCount: Int?
    let screenRecordingTotalBytes: Int?
    let shortVideoCount: Int?
    let shortVideoTotalBytes: Int?
    let capabilities: AICapabilities
}

struct AICapabilities: Codable {
    let canSearchByPerson: Bool
    let canSearchByDate: Bool
    let canSearchByLocation: Bool
    let canFindDuplicates: Bool
    let canFindLargeFiles: Bool
}

// MARK: - Photo Query
struct PhotoQueryRequestBody: Codable {
    let type: String
    let dateRange: AIDateRange?
    let contentQuery: String?
    let mediaType: String?
    let limit: Int?
}

struct PhotoQueryResponseBody: Codable {
    let assetIds: [String]
    /// `true` when the backend ran a valid semantic search. An empty `assetIds`
    /// combined with `searched == true` means "no strong matches exist" — the
    /// client should NOT fall back to imprecise on-device matching.
    let searched: Bool?
}
