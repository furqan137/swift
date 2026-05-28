import Foundation

// MARK: - Indexing Stage

enum IndexingStage: String, Codable, Sendable {
    case metadataScan
    case contentEmbeddings
}

// MARK: - Indexing State

enum IndexingState: Equatable, Sendable, CustomStringConvertible {
    case notStarted
    case inProgress(stage: IndexingStage, progress: Double)
    case paused
    case complete
    case failed(error: String)
    case blockedNoPhotoPermission

    var description: String {
        switch self {
        case .notStarted: return "notStarted"
        case .inProgress(let stage, let progress):
            return "inProgress(\(stage.rawValue), \(Int(progress * 100))%)"
        case .paused: return "paused"
        case .complete: return "complete"
        case .failed(let error): return "failed(\(error))"
        case .blockedNoPhotoPermission: return "blockedNoPhotoPermission"
        }
    }
}

// MARK: - Persisted Indexing State

/// Round-trips settled indexing states to/from UserDefaults.
/// In-progress states are derived live at runtime and never persisted.
struct PersistedIndexingState: Codable {
    enum SettledCase: String, Codable {
        case notStarted
        case complete
        case failed
        case paused
        case blockedNoPhotoPermission
    }

    let settled: SettledCase
    let errorMessage: String?

    init(from state: IndexingState) {
        switch state {
        case .notStarted:
            settled = .notStarted
            errorMessage = nil
        case .complete:
            settled = .complete
            errorMessage = nil
        case .failed(let error):
            settled = .failed
            errorMessage = error
        case .paused:
            settled = .paused
            errorMessage = nil
        case .blockedNoPhotoPermission:
            settled = .blockedNoPhotoPermission
            errorMessage = nil
        case .inProgress:
            // Should never be persisted; default to notStarted
            settled = .notStarted
            errorMessage = nil
        }
    }

    var indexingState: IndexingState {
        switch settled {
        case .notStarted: return .notStarted
        case .complete: return .complete
        case .failed: return .failed(error: errorMessage ?? "Unknown error")
        case .paused: return .paused
        case .blockedNoPhotoPermission: return .blockedNoPhotoPermission
        }
    }
}
