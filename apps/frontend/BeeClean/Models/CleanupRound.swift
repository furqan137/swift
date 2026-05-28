import Foundation

// MARK: - Checkpoint Item Ref (pre-resolved item for checkpoint flow)

struct CheckpointItemRef: Equatable {
    let assetId: String
    let category: CleanupTaskCategory
    let isBest: Bool
    let fileSize: Int64
    let groupId: String?   // non-nil for grouped items (to keep group context)
}

// MARK: - Cleanup Task (single mini-task in a round)

struct CleanupTask: Identifiable, Equatable {
    let id: String
    let icon: String          // SF Symbol name
    let title: String         // e.g. "5 duplicate screenshots"
    let estimatedBytes: Int64 // storage saved
    let category: CleanupTaskCategory
    var itemRefs: [CheckpointItemRef] = []

    var formattedBytes: String {
        CleanupRound.formatBytes(estimatedBytes)
    }
}

enum CleanupTaskCategory: String, Codable {
    case duplicatePhotos
    case similarPhotos
    case similarScreenshots
    case screenshots
    case blurryPhotos
    case similarVideos
    case screenRecordings
    case shortRecordings
    case longVideos
    case otherPhotos
    case promoEmails

    /// Maps to the coin-economy category keys used by the reward formula
    /// (mirrors ProgressMath.categoryMultipliers / the backend).
    var coinCategoryKey: String {
        switch self {
        case .duplicatePhotos:                            return "duplicates"
        case .similarPhotos, .similarScreenshots, .similarVideos: return "similar"
        case .screenshots:                                return "screenshots"
        case .blurryPhotos:                               return "blurry"
        case .screenRecordings, .shortRecordings:         return "screen_recordings"
        case .longVideos:                                 return "large_videos"
        case .otherPhotos, .promoEmails:                  return "other"
        }
    }
}

// MARK: - Cleanup Round (a single guided session)

struct CleanupRound: Identifiable, Equatable {
    let id: String
    let tasks: [CleanupTask]
    let totalBytes: Int64
    let estimatedSeconds: Int    // 45-90
    let interactionCount: Int    // 8-12

    var formattedBytes: String {
        Self.formatBytes(totalBytes)
    }

    var formattedTime: String {
        if estimatedSeconds < 60 {
            return "~\(estimatedSeconds) sec"
        }
        let mins = estimatedSeconds / 60
        let secs = estimatedSeconds % 60
        if secs == 0 { return "~\(mins) min" }
        return "~\(mins)m \(secs)s"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else if bytes < 1_000_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1f MB", mb)
        } else {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.1f GB", gb)
        }
    }
}

// MARK: - Today's Plan (returned from orchestrator)

struct TodayCleanupPlan: Equatable {
    let totalRecoverableBytes: Int64
    let roundBytes: Int64       // bytes for the current round only
    let tasks: [CleanupTask]
    let estimatedSeconds: Int
    let beeHealthScore: Int     // 0-100
    let subtitle: String        // "Bee found a quick cleanup for you"
    var checkpointCount: Int = 0
    /// True when the orchestrator could not produce a minimally viable
    /// task — every eligible asset has already been adjudicated. UI should
    /// render a "you're all caught up" empty state instead of an empty deck.
    var isPoolExhausted: Bool = false

    var formattedRoundBytes: String {
        CleanupRound.formatBytes(roundBytes)
    }

    var formattedTotalBytes: String {
        CleanupRound.formatBytes(totalRecoverableBytes)
    }

    var formattedTime: String {
        if estimatedSeconds <= 0 { return "" }
        if estimatedSeconds < 60 {
            return "~\(estimatedSeconds) sec"
        }
        let mins = estimatedSeconds / 60
        let secs = estimatedSeconds % 60
        if secs == 0 { return "~\(mins) min" }
        return "~\(mins)m \(secs)s"
    }

    static let empty = TodayCleanupPlan(
        totalRecoverableBytes: 0,
        roundBytes: 0,
        tasks: [],
        estimatedSeconds: 0,
        beeHealthScore: 0,
        subtitle: "Scanning for cleanup tasks..."
    )
}
