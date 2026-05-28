import Foundation
import Photos
import UIKit
import SwiftUI
import BackgroundTasks

// MARK: - PhotoIndexingService
@MainActor
class PhotoIndexingService: ObservableObject {
    static let shared = PhotoIndexingService()

    // MARK: Background task identifier
    /// Must match Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated static let backgroundTaskIdentifier = "com.beeclean.indexing.resume"

    @Published var progress = IndexingProgress()
    @Published var isIndexing = false
    @Published var embeddingProgress = IndexingProgress()
    @Published var isIndexingEmbeddings = false
    /// Global metrics — updated live during a run, inspectable from any view.
    @Published var metrics = IndexingMetrics()
    /// True when the pipeline has work remaining but is currently idle
    /// (e.g. the system asked us to stop, or we're waiting for BG execution).
    @Published var isPaused = false
    /// True when there is known pending work that has not been completed.
    /// Persists across relaunches (driven by CLIPEmbeddingStore vs the library).
    @Published var hasPendingWork = false
    /// Short human-readable status used by global UI (banner).
    @Published var statusLine = ""

    private static let embeddingCountKey = "embedding_upserted_count"
    private static let pipelineVersionKey = "embedding_pipeline_version"
    private static let resumeCountKey = "indexing_resume_count"
    private static let fullIndexCompleteKey = "embedding_full_index_complete"
    /// Bump this when the embedding pipeline changes and all photos need re-indexing.
    /// 8 → 9: Fix polling race that falsely set fullIndexComplete before any work ran.
    /// 9 → 10: New AskBee architecture (on-device QueryParser, parallel execution, TemplateReplyService).
    ///         Force fresh index to ensure compatibility with new search system.
    nonisolated private static let currentPipelineVersion = 10

    /// Whether the full initial index has completed at least once.
    /// Only true when the pipeline ran to completion without interruption.
    /// Used to gate incremental sync — until this is true, always fetch ALL photos.
    private var fullIndexComplete: Bool {
        get { UserDefaults.standard.bool(forKey: Self.fullIndexCompleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.fullIndexCompleteKey) }
    }

    /// The in-flight top-level task, if any. Used to avoid double-starts and to
    /// let background-task handlers wait for a graceful stop.
    private var runningTask: Task<Void, Never>?

    /// When set, the pipeline should stop cleanly at the next chunk boundary
    /// and save its checkpoint. Used by iOS BG task expiration handlers.
    private var shouldStopAtNextCheckpoint = false

    private let clipIndexer = CLIPPhotoIndexer.shared

    private init() {
        // Clean up stale keys from old buggy watermark code
        UserDefaults.standard.removeObject(forKey: "embedding_indexed_count")
        UserDefaults.standard.removeObject(forKey: "embedding_last_index_date")
        UserDefaults.standard.removeObject(forKey: "embedding_indexed_count_v2")
        UserDefaults.standard.removeObject(forKey: "embedding_last_index_date_v2")

        // Pipeline migration: if the stored version doesn't match, force a full re-index.
        let storedVersion = UserDefaults.standard.integer(forKey: Self.pipelineVersionKey)
        if storedVersion < Self.currentPipelineVersion {
            print("[Migration] Pipeline version \(storedVersion) → \(Self.currentPipelineVersion). Forcing re-index.")
            // Clean up old checkpoint/retry files from previous backend-based pipeline
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? FileManager.default.removeItem(at: docs.appendingPathComponent("indexing_checkpoint_v1.json"))
                try? FileManager.default.removeItem(at: docs.appendingPathComponent("indexing_retry_queue_v1.json"))
            }
            UserDefaults.standard.removeObject(forKey: Self.embeddingCountKey)
            UserDefaults.standard.removeObject(forKey: Self.resumeCountKey)
            UserDefaults.standard.removeObject(forKey: Self.fullIndexCompleteKey)
            CLIPEmbeddingStore.shared.purgeStaleVersions(keeping: CLIPConfig.clipModelVersion)
            // Also clear IndexingService's persisted state so it doesn't
            // load stale .complete after migration cleared fullIndexComplete.
            UserDefaults.standard.removeObject(forKey: "indexing_state_v1")
            UserDefaults.standard.set(Self.currentPipelineVersion, forKey: Self.pipelineVersionKey)
        }

        // Seed persisted counters into the metrics struct so UI reflects
        // cumulative state across relaunches.
        metrics.resumeCount = UserDefaults.standard.integer(forKey: Self.resumeCountKey)
    }

    // MARK: - Public API — Durable Job Control

    /// Fire-and-forget entry point for any view that wants indexing to run.
    /// Safe to call from `onAppear`, scene phase changes, or anywhere else.
    /// - If a run is already in-flight, does nothing.
    /// - If indexing has already completed and there's nothing new, does nothing.
    /// - Otherwise it starts the pipeline in an unstructured detached task so
    ///   the caller's view lifecycle has no effect on its progress.
    func ensureRunning() {
        guard runningTask == nil else { return }
        guard !isIndexing, !isIndexingEmbeddings else { return }

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.runFullIndexWithEmbeddings()
            self.runningTask = nil
        }
    }

    /// Called once from `BeeCleanApp` on launch. Decides whether we have
    /// unfinished work from a previous run and if so, resumes it. This is the
    /// "durable job" contract — users don't need to open any specific screen.
    func resumeIfNeeded() {
        // CLIPPhotoIndexer's missingAssetIds() naturally handles both resume
        // (finds gaps from interrupted runs) and incremental (finds new photos).
        // If fullIndexComplete is true and there are no new photos,
        // CLIPPhotoIndexer exits immediately with "Up to date".
        if !fullIndexComplete {
            hasPendingWork = true
            metrics.resumeCount += 1
            UserDefaults.standard.set(metrics.resumeCount, forKey: Self.resumeCountKey)
            statusLine = "Preparing library…"
            ensureRunning()
        } else {
            // Even if complete, check for new photos by running the pipeline —
            // CLIPPhotoIndexer will exit immediately if nothing new.
            ensureRunning()
        }
    }

    /// Called by the app delegate / SwiftUI scene when the app transitions to
    /// the background. Saves state immediately and schedules a BG processing
    /// task so iOS can hand us more time later to finish.
    func handleAppBackgrounding() {
        // If we're mid-run, flip the stop flag so the pipeline saves and exits
        // cleanly at the next safe boundary.
        if isIndexing || isIndexingEmbeddings {
            shouldStopAtNextCheckpoint = true
            isPaused = true
            statusLine = "Paused — will resume when allowed"
            clipIndexer.cancel()
        }

        scheduleBackgroundIndexing()
    }

    /// Register the BGProcessingTask handler. Must be called once, early,
    /// before `application(_:didFinishLaunchingWithOptions:)` returns.
    /// When using SwiftUI, call this from the App's `init()`.
    nonisolated static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await PhotoIndexingService.shared.handleBackgroundTask(processingTask)
            }
        }
    }

    /// Schedule a BGProcessingTask to run "some time soon" when the device is
    /// idle, preferring conditions where it can run long (up to a few minutes
    /// depending on system state).
    func scheduleBackgroundIndexing() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Ask iOS for the earliest opportunity. iOS may delay this considerably.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGTask] Scheduled indexing resume task")
        } catch {
            // Common reasons: task already scheduled, simulator, or user disabled
            // background app refresh. Not fatal — we'll just resume on next launch.
            print("[BGTask] Could not schedule: \(error.localizedDescription)")
        }
    }

    /// Handle a BGProcessingTask launch. Runs the pipeline for as long as iOS
    /// permits and exits cleanly when we're told to stop.
    func handleBackgroundTask(_ task: BGProcessingTask) async {
        // Reschedule immediately so we keep getting opportunities.
        scheduleBackgroundIndexing()

        // If iOS is about to kill us, flip the stop flag so the pipeline will
        // checkpoint at the next safe boundary.
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.shouldStopAtNextCheckpoint = true
                self?.clipIndexer.cancel()
            }
        }

        statusLine = "Indexing in background…"
        shouldStopAtNextCheckpoint = false
        await runFullIndexWithEmbeddings()

        // Surface completion state to the system.
        let finished = !isIndexing && !isIndexingEmbeddings && !shouldStopAtNextCheckpoint
        task.setTaskCompleted(success: finished)
    }

    // MARK: - Core Pipeline

    /// Runs the on-device CLIP embedding index followed by face detection.
    func runFullIndexWithEmbeddings() async {
        AnalyticsService.shared.log("indexing_stage_started", properties: ["stage": "contentEmbeddings"])
        print("[Indexing] Phase 1: on-device CLIP embedding index starting…")
        await runLocalCLIPIndex()
        AnalyticsService.shared.log("indexing_stage_completed", properties: ["stage": "contentEmbeddings"])

        // Only proceed to face indexing if CLIP completed cleanly
        guard !shouldStopAtNextCheckpoint else {
            print("[Indexing] CLIP index paused — skipping face indexing")
            return
        }

        AnalyticsService.shared.log("indexing_completed", properties: [
            "assets_per_second": String(format: "%.2f", metrics.assetsPerSecond),
            "total_assets": metrics.assetsThisRun,
            "failed_assets": metrics.failedThisRun
        ])
        print("[Indexing] Phase 3 done. All indexing complete.")
    }

    /// Run the on-device CLIP embedding pipeline by delegating to CLIPPhotoIndexer.
    /// Bridges CLIPPhotoIndexer's progress into PhotoIndexingService's @Published
    /// properties so IndexingService can derive its state correctly.
    private func runLocalCLIPIndex() async {
        isIndexing = true
        isIndexingEmbeddings = true
        isPaused = false
        shouldStopAtNextCheckpoint = false
        embeddingProgress = IndexingProgress()
        embeddingProgress.phase = "Preparing…"
        statusLine = "Preparing library…"

        // Start a new run window for metrics.
        metrics.runStartedAt = Date()
        metrics.assetsThisRun = 0
        metrics.failedThisRun = 0
        metrics.completedAt = nil

        // Background task protection so iOS doesn't kill us
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CLIPIndex") {
            print("[CLIPIndex] Background time expired — cancelling")
            self.clipIndexer.cancel()
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }

        defer {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
            }
        }

        // Permission gate
        let photoKit = PhotoKitService.shared
        if photoKit.authorizationStatus != .authorized && photoKit.authorizationStatus != .limited {
            embeddingProgress.phase = "Requesting permission…"
            let granted = await photoKit.requestAuthorization()
            if !granted {
                print("[CLIPIndex] Photo library access denied")
                embeddingProgress.error = "Photo library access denied"
                embeddingProgress.phase = "Permission denied"
                AnalyticsService.shared.log("indexing_failed", properties: [
                    "reason": "photo_permission_denied"
                ])
                isIndexing = false
                isIndexingEmbeddings = false
                return
            }
        }

        // Start CLIPPhotoIndexer
        clipIndexer.start()

        // Wait for CLIPPhotoIndexer to actually start before polling.
        // Replaced the previous 100ms sleep with a proper wait loop that
        // checks every 50ms for up to 5 seconds. This prevents the race
        // condition on heavily loaded devices where 100ms wasn't enough
        // for the MainActor.run block to execute.
        var waitAttempts = 0
        let maxWaitAttempts = 100 // 5 seconds max
        while !clipIndexer.isCurrentlyIndexing() && waitAttempts < maxWaitAttempts {
            try? await Task.sleep(for: .milliseconds(50))
            waitAttempts += 1
        }

        // If CLIP isn't running after the wait, it finished fast (nothing
        // to index / "Up to date") or bailed early — NOT a startup failure.
        // Fall through: the progress loop below is skipped and the
        // final-state block classifies the real outcome and resets flags.

        // Poll CLIPPhotoIndexer's state and bridge it to our @Published properties.
        // CLIPPhotoIndexer handles batch processing, resumability (via missingAssetIds),
        // thermal/battery guards, and cancellation internally.
        while clipIndexer.isCurrentlyIndexing() {
            if shouldStopAtNextCheckpoint {
                clipIndexer.cancel()
                break
            }

            // Bridge progress from CLIPPhotoIndexer → PhotoIndexingService
            let clipProgress = clipIndexer.progress
            let total = Int(clipProgress.totalUnitCount)
            let completed = Int(clipProgress.completedUnitCount)

            if total > 0 {
                embeddingProgress.totalAssets = total
                embeddingProgress.processedAssets = completed
                embeddingProgress.phase = "Indexing \(completed)/\(total)…"
                metrics.assetsThisRun = completed

                let rate = metrics.assetsPerSecond
                if rate > 0.1 {
                    statusLine = "Indexing photos — \(embeddingProgress.percent)% (\(String(format: "%.1f", rate))/s)"
                } else {
                    statusLine = "Indexing photos — \(embeddingProgress.percent)%"
                }
            }

            try? await Task.sleep(for: .seconds(1))
        }

        // Check final state
        let clipStatusLine = clipIndexer.statusLine
        let wasModelLoadFailure = clipStatusLine == "Model load failed"
        let wasCancelled = shouldStopAtNextCheckpoint || clipStatusLine == "Paused"
        let storeCount = CLIPEmbeddingStore.shared.count()

        if wasModelLoadFailure {
            print("[CLIPIndex] Model load failed — cannot proceed")
            embeddingProgress.error = "Failed to load CLIP model"
            embeddingProgress.phase = "Model load failed"
            statusLine = "Indexing failed — model load error"
            hasPendingWork = true
            isIndexing = false
            isIndexingEmbeddings = false
            return
        }

        if wasCancelled {
            print("[CLIPIndex] Paused at \(embeddingProgress.processedAssets)/\(embeddingProgress.totalAssets)")
            embeddingProgress.phase = "Paused at \(embeddingProgress.processedAssets)/\(embeddingProgress.totalAssets)"
            hasPendingWork = true
            isPaused = true
            statusLine = "Paused — will resume when allowed"
        } else {
            // Clean completion
            fullIndexComplete = true
            UserDefaults.standard.set(storeCount, forKey: Self.embeddingCountKey)
            embeddingProgress.phase = "Complete — \(storeCount) embeddings stored"
            embeddingProgress.isComplete = true
            statusLine = "Indexing complete — \(storeCount) photos"
            hasPendingWork = false
            metrics.completedAt = Date()
            print("[CLIPIndex] Complete — \(storeCount) embeddings in store")
        }

        isIndexing = false
        isIndexingEmbeddings = false
    }

    /// Clear state and force a full re-index next time.
    func resetCheckpoint() {
        fullIndexComplete = false
        UserDefaults.standard.removeObject(forKey: Self.embeddingCountKey)
        print("[Indexing] Checkpoint cleared — next index will start fresh")
    }

    /// User-driven retry after a surfaced error (model load failure,
    /// failed-to-start). Clears the error state and re-enters the
    /// pipeline. Permission-denied isn't recoverable from this entry
    /// point — the user has to fix that in Settings, which the banner's
    /// "Open Settings" affordance handles separately.
    func retryAfterError() {
        embeddingProgress.error = nil
        statusLine = "Retrying…"
        ensureRunning()
    }

    /// User-driven dismiss for the error banner. Wipes the surfaced
    /// failure without kicking off another run, so the persistent
    /// "Indexing didn't finish" pill that was sitting on top of the
    /// header chrome can be hidden. A future incremental sync will
    /// re-raise the banner if it hits the same problem.
    func dismissSurfacedFailure() {
        embeddingProgress.error = nil
        if statusLine.localizedCaseInsensitiveContains("failed") {
            statusLine = ""
        }
    }

    /// Whether the most recent run ended in an error the banner should
    /// surface with a "something went wrong" treatment.
    var hasFailureToSurface: Bool {
        embeddingProgress.error != nil
    }

    /// Classifies the current error so the banner can pick the right
    /// affordance: permission errors send the user to Settings, every
    /// other surfaced failure offers Retry.
    enum SurfacedFailure {
        case permissionDenied
        case retryable
    }
    var surfacedFailure: SurfacedFailure? {
        guard let err = embeddingProgress.error else { return nil }
        if err.localizedCaseInsensitiveContains("permission") || err.localizedCaseInsensitiveContains("denied") {
            return .permissionDenied
        }
        return .retryable
    }
}
