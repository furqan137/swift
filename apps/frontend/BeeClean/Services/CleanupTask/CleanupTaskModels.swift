import Foundation

// MARK: - Cleanup Task models (Shuffling System)
//
// Display snapshots persisted by the backend wrapping the existing client-side
// generator. `taskType` / `category` remain the internal metadata; the
// user-facing label is always `displayTitle` ("Task #X").

struct ActiveCleanupTask: Codable, Equatable {
    let taskNumber: Int
    let taskTitle: String
    let taskType: String
    let category: String
    let estimatedMB: Double
    let estimatedCoins: Int
    let level: Int
    let status: String
    let generatedAt: String

    /// User-facing label. Numbered progression, not the task type.
    var displayTitle: String { "Task #\(taskNumber)" }

    /// Bytes for reusing the existing MB formatter on the card.
    var estimatedBytes: Int64 { Int64(estimatedMB * 1_000_000) }
}

struct CompletedCleanupTask: Codable, Equatable, Identifiable {
    let taskNumber: Int
    let taskTitle: String
    let taskType: String
    let category: String
    let mbReviewed: Double
    let coinsEarned: Int
    let levelAtCompletion: Int
    let assetCount: Int
    let completedAt: String

    var id: Int { taskNumber }
    var displayTitle: String { "Task #\(taskNumber)" }
    var completedDate: Date? { CleanupTaskDates.parse(completedAt) }
}

/// Outcome of a finished guided session, sent to the backend on completion.
struct CompletedTaskResult: Codable {
    let taskTitle: String
    let taskType: String
    let category: String
    let mbReviewed: Double
    let coinsEarned: Int
    let levelAtCompletion: Int
    let assetCount: Int
}

/// Snapshot the client persists for the active task. The client owns the
/// number (deterministic rolling counter); the backend stores what it's sent.
struct ActiveTaskUpsert: Codable {
    let taskNumber: Int
    let taskTitle: String
    let taskType: String
    let category: String
    let estimatedMB: Double
    let estimatedCoins: Int
    let level: Int
}

/// Backend body for recording a completion — the view-supplied `CompletedTaskResult`
/// plus the client-owned `taskNumber` injected by the manager.
struct CompletedTaskRequest: Codable {
    let taskNumber: Int
    let taskTitle: String
    let taskType: String
    let category: String
    let mbReviewed: Double
    let coinsEarned: Int
    let levelAtCompletion: Int
    let assetCount: Int
}

// MARK: - History grouping

struct DayGroup: Identifiable {
    let id: String          // stable key (the day label)
    let label: String       // "Today" / "Yesterday" / "May 24"
    let items: [CompletedCleanupTask]
    let totalMB: Double
    let totalCoins: Int
    let count: Int
}

enum CleanupTaskDates {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Supabase timestamptz may or may not carry fractional seconds.
    static func parse(_ s: String) -> Date? {
        withFractional.date(from: s) ?? plain.date(from: s)
    }
}
