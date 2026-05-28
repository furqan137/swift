import Foundation
import Combine
import Photos
import UIKit

// MARK: - Memory Pressure Monitor

/// Singleton that monitors system memory pressure and notifies observers.
/// Indexing services should pause operations when under memory pressure.
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private(set) var isUnderMemoryPressure = false

    private var memoryWarningObserver: Any?

    private init() {
        // Monitor UIApplication.didReceiveMemoryWarningNotification
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[MemoryMonitor] ⚠️ Memory warning received — flagging pressure")
            self?.isUnderMemoryPressure = true

            // Clear the flag after 30 seconds to allow resumption
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                print("[MemoryMonitor] Memory pressure flag cleared")
                self?.isUnderMemoryPressure = false
            }
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - IndexingService (Unified Facade)

@MainActor
final class IndexingService: ObservableObject {
    static let shared = IndexingService()

    @Published private(set) var state: IndexingState = .notStarted

    private let photoIndexing = PhotoIndexingService.shared
    private let photoKit = PhotoKitService.shared

    private var cancellables = Set<AnyCancellable>()
    private static let persistenceKey = "indexing_state_v1"

    private init() {
        // Hydrate from disk
        state = Self.loadPersistedState()

        // Subscribe to both services and re-derive on every change.
        let upstream = Publishers.MergeMany(
            photoIndexing.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            photoKit.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.updateDerivedState()
        }

        cancellables.insert(upstream)
    }

    // MARK: - Public Control Methods

    /// Sole entry point for starting indexing. Called on Gmail auth success.
    /// Idempotent — no-ops if already in progress or complete.
    func startIfNeeded() {
        // Reconcile persisted state with actual completion flag.
        // Migration may have cleared fullIndexComplete while persisted
        // state still says .complete (race during Combine debounce window).
        let fullIndexComplete = UserDefaults.standard.bool(forKey: "embedding_full_index_complete")
        if state == .complete && !fullIndexComplete {
            print("[Indexing] startIfNeeded — stale .complete state, resetting to .notStarted")
            state = .notStarted
        }
        guard state != .complete else {
            print("[Indexing] startIfNeeded skipped — already complete")
            return
        }
        if case .inProgress = state {
            print("[Indexing] startIfNeeded skipped — already in progress")
            return
        }

        let status = photoKit.authorizationStatus
        let hasAccess = status == .authorized || status == .limited

        print("[Indexing] startIfNeeded — state: \(state), photoStatus: \(status.rawValue), fullIndexComplete: \(fullIndexComplete)")
        AnalyticsService.shared.log("indexing_triggered", properties: [
            "current_state": state.description,
            "photo_status": "\(status.rawValue)"
        ])

        if hasAccess {
            photoIndexing.ensureRunning()
        } else if status == .notDetermined {
            Task {
                let granted = await photoKit.requestAuthorization()
                if granted {
                    photoIndexing.ensureRunning()
                }
                // If denied, deriveState() will pick up .blockedNoPhotoPermission
            }
        }
        // If denied/restricted, deriveState() handles it via upstream subscription
    }

    /// Resume interrupted indexing work. Called on app launch and foreground.
    /// Does NOT start fresh indexing — only resumes if there's a checkpoint.
    /// Only proceeds if photo access was already granted — never prompts for
    /// permission from a background resume path. Permission requesting is
    /// handled by `startIfNeeded()` via explicit UI flows (AskBee / Email).
    func resumeFromCheckpoint() {
        let status = photoKit.authorizationStatus
        guard status == .authorized || status == .limited else {
            print("[Indexing] resumeFromCheckpoint skipped — photo status: \(status.rawValue), state: \(state)")
            return
        }
        print("[Indexing] resumeFromCheckpoint proceeding — state: \(state), fullIndexComplete: \(UserDefaults.standard.bool(forKey: "embedding_full_index_complete"))")
        photoIndexing.resumeIfNeeded()
    }

    /// Retry after a failed indexing run. Only valid when state is `.failed`.
    func retry() {
        guard case .failed = state else { return }
        AnalyticsService.shared.log("indexing_retry_triggered")
        photoIndexing.ensureRunning()
    }

    // MARK: - Derived State

    private func updateDerivedState() {
        let newState = deriveState()
        guard newState != state else { return }
        state = newState
        persistIfSettled(newState)
    }

    private func deriveState() -> IndexingState {
        let status = photoKit.authorizationStatus
        let hasAccess = status == .authorized || status == .limited

        // 1. Check for model load failure
        if photoIndexing.statusLine.contains("Model load failed") {
            return .failed(error: "Failed to load AI models. Tap retry to try again.")
        }

        // 2. Check if full index ever completed — if so, stay .complete even
        //    during brief incremental runs so Ask Bee doesn't re-lock.
        let fullIndexComplete = UserDefaults.standard.bool(forKey: "embedding_full_index_complete")
        if fullIndexComplete {
            return .complete
        }

        // 3. Photo metadata or embedding indexing in progress
        if photoIndexing.isIndexing {
            let progress = photoIndexing.isIndexingEmbeddings
                ? photoIndexing.embeddingProgress
                : photoIndexing.progress
            let stage: IndexingStage = photoIndexing.isIndexingEmbeddings
                ? .contentEmbeddings
                : .metadataScan
            let fraction: Double = progress.totalAssets > 0
                ? Double(progress.processedAssets) / Double(progress.totalAssets)
                : 0
            return .inProgress(stage: stage, progress: fraction)
        }

        // 4. Paused / pending work (but full index never completed)
        if photoIndexing.hasPendingWork || photoIndexing.isPaused {
            return .paused
        }

        // 6. Photo access explicitly denied or restricted
        if !hasAccess && (status == .denied || status == .restricted) {
            return .blockedNoPhotoPermission
        }

        // 7. Nothing running, nothing pending, full index never completed
        return .notStarted
    }

    // MARK: - Status Line

    var statusLine: String {
        switch state {
        case .notStarted:
            return "Preparing your library..."
        case .inProgress(let stage, _):
            switch stage {
            case .metadataScan:
                if !photoIndexing.statusLine.isEmpty {
                    return photoIndexing.statusLine
                }
                let p = photoIndexing.progress
                if p.totalAssets > 0 {
                    return p.phase
                }
                return "Scanning your library..."
            case .contentEmbeddings:
                if !photoIndexing.statusLine.isEmpty {
                    return photoIndexing.statusLine
                }
                let p = photoIndexing.embeddingProgress
                if p.totalAssets > 0 {
                    return "Generating embeddings — \(p.processedAssets) of \(p.totalAssets)"
                }
                return "Generating content embeddings..."
            }
        case .paused:
            return "Indexing paused — will resume shortly"
        case .complete:
            return ""
        case .failed(let error):
            return "Indexing failed: \(error)"
        case .blockedNoPhotoPermission:
            return "Photo access required"
        }
    }

    // MARK: - Persistence

    private func persistIfSettled(_ state: IndexingState) {
        switch state {
        case .inProgress:
            return // Never persist in-progress
        default:
            break
        }
        let persisted = PersistedIndexingState(from: state)
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private static func loadPersistedState() -> IndexingState {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let persisted = try? JSONDecoder().decode(PersistedIndexingState.self, from: data) else {
            return .notStarted
        }
        return persisted.indexingState
    }
}
