import Foundation

// MARK: - Review sheet filter

enum GuidedCleanupReviewFilter: Equatable {
    case all
    case photos
    case videos
}

// MARK: - Completion deletion UI (in-place on completion screen)

enum GuidedCleanupCompletionDeletionPhase: Equatable {
    case idle
    case running
    case success
}

enum GuidedCleanupDeletionMessages {
    static func statusMessages(for filter: GuidedCleanupReviewFilter) -> [String] {
        switch filter {
        case .photos:
            return [
                "Analyzing duplicate photos...",
                "Finding safe copies to remove...",
                "Deletion is in progress.",
                "Almost done..."
            ]
        case .videos:
            return [
                "Analyzing your videos...",
                "Preparing clips for removal...",
                "Deletion is in progress.",
                "Almost done..."
            ]
        case .all:
            return [
                "Preparing your cleanup...",
                "Analyzing selected items...",
                "Deletion is in progress.",
                "Almost done..."
            ]
        }
    }
}

// MARK: - Celebration Presentation

enum CheckpointGifVariant: String, Equatable, Codable {
    case gif1
    case gif2
}

enum CompletionResultGifVariant: String, Equatable, Codable, CaseIterable {
    case affectionateAndWelcoming
    case chefKiss
    case excitedAndJoyful
    case inLoveAndDreamy
    case smiling
}

enum BeeFrameAssetStyle: Equatable {
    case reactiveAnimations
    case checkpointGif(CheckpointGifVariant)
    case completionResultGif(CompletionResultGifVariant)
}

struct BeeFrameAnimation: Equatable {
    let startFrame: Int
    let endFrame: Int
    let fps: Double
    let assetStyle: BeeFrameAssetStyle

    init(
        startFrame: Int,
        endFrame: Int,
        fps: Double,
        assetStyle: BeeFrameAssetStyle = .reactiveAnimations
    ) {
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.fps = fps
        self.assetStyle = assetStyle
    }

    /// Session completion + legacy celebration (Reactive Animations asset catalog).
    static let checkpointCelebration = BeeFrameAnimation(
        startFrame: 300,
        endFrame: 348,
        fps: 24
    )

    /// Busy loop while PhotoKit deletion runs.
    static let deletionInProgress = BeeFrameAnimation(
        startFrame: 260,
        endFrame: 299,
        fps: 20
    )

    /// Mid-session checkpoint screen (CheckpointGif-1 / CheckpointGif-2 bundle PNGs).
    static func checkpointGifCelebration(variant: CheckpointGifVariant) -> BeeFrameAnimation {
        BeeFrameAnimation(
            startFrame: 0,
            endFrame: 179,
            fps: 24,
            assetStyle: .checkpointGif(variant)
        )
    }

    /// Completion result screen (5 result animations in Resources/CheckpointCompletionResultsGifs).
    static func completionResultCelebration(variant: CompletionResultGifVariant) -> BeeFrameAnimation {
        let endFrame: Int = {
            switch variant {
            case .smiling:
                return 119
            default:
                return 179
            }
        }()
        
        return BeeFrameAnimation(
            startFrame: 0,
            endFrame: endFrame,
            fps: 24,
            assetStyle: .completionResultGif(variant)
        )
    }

    func assetName(for frame: Int) -> String {
        switch assetStyle {
        case .reactiveAnimations:
            return String(format: "Reactive Animations_%05d", frame)
        case .checkpointGif(.gif1):
            return String(format: "6f05ceca78511f1a6a5dc507aca7d3bb46a0f24b-%d", frame)
        case .checkpointGif(.gif2):
            return String(format: "4364a028eb61b8b2d9f86f68272ed4e47d92bda7-%d", frame)
        case .completionResultGif(.affectionateAndWelcoming):
            return String(format: "23b488d6745a4032c1a81442f78a8a5806a69754-%d", frame)
        case .completionResultGif(.chefKiss):
            return String(format: "84cabd30dccd9f5c138f29eb669f7b94003eb658-%d", frame)
        case .completionResultGif(.excitedAndJoyful):
            return String(format: "ef141fc9eb7c25eaf94195c6933d5ba5bfe22731-%d", frame)
        case .completionResultGif(.inLoveAndDreamy):
            return String(format: "6d2c6ed6be84fb907ded313f1c100707aae71616-%d", frame)
        case .completionResultGif(.smiling):
            return String(format: "88050e2862e8cd3a6926e7d6ee0caf3c9a745bb2-%d", frame)
        }
    }
}

struct GuidedCleanupCelebrationContent: Equatable {
    let title: String
    let subtitlePrefix: String
    let subtitleHighlight: String
    let mascotAnimation: BeeFrameAnimation
    let sessionBytesCleaned: Int64
    let sessionGoalBytes: Int64
    let primaryButtonTitle: String
    let isSessionComplete: Bool
    let completedThroughTask: Int

    var sessionProgressFraction: Double {
        let goal = max(sessionGoalBytes, 1)
        return min(1.0, Double(sessionBytesCleaned) / Double(goal))
    }

    var formattedSessionBytes: String {
        CleanupRound.formatBytes(sessionBytesCleaned)
    }

    var formattedSessionGoal: String {
        CleanupRound.formatBytes(sessionGoalBytes)
    }
}

// MARK: - Completion stat subtitles

extension CleanupTaskCategory {
    var isPhotoCategory: Bool {
        switch self {
        case .duplicatePhotos, .similarPhotos, .similarScreenshots,
             .screenshots, .blurryPhotos, .otherPhotos:
            return true
        default:
            return false
        }
    }

    var isVideoCategory: Bool {
        switch self {
        case .similarVideos, .screenRecordings, .shortRecordings, .longVideos:
            return true
        default:
            return false
        }
    }

    /// Short label under photo/video count on the completion screen.
    var completionStatSubtitle: String {
        switch self {
        case .duplicatePhotos: return "Duplicates Deleted"
        case .similarPhotos: return "Similar Photos Removed"
        case .similarScreenshots: return "Duplicate Screenshots Removed"
        case .screenshots: return "Screenshots Removed"
        case .blurryPhotos: return "Blurry Photos Removed"
        case .otherPhotos: return "Photos Removed"
        case .similarVideos: return "Similar Videos Removed"
        case .screenRecordings: return "Screen Recordings Removed"
        case .shortRecordings: return "Short Clips Removed"
        case .longVideos: return "Large Videos Removed"
        case .promoEmails: return "Items Removed"
        }
    }
}
