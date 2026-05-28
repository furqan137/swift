import Foundation

// MARK: - Wire Models

private struct RemoteChatSession: Codable {
    let id: UUID
    let title: String
    let messages: [AIMessage]
    let isPinned: Bool
    let createdAt: String
    let updatedAt: String
}

private struct ListResponse: Codable {
    let sessions: [RemoteChatSession]
}

private struct UpsertRequest: Codable {
    let title: String
    let messages: [AIMessage]
    let isPinned: Bool
}

private struct UpsertResponse: Codable {
    let session: RemoteChatSession
}

// MARK: - Service

@MainActor
final class ChatAPIService {
    static let shared = ChatAPIService()
    private let auth = AuthService.shared

    private init() {}

    private var isoFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// Fetch all sessions for the current user.
    func fetchAll() async -> [ChatSession]? {
        do {
            let data = try await auth.authenticatedRequest(to: "/chats")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(ListResponse.self, from: data)
            return response.sessions.map(toLocal)
        } catch {
            print("[ChatAPI] Fetch error: \(error)")
            return nil
        }
    }

    /// Upsert a session on the server. Returns true on success.
    @discardableResult
    func upsert(_ session: ChatSession) async -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let body = try encoder.encode(UpsertRequest(
                title: session.title,
                messages: session.messages,
                isPinned: session.isPinned
            ))
            _ = try await auth.authenticatedRequest(
                to: "/chats/\(session.id.uuidString)",
                method: "PUT",
                body: body
            )
            return true
        } catch {
            print("[ChatAPI] Upsert error: \(error)")
            return false
        }
    }

    /// Delete a session on the server.
    @discardableResult
    func delete(_ id: UUID) async -> Bool {
        do {
            _ = try await auth.authenticatedRequest(
                to: "/chats/\(id.uuidString)",
                method: "DELETE"
            )
            return true
        } catch {
            print("[ChatAPI] Delete error: \(error)")
            return false
        }
    }

    // MARK: - Mapping

    private func toLocal(_ remote: RemoteChatSession) -> ChatSession {
        let created = isoFormatter.date(from: remote.createdAt) ?? Date()
        let updated = isoFormatter.date(from: remote.updatedAt) ?? created
        return ChatSession(
            id: remote.id,
            title: remote.title,
            messages: remote.messages,
            createdAt: created,
            updatedAt: updated,
            isPinned: remote.isPinned
        )
    }
}
