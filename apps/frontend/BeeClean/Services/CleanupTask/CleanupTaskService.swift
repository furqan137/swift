import Foundation

// MARK: - Cleanup Task Service
//
// Thin network layer for the Shuffling System endpoints. Mirrors
// ProgressService: uses AuthService.authenticatedRequest, decodes Codable,
// and tolerates offline (returns nil / [] so the UI degrades gracefully).

@MainActor
final class CleanupTaskService {
    static let shared = CleanupTaskService()
    private let auth = AuthService.shared

    private init() {}

    /// GET /cleanup-task/active — nil when the user has no active task.
    func fetchActiveTask() async -> ActiveCleanupTask? {
        do {
            let data = try await auth.authenticatedRequest(to: "/cleanup-task/active")
            // Endpoint returns `null` when none exists — decode tolerantly.
            if data.isEmpty { return nil }
            return try? JSONDecoder().decode(ActiveCleanupTask.self, from: data)
        } catch {
            print("[CleanupTaskService] fetchActiveTask error: \(error)")
            return nil
        }
    }

    /// POST /cleanup-task/active — persist the display snapshot; the response
    /// carries the server-assigned taskNumber.
    func upsertActiveTask(_ snapshot: ActiveTaskUpsert) async -> ActiveCleanupTask? {
        do {
            let body = try JSONEncoder().encode(snapshot)
            let data = try await auth.authenticatedRequest(to: "/cleanup-task/active", method: "POST", body: body)
            return try JSONDecoder().decode(ActiveCleanupTask.self, from: data)
        } catch {
            print("[CleanupTaskService] upsertActiveTask error: \(error)")
            return nil
        }
    }

    /// POST /cleanup-task/complete — store the finished task; clears the active row.
    func completeTask(_ request: CompletedTaskRequest) async -> CompletedCleanupTask? {
        do {
            let body = try JSONEncoder().encode(request)
            let data = try await auth.authenticatedRequest(to: "/cleanup-task/complete", method: "POST", body: body)
            return try JSONDecoder().decode(CompletedCleanupTask.self, from: data)
        } catch {
            print("[CleanupTaskService] completeTask error: \(error)")
            return nil
        }
    }

    /// GET /cleanup-task/history — flat, newest first.
    func fetchHistory() async -> [CompletedCleanupTask] {
        do {
            let data = try await auth.authenticatedRequest(to: "/cleanup-task/history")
            return (try? JSONDecoder().decode([CompletedCleanupTask].self, from: data)) ?? []
        } catch {
            print("[CleanupTaskService] fetchHistory error: \(error)")
            return []
        }
    }
}
