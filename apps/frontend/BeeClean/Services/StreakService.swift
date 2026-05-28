import Foundation

// MARK: - Streak API Models

struct StreakResponse: Codable {
    let currentStreak: Int
    let bestStreak: Int
    let lastActivityDate: String?
    let lifetimeItemsCleaned: Int
    let lifetimeBytesSaved: Int
    let totalScansCompleted: Int
    let cleanScore: Int
}

struct StreakSyncRequest: Codable {
    let currentStreak: Int
    let bestStreak: Int
    let lastActivityDate: String?
    let lifetimeItemsCleaned: Int
    let lifetimeBytesSaved: Int
    let totalScansCompleted: Int
    let cleanScore: Int
}

struct StreakActivityRequest: Codable {
    let action: String
    let itemCount: Int
    let bytesSaved: Int
}

struct ActivityEntry: Codable, Identifiable {
    let action: String
    let itemCount: Int
    let bytesSaved: Int
    let createdAt: String

    var id: String { "\(action)-\(createdAt)" }

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }

    /// Source category encoded into `action` as `"deletion:duplicates"`,
    /// `"deletion:screenshots"`, etc. Lets the Progress chart filter by
    /// the leaf category that produced each cleanup without a backend
    /// schema migration (`action` is already a free-form String on
    /// `streak_activities`). Returns nil for legacy entries without
    /// the `:category` suffix and for flows that don't tag (email,
    /// contacts, scans) — those fall into the "All" bucket on the chip
    /// row and never appear under a specific category filter.
    var category: SavedFindSourceCategory? {
        let parts = action.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return SavedFindSourceCategory(rawValue: String(parts[1]))
    }

    /// Bare verb without the category suffix — `"deletion:duplicates"` →
    /// `"deletion"`. Useful when we need to bucket by action type
    /// regardless of category (e.g., separating compressions from
    /// deletions in a future leaderboard).
    var bareAction: String {
        action.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? action
    }
}

// MARK: - Streak Service

@MainActor
final class StreakService {
    static let shared = StreakService()
    private let auth = AuthService.shared

    /// Local retry queue for activity events that failed to upload.
    /// Persisted to UserDefaults so a network blip (or full offline
    /// session) doesn't lose the cleanup the user actually performed —
    /// previously, a failed POST was just logged and dropped, so the
    /// streak/activity history on the backend would silently fall
    /// behind local state forever.
    private static let pendingQueueKey = "streak.pendingActivities.v1"

    private init() {}

    private struct QueuedActivity: Codable {
        let action: String
        let itemCount: Int
        let bytesSaved: Int
    }

    private var pendingQueue: [QueuedActivity] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingQueueKey),
                  let arr = try? JSONDecoder().decode([QueuedActivity].self, from: data)
            else { return [] }
            return arr
        }
        set {
            // Bound the queue so a permanently-offline user can't
            // explode UserDefaults with months of cleanup history.
            let bounded = Array(newValue.suffix(500))
            if let data = try? JSONEncoder().encode(bounded) {
                UserDefaults.standard.set(data, forKey: Self.pendingQueueKey)
            }
        }
    }

    /// Fetch the user's streak from the server.
    func fetchStreak() async -> StreakResponse? {
        do {
            let data = try await auth.authenticatedRequest(to: "/streak")
            return try JSONDecoder().decode(StreakResponse.self, from: data)
        } catch {
            print("[StreakService] Fetch error: \(error)")
            return nil
        }
    }

    /// Sync local streak state to the server.
    func syncStreak(_ request: StreakSyncRequest) async -> StreakResponse? {
        do {
            let body = try JSONEncoder().encode(request)
            let data = try await auth.authenticatedRequest(to: "/streak/sync", method: "POST", body: body)
            return try JSONDecoder().decode(StreakResponse.self, from: data)
        } catch {
            print("[StreakService] Sync error: \(error)")
            return nil
        }
    }

    /// Log an individual activity event. On failure, queues the event
    /// locally for the next `flushPendingActivities()` pass.
    func recordActivity(action: String, itemCount: Int, bytesSaved: Int = 0) async {
        do {
            let request = StreakActivityRequest(action: action, itemCount: itemCount, bytesSaved: bytesSaved)
            let body = try JSONEncoder().encode(request)
            _ = try await auth.authenticatedRequest(to: "/streak/activity", method: "POST", body: body)
            // Opportunistic drain — if we just succeeded, the network's
            // probably back, so try to flush anything queued previously.
            await flushPendingActivities()
        } catch {
            print("[StreakService] Activity log error: \(error) — queuing for retry")
            var queue = pendingQueue
            queue.append(QueuedActivity(action: action, itemCount: itemCount, bytesSaved: bytesSaved))
            pendingQueue = queue
        }
    }

    /// Replay any locally-queued activity events. Called opportunistically
    /// when a fresh `recordActivity` succeeds; also safe to call from app
    /// foreground / scene-phase transitions. Stops on the first failure
    /// so a flaky connection doesn't drain the queue into the void.
    func flushPendingActivities() async {
        var queue = pendingQueue
        guard !queue.isEmpty else { return }
        while !queue.isEmpty {
            let next = queue[0]
            do {
                let request = StreakActivityRequest(
                    action: next.action,
                    itemCount: next.itemCount,
                    bytesSaved: next.bytesSaved
                )
                let body = try JSONEncoder().encode(request)
                _ = try await auth.authenticatedRequest(to: "/streak/activity", method: "POST", body: body)
                queue.removeFirst()
                pendingQueue = queue
            } catch {
                // Still offline / still failing — stop and keep the
                // remaining queue intact for the next attempt.
                print("[StreakService] flush stalled at \(queue.count) remaining: \(error)")
                return
            }
        }
    }

    /// Fetch recent activity history.
    func fetchActivities(limit: Int = 50) async -> [ActivityEntry] {
        do {
            let data = try await auth.authenticatedRequest(to: "/streak/activities?limit=\(limit)")
            return try JSONDecoder().decode([ActivityEntry].self, from: data)
        } catch {
            print("[StreakService] Activities error: \(error)")
            return []
        }
    }
}
