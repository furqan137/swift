import Foundation

// MARK: - Progress API Models

/// Authoritative coin-progression state. Returned by `GET /progress`,
/// `POST /progress/sync`, and `POST /progress/checkpoint`. The Clean Bar is
/// progress within the current level; the bee stage is derived from
/// `cleanBarPercent`. Total lifetime coins are the source of truth.
struct ProgressState: Codable {
    let totalLifetimeCoins: Int
    let maxLifetimeCoins: Int
    let currentLevel: Int
    let maxLevel: Int
    let currentLevelCoins: Int
    let coinsNeededForNextLevel: Int
    let cleanBarPercent: Double
    let beeStage: Int
}

/// Per-category deleted bytes + reviewed item count, keyed by coin category.
struct CategoryStat: Codable {
    let bytes: Int64
    let reviewed: Int
}

struct CheckpointCoinRequest: Codable {
    let eventId: String      // "{planId}:{taskId}:{checkpointId}" — idempotency key
    let planId: String
    let taskId: String
    let checkpointId: String
    let reviewedItemCount: Int
    let selectedItemCount: Int
    let deletedBytes: Int64
    let categoryBreakdown: [String: CategoryStat]
    // Client's authoritative derived progress AFTER this award. The client is
    // the display source of truth, so the backend persists these directly —
    // guaranteeing the DB's clean bar % + level match what the user sees.
    let maxLifetimeCoins: Int
    let totalLifetimeCoins: Int
    let currentLevel: Int
    let maxLevel: Int
    let currentLevelCoins: Int
    let coinsNeededForNextLevel: Int
    let cleanBarPercent: Double
    let beeStage: Int
}

struct LibrarySyncRequest: Codable {
    let totalPhotos: Int
    let totalVideos: Int
}

// MARK: - Progress Service

@MainActor
final class ProgressService {
    static let shared = ProgressService()
    private let auth = AuthService.shared

    /// Failed coin-award POSTs are queued so a network blip doesn't lose the
    /// coins the user earned. Replay is safe: the backend dedupes on `eventId`
    /// (UNIQUE(user_id, event_id)).
    private static let pendingQueueKey = "progress.pendingCoinAwards.v1"

    private init() {}

    private var pendingQueue: [CheckpointCoinRequest] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingQueueKey),
                  let arr = try? JSONDecoder().decode([CheckpointCoinRequest].self, from: data)
            else { return [] }
            return arr
        }
        set {
            let bounded = Array(newValue.suffix(500))
            if let data = try? JSONEncoder().encode(bounded) {
                UserDefaults.standard.set(data, forKey: Self.pendingQueueKey)
            }
        }
    }

    /// Fetch authoritative progress.
    func fetchProgress() async -> ProgressState? {
        do {
            let data = try await auth.authenticatedRequest(to: "/progress")
            return try JSONDecoder().decode(ProgressState.self, from: data)
        } catch {
            print("[ProgressService] fetchProgress error: \(error)")
            return nil
        }
    }

    /// Recompute maxLifetimeCoins + level requirements from library counts.
    func syncLibrary(totalPhotos: Int, totalVideos: Int) async -> ProgressState? {
        do {
            let body = try JSONEncoder().encode(LibrarySyncRequest(totalPhotos: totalPhotos, totalVideos: totalVideos))
            let data = try await auth.authenticatedRequest(to: "/progress/sync", method: "POST", body: body)
            return try JSONDecoder().decode(ProgressState.self, from: data)
        } catch {
            print("[ProgressService] syncLibrary error: \(error)")
            return nil
        }
    }

    /// Award a checkpoint's coins. On failure, queues for the next flush.
    @discardableResult
    func recordCheckpoint(_ request: CheckpointCoinRequest) async -> ProgressState? {
        do {
            let body = try JSONEncoder().encode(request)
            let data = try await auth.authenticatedRequest(to: "/progress/checkpoint", method: "POST", body: body)
            await flushPendingCoinAwards()
            return try JSONDecoder().decode(ProgressState.self, from: data)
        } catch {
            print("[ProgressService] award error: \(error) — queuing for retry")
            var queue = pendingQueue
            queue.append(request)
            pendingQueue = queue
            return nil
        }
    }

    /// Replay queued awards. Stops on the first failure so a flaky connection
    /// doesn't drain the queue into the void. Backend dedup makes replay safe.
    func flushPendingCoinAwards() async {
        var queue = pendingQueue
        guard !queue.isEmpty else { return }
        while !queue.isEmpty {
            let next = queue[0]
            do {
                let body = try JSONEncoder().encode(next)
                _ = try await auth.authenticatedRequest(to: "/progress/checkpoint", method: "POST", body: body)
                queue.removeFirst()
                pendingQueue = queue
            } catch {
                print("[ProgressService] flush stalled at \(queue.count) remaining: \(error)")
                return
            }
        }
    }
}
