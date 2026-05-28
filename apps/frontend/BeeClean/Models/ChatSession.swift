import Foundation

struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [AIMessage]
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, isPinned
    }

    init(
        id: UUID = UUID(),
        title: String,
        messages: [AIMessage],
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = isPinned
    }

    /// Full init used when rehydrating from the server.
    init(
        id: UUID,
        title: String,
        messages: [AIMessage],
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPinned = (try? container.decode(Bool.self, forKey: .isPinned)) ?? false

        // Resilient: a single corrupt message drops just that message, not the session
        let sessionId = id
        let wrapped = (try? container.decode([FailableDecodable<AIMessage>].self, forKey: .messages)) ?? []
        messages = wrapped.enumerated().compactMap { index, item in
            if let msg = item.value { return msg }
            print("[ChatHistory] Session \(sessionId): dropped message at index \(index) — \(item.error?.localizedDescription ?? "unknown")")
            return nil
        }
    }

    /// Derive a short title from the first user message.
    static func titleFrom(messages: [AIMessage]) -> String {
        if let firstUser = messages.first(where: { $0.role == .user }) {
            let trimmed = firstUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(60))
        }
        return "New Chat"
    }

    /// Short preview of the most recent user question for the history list.
    var preview: String {
        if let lastUser = messages.last(where: { $0.role == .user }) {
            return lastUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }
}
