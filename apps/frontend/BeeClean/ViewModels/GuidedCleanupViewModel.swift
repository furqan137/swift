import Foundation
import Photos
import CryptoKit

// MARK: - Persisted Progress

private struct GuidedCleanupProgress: Codable {
    let signature: String              // kept for diagnostics; no longer gates restore
    let currentIndex: Int              // fallback when currentAssetId is unmappable
    let currentAssetId: String?        // stable cursor anchor across plan rebuilds
    let markedForDeletion: [String]
    let keptIds: [String]
    let pendingCheckpointTaskIndex: Int?
    // Coin award bookkeeping. `planId`/`taskId` build per-checkpoint event ids
    // ("{planId}:{taskId}:{checkpointId}"); `awardedCheckpointIds` is the
    // relaunch guard that prevents re-awarding a checkpoint after a restore.
    var planId: String = ""
    var taskId: String = ""
    var awardedCheckpointIds: [String] = []
    var totalCoinsEarned: Int = 0

    // Checkpoint + completion animation bookkeeping.
    let passedCheckpointCount: Int?
    let activeCheckpointGifVariant: CheckpointGifVariant?
    let activeCompletionResultGifVariant: CompletionResultGifVariant?
}

// MARK: - Guided Cleanup Item

struct GuidedItem: Identifiable {
    let id: String              // assetId
    let category: CleanupTaskCategory
    let taskIndex: Int          // which CleanupTask this belongs to
    let isBest: Bool
    let fileSize: Int64
}

// MARK: - Next Task Preview

/// What the next Quick Cleanup round offers, shown on the completion screen.
struct NextTaskPreview: Equatable {
    let bytes: String
}

// MARK: - Guided Cleanup View Model

@MainActor
final class GuidedCleanupViewModel: ObservableObject {

    // MARK: - Published State

    @Published var items: [GuidedItem] = []
    @Published var currentIndex: Int = 0
    @Published var markedForDeletion: Set<String> = []
    @Published var keptIds: Set<String> = []
    @Published var isDeleting = false
    @Published var completionDeletionPhase: GuidedCleanupCompletionDeletionPhase = .idle
    @Published var completionDeletionMessage: String = ""
    /// Set when the user finishes the last item of a task AND another task
    /// remains. View renders a congrats screen until `continueAfterCheckpoint`
    /// is called.
    @Published var pendingCheckpointTaskIndex: Int? = nil
    /// Random CheckpointGif variant for the active checkpoint celebration.
    @Published private(set) var activeCheckpointGifVariant: CheckpointGifVariant? = nil
    /// Random completion-result GIF variant for the final completion screen.
    @Published private(set) var activeCompletionResultGifVariant: CompletionResultGifVariant? = nil
    /// Checkpoints the user has finished AND continued past (progress bar fill).
    @Published private(set) var passedCheckpointCount: Int = 0

    /// True when the orchestrator could not produce a viable task — the
    /// user has adjudicated every eligible photo. UI renders an empty
    /// state instead of an empty deck.
    @Published private(set) var isPoolExhausted: Bool = false

    /// Preview of the task `startNewTask()` would generate — the XP and
    /// storage the next round offers — computed on demand for the completion
    /// screen without mutating session state. `nil` when no viable next task
    /// exists (pool exhausted).
    @Published private(set) var nextTaskPreview: NextTaskPreview? = nil

    /// Per-task seen set: every asset ID that has been (or will be) presented
    /// in the current task across all checkpoints. Reset only when a brand
    /// new task is generated via `startNewTask()` — never mid-task. Used
    /// for within-task dedup only. Cross-task exclusion lives in
    /// `decisionsStore`; do not conflate the two.
    @Published private(set) var seenAssetIds: Set<String> = []

    // MARK: - Dependencies

    private let store: SimilarPhotosStore
    /// Cross-task / cross-launch source of truth for "user already decided".
    /// Reads feed the orchestrator's `excluding:`; writes happen at every
    /// swipe / unmark / undo / deletion completion. Survives app relaunch.
    private let decisionsStore: any DecisionsStore
    /// Checkpoints in the current task. Mutated when the user starts a brand
    /// new task via `startNewTask()` so the progress tracker re-renders with
    /// the new checkpoint set. Published so SwiftUI observes replacements.
    @Published private(set) var tasks: [CleanupTask]
    /// Session storage target from the resolved plan (`roundBytes`).
    private(set) var roundGoalBytes: Int64 = 0

    // MARK: - Undo

    private enum SwipeAction { case delete(String), keep(String) }
    private var history: [SwipeAction] = []

    // MARK: - Coin award bookkeeping

    /// Stable ids for this guided session. Combined with a checkpoint id they
    /// form the idempotency key ("{planId}:{taskId}:{checkpointId}") sent to
    /// the backend. Persisted in progress and reused on restore; regenerated
    /// only by `startNewTask()`.
    private var planId: String = UUID().uuidString
    private var taskId: String = UUID().uuidString
    /// Event ids already awarded. The relaunch / undo-recross guard: a
    /// checkpoint is awarded exactly once.
    private var awardedCheckpointIds: Set<String> = []
    /// Running recap of coins earned this session (sum of the optimistic
    /// per-checkpoint awards). Shown on the task summary — never re-awards.
    @Published private(set) var totalCoinsEarned: Int = 0

    // MARK: - Session outcome (for the persisted Shuffling-System history)
    /// Bytes actually deleted across this whole session (instrumentation only;
    /// does not affect coin/level formulas). Used to record MB cleaned.
    @Published private(set) var sessionBytesCleaned: Int64 = 0
    /// Count of assets deleted this session.
    private(set) var sessionDeletedCount: Int = 0
    /// Deleted bytes per category this session — for the dominant-category tag.
    private(set) var sessionDeletedBytesByCategory: [CleanupTaskCategory: Int64] = [:]
    /// Guard so a finished session is recorded to history exactly once.
    private var didRecordCompletion = false

    /// Category that contributed the most deleted bytes this session.
    var dominantSessionCategory: CleanupTaskCategory? {
        sessionDeletedBytesByCategory.max(by: { $0.value < $1.value })?.key ?? tasks.first?.category
    }

    /// Returns true the first time it's called per session; false afterward.
    /// Lets the view fire the completion record exactly once across the
    /// completion screen / back-arrow / onDisappear paths.
    func markCompletionRecorded() -> Bool {
        if didRecordCompletion { return false }
        didRecordCompletion = true
        return true
    }

    // MARK: - Init

    init(
        plan: TodayCleanupPlan,
        store: SimilarPhotosStore,
        decisionsStore: any DecisionsStore = UserDefaultsDecisionsStore.shared
    ) {
        self.store = store
        self.decisionsStore = decisionsStore
        self.tasks = plan.tasks
        self.roundGoalBytes = plan.roundBytes
        self.items = Self.itemsFromPlan(plan, store: store)
        self.isPoolExhausted = plan.isPoolExhausted
        // Every asset in the plan is destined to appear in some checkpoint
        // of this task, so seed the seen set upfront. Items currentItem
        // advances through are already covered; this also defends against
        // any future code path that hands the orchestrator items mid-task.
        self.seenAssetIds = Set(self.items.map { $0.id })

        restoreProgressIfMatching()
    }

    // MARK: - Derived

    var currentItem: GuidedItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var isComplete: Bool { currentIndex >= items.count }

    var totalMarked: Int { markedForDeletion.count }

    var totalBytesMarked: Int64 {
        items.filter { markedForDeletion.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

    var formattedBytesMarked: String {
        CleanupRound.formatBytes(totalBytesMarked)
    }

    // MARK: - Completion presentation (Abdul: animation/results screen support)

    var markedPhotoCount: Int {
        items.filter { markedForDeletion.contains($0.id) && $0.category.isPhotoCategory }.count
    }

    var markedVideoCount: Int {
        items.filter { markedForDeletion.contains($0.id) && $0.category.isVideoCategory }.count
    }

    var sessionProgressPercent: Int {
        let goal = max(roundGoalBytes, 1)
        let fraction = min(1.0, Double(totalBytesMarked) / Double(goal))
        let percent = Int((fraction * 100).rounded())
        if totalBytesMarked > 0 && percent == 0 { return 1 }
        return percent
    }

    var completionPhotoSubtitle: String {
        completionSubtitle(
            among: { $0.isPhotoCategory },
            fallback: "Photos Removed"
        )
    }

    var completionVideoSubtitle: String {
        completionSubtitle(
            among: { $0.isVideoCategory },
            fallback: "Videos Removed"
        )
    }

    private func completionSubtitle(
        among categoryFilter: (CleanupTaskCategory) -> Bool,
        fallback: String
    ) -> String {
        if let dominant = dominantMarkedCategory(where: categoryFilter) {
            return dominant.completionStatSubtitle
        }
        if let taskCategory = tasks.first(where: { categoryFilter($0.category) })?.category {
            return taskCategory.completionStatSubtitle
        }
        return fallback
    }

    private func dominantMarkedCategory(
        where categoryFilter: (CleanupTaskCategory) -> Bool
    ) -> CleanupTaskCategory? {
        var counts: [CleanupTaskCategory: Int] = [:]
        for item in items where markedForDeletion.contains(item.id) && categoryFilter(item.category) {
            counts[item.category, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var progressFraction: Double {
        guard !items.isEmpty else { return 0 }
        return Double(currentIndex) / Double(items.count)
    }

    var canUndo: Bool { !history.isEmpty }

    func reviewedCount(forTask taskIndex: Int) -> Int {
        let taskItems = items.filter { $0.taskIndex == taskIndex }
        return taskItems.filter { item in
            guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
            return idx < currentIndex
        }.count
    }

    func totalCount(forTask taskIndex: Int) -> Int {
        items.filter { $0.taskIndex == taskIndex }.count
    }

    func isTaskComplete(_ taskIndex: Int) -> Bool {
        reviewedCount(forTask: taskIndex) >= totalCount(forTask: taskIndex)
    }

    func activeTaskIndex() -> Int? {
        // While a checkpoint celebration is showing, the highlighted task
        // is the one the user just finished — the progress bar must not
        // auto-advance to the next task until "Continue to Next" is tapped.
        if let pending = pendingCheckpointTaskIndex {
            return pending
        }
        guard let current = currentItem else { return tasks.indices.last }
        return current.taskIndex
    }

    /// How many checkpoint nodes (0…tasks.count) are filled on the progress
    /// tracker. Fill advances on checkpoint confirmation, not mid-swipe.
    var completedCheckpointNodes: Int {
        if isComplete { return tasks.count }
        if let cp = pendingCheckpointTaskIndex { return cp + 1 }
        return passedCheckpointCount
    }

    /// Clears persisted session progress when leaving for the dashboard.
    func clearSessionState() {
        activeCompletionResultGifVariant = nil
        clearProgress()
    }

    // MARK: - Actions

    func swipeLeft() {
        guard let item = currentItem else { return }
        markedForDeletion.insert(item.id)
        keptIds.remove(item.id)
        history.append(.delete(item.id))
        decisionsStore.record(item.id, status: .pendingDelete)
        let completedTaskIdx = item.taskIndex
        currentIndex += 1
        // Heavy two-beat + afterglow — "decisive removal". Pairs with
        // the red ✗ button and leftward swipe. Deliberately distinct
        // from `cleanupKeep()` so the user feels which side committed.
        HapticManager.shared.cleanupDelete()
        if isComplete, activeCompletionResultGifVariant == nil {
            activeCompletionResultGifVariant = pickRandomCompletionResultGifVariant()
        }
        checkForCheckpoint(completedTaskIdx: completedTaskIdx)
        saveProgress()
    }

    func swipeRight() {
        guard let item = currentItem else { return }
        keptIds.insert(item.id)
        markedForDeletion.remove(item.id)
        history.append(.keep(item.id))
        decisionsStore.record(item.id, status: .kept)
        let completedTaskIdx = item.taskIndex
        currentIndex += 1
        // Single bright tick — "yes, save it". Pairs with the green ✓
        // button and rightward swipe. Brightness profile is the
        // opposite of `cleanupDelete()` (dull/low-sharpness) so the
        // two haptics read as unmistakable opposites by feel.
        HapticManager.shared.cleanupKeep()
        if isComplete, activeCompletionResultGifVariant == nil {
            activeCompletionResultGifVariant = pickRandomCompletionResultGifVariant()
        }
        checkForCheckpoint(completedTaskIdx: completedTaskIdx)
        saveProgress()
    }

    /// Called when a card's underlying asset can't be loaded (PHAsset
    /// vanished, thumbnail chain exhausted). Drop it from this VM's
    /// items AND from the global store so it doesn't reappear in any
    /// other surface; nudge currentIndex if the removal was at or
    /// before the cursor so the next render shows a different live
    /// card. Safe to call from a SwiftUI render callback.
    func pruneUnloadable(_ assetId: String) {
        guard let idx = items.firstIndex(where: { $0.id == assetId }) else { return }
        items.remove(at: idx)
        markedForDeletion.remove(assetId)
        keptIds.remove(assetId)
        if idx < currentIndex { currentIndex -= 1 }
        store.pruneUnloadableAsset(assetId)
        saveProgress()
    }

    /// If the just-finished item was the LAST one of its task AND another task
    /// still has items, surface the checkpoint celebration screen. Coins are
    /// NOT awarded here — they're awarded when the user confirms the
    /// checkpoint's cleanup (see `completeCheckpoint` / `deleteAllMarked`).
    private func checkForCheckpoint(completedTaskIdx: Int) {
        guard let next = currentItem else {
            // Deck exhausted — final checkpoint. Its coins are awarded at
            // completion via `deleteAllMarked`.
            return
        }
        if next.taskIndex != completedTaskIdx {
            pendingCheckpointTaskIndex = completedTaskIdx
            activeCheckpointGifVariant = Bool.random() ? .gif1 : .gif2
        }
    }

    /// Award a completed checkpoint's coins exactly once. `deletedIds` are the
    /// asset ids just removed for this checkpoint (empty if the user kept
    /// everything — coins are still earned from the review). The
    /// `awardedCheckpointIds` guard + backend `eventId` dedup make this safe
    /// under undo-recross and relaunch.
    private func awardCheckpointCoins(taskIndex: Int, deletedIds: Set<String>) {
        guard tasks.indices.contains(taskIndex) else { return }
        let checkpointId = tasks[taskIndex].id
        let eventId = "\(planId):\(taskId):\(checkpointId)"
        guard !awardedCheckpointIds.contains(eventId) else { return }
        awardedCheckpointIds.insert(eventId)

        let taskItems = items.filter { $0.taskIndex == taskIndex }
        let reviewedItemCount = taskItems.count            // checkpoint complete ⇒ all reviewed
        let deletedItems = taskItems.filter { deletedIds.contains($0.id) }
        let selectedItemCount = deletedItems.count
        let deletedBytes = deletedItems.reduce(Int64(0)) { $0 + $1.fileSize }

        var breakdown: [String: (bytes: Int64, reviewed: Int)] = [:]
        for item in taskItems {
            let key = item.category.coinCategoryKey
            var entry = breakdown[key] ?? (0, 0)
            entry.reviewed += 1
            if deletedIds.contains(item.id) { entry.bytes += item.fileSize }
            breakdown[key] = entry
        }
        let categoryBreakdown = breakdown.mapValues { CategoryStat(bytes: $0.bytes, reviewed: $0.reviewed) }

        let coins = ProgressMath.checkpointCoins(
            reviewed: reviewedItemCount,
            selected: selectedItemCount,
            deletedBytes: deletedBytes,
            breakdown: categoryBreakdown
        )
        totalCoinsEarned += coins

        ProgressManager.shared.awardCheckpointCoins(
            eventId: eventId,
            planId: planId,
            taskId: taskId,
            checkpointId: checkpointId,
            reviewedItemCount: reviewedItemCount,
            selectedItemCount: selectedItemCount,
            deletedBytes: deletedBytes,
            categoryBreakdown: categoryBreakdown
        )
        saveProgress()
    }

    /// Checkpoint celebration CTA: delete this checkpoint's marked items (if
    /// any), then award its coins immediately and continue. Returns false only
    /// if a non-empty deletion failed/was cancelled (no award, stay on screen).
    func completeCheckpoint(taskIndex: Int) async -> Bool {
        let toDelete = items.filter { $0.taskIndex == taskIndex && markedForDeletion.contains($0.id) }
        let deletedIds = Set(toDelete.map { $0.id })
        if !toDelete.isEmpty {
            let ok = await deleteMarkedItems(toDelete)
            guard ok else { return false }
        }
        awardCheckpointCoins(taskIndex: taskIndex, deletedIds: deletedIds)
        continueAfterCheckpoint()
        return true
    }

    func continueAfterCheckpoint() {
        if let idx = pendingCheckpointTaskIndex {
            // Advance the progress-bar fill past this checkpoint.
            passedCheckpointCount = max(passedCheckpointCount, idx + 1)
            // Review-based coins are earned for completing the checkpoint even
            // when nothing was deleted (kept all / skipped). Idempotent via
            // `awardedCheckpointIds`, so the delete path (which already awarded
            // in `completeCheckpoint`) is unaffected.
            awardCheckpointCoins(taskIndex: idx, deletedIds: [])
        }
        pendingCheckpointTaskIndex = nil
        activeCheckpointGifVariant = nil
        HapticManager.shared.impact(.light)
        saveProgress()
    }

    func ensureCompletionResultGifVariant() {
        if activeCompletionResultGifVariant == nil {
            activeCompletionResultGifVariant = pickRandomCompletionResultGifVariant()
        }
    }

    /// Live coin estimate for the checkpoint celebration, before the user
    /// confirms. Mirrors the award formula using the currently-marked items.
    func coinPreview(forTask taskIndex: Int) -> Int {
        guard tasks.indices.contains(taskIndex) else { return 0 }
        let taskItems = items.filter { $0.taskIndex == taskIndex }
        let selected = taskItems.filter { markedForDeletion.contains($0.id) }
        let deletedBytes = selected.reduce(Int64(0)) { $0 + $1.fileSize }
        var breakdown: [String: (bytes: Int64, reviewed: Int)] = [:]
        for item in taskItems {
            let key = item.category.coinCategoryKey
            var entry = breakdown[key] ?? (0, 0)
            entry.reviewed += 1
            if markedForDeletion.contains(item.id) { entry.bytes += item.fileSize }
            breakdown[key] = entry
        }
        let cb = breakdown.mapValues { CategoryStat(bytes: $0.bytes, reviewed: $0.reviewed) }
        return ProgressMath.checkpointCoins(
            reviewed: taskItems.count,
            selected: selected.count,
            deletedBytes: deletedBytes,
            breakdown: cb
        )
    }

    /// Award any checkpoints not yet credited when the task summary appears,
    /// so the recap reflects all earned coins (and none are lost if the user
    /// starts a new task without running the final delete). Uses the current
    /// marked items as the selection; the guard makes this safe alongside
    /// `deleteAllMarked`.
    func finalizeCompletion() {
        for t in tasks.indices {
            let selectedIds = Set(items.filter { $0.taskIndex == t && markedForDeletion.contains($0.id) }.map { $0.id })
            awardCheckpointCoins(taskIndex: t, deletedIds: selectedIds)
        }
    }

    /// Bank coins for every checkpoint the user has fully reviewed but not yet
    /// had credited — e.g. they finished a checkpoint then left via the back
    /// arrow / swipe-back instead of the celebration CTA. Incomplete
    /// checkpoints are skipped so partial reviews aren't over-credited.
    /// Idempotent via `awardedCheckpointIds`.
    func awardCompletedCheckpoints() {
        for t in tasks.indices where isTaskComplete(t) {
            let selectedIds = Set(items.filter { $0.taskIndex == t && markedForDeletion.contains($0.id) }.map { $0.id })
            awardCheckpointCoins(taskIndex: t, deletedIds: selectedIds)
        }
    }

    // MARK: - Per-Task Stats (for checkpoint screen)

    func markedCount(forTask taskIndex: Int) -> Int {
        items.filter { $0.taskIndex == taskIndex && markedForDeletion.contains($0.id) }.count
    }

    func keptCount(forTask taskIndex: Int) -> Int {
        items.filter { $0.taskIndex == taskIndex && keptIds.contains($0.id) }.count
    }

    func bytesMarked(forTask taskIndex: Int) -> Int64 {
        items.filter { $0.taskIndex == taskIndex && markedForDeletion.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

    // MARK: - Celebration Presentation

    func sessionBytesCleaned(throughTask taskIndex: Int) -> Int64 {
        guard taskIndex >= 0 else { return 0 }
        return (0...taskIndex).reduce(Int64(0)) { $0 + bytesMarked(forTask: $1) }
    }

    func checkpointCelebration(for taskIndex: Int) -> GuidedCleanupCelebrationContent {
        let checkpointBytes = bytesMarked(forTask: taskIndex)
        return GuidedCleanupCelebrationContent(
            title: "Checkpoint Completed!",
            subtitlePrefix: "You cleaned ",
            subtitleHighlight: CleanupRound.formatBytes(checkpointBytes),
            mascotAnimation: .checkpointGifCelebration(
                variant: activeCheckpointGifVariant ?? .gif1
            ),
            sessionBytesCleaned: sessionBytesCleaned(throughTask: taskIndex),
            sessionGoalBytes: roundGoalBytes,
            primaryButtonTitle: "Nice! Let's keep going",
            isSessionComplete: false,
            completedThroughTask: taskIndex
        )
    }

    func completionCelebration() -> GuidedCleanupCelebrationContent {
        GuidedCleanupCelebrationContent(
            title: "Task Complete!",
            subtitlePrefix: "You cleaned ",
            subtitleHighlight: formattedBytesMarked,
            mascotAnimation: .checkpointCelebration,
            sessionBytesCleaned: totalBytesMarked,
            sessionGoalBytes: roundGoalBytes,
            primaryButtonTitle: "Back to Dashboard",
            isSessionComplete: true,
            completedThroughTask: max(tasks.count - 1, 0)
        )
    }

    func undoLast() {
        guard let last = history.popLast() else { return }
        currentIndex = max(0, currentIndex - 1)
        switch last {
        case .delete(let id):
            markedForDeletion.remove(id)
            // User is taking the decision back — drop it from the store so
            // the photo can re-surface (the next swipe writes a fresh one).
            decisionsStore.remove(id)
        case .keep(let id):
            keptIds.remove(id)
            decisionsStore.remove(id)
        }
        // Undoing into a previous task should also clear a pending checkpoint
        // celebration that was triggered by completing that task.
        pendingCheckpointTaskIndex = nil
        activeCheckpointGifVariant = nil
        HapticManager.shared.impact(.light)
        saveProgress()
    }

    func unmarkItem(_ id: String) {
        // From the review grid: tapping a marked thumbnail says "actually
        // keep this." It's a real opinion, not an undo — record it as kept
        // so it stays out of future tasks.
        markedForDeletion.remove(id)
        keptIds.insert(id)
        decisionsStore.record(id, status: .kept)
        saveProgress()
    }

    // MARK: - Deletion

    /// Finishes the run: deletes any remaining marked items, then awards coins
    /// for every checkpoint not yet credited (the final checkpoint, which has
    /// no celebration screen, plus any the user reviewed but skipped
    /// confirming individually).
    func deleteAllMarked() async -> Bool {
        let toDelete = items.filter { markedForDeletion.contains($0.id) }
        let deletedIds = Set(toDelete.map { $0.id })
        let success = toDelete.isEmpty ? true : await deleteMarkedItems(toDelete)
        if success {
            for t in tasks.indices {
                awardCheckpointCoins(taskIndex: t, deletedIds: deletedIds)
            }
            clearProgress()
        }
        return success
    }

    /// Deletes marked items matching `predicate` (e.g. photos-only from completion review).
    func deleteMarked(matching predicate: (GuidedItem) -> Bool) async -> Bool {
        let toDelete = items.filter { markedForDeletion.contains($0.id) && predicate($0) }
        guard !toDelete.isEmpty else { return true }
        return await deleteMarkedItems(toDelete)
    }

    /// Deletes only the marked items for one task (used by the checkpoint
    /// "Delete N" button). Run continues afterward.
    func deleteMarkedForTask(taskIndex: Int) async -> Bool {
        let toDelete = items.filter {
            $0.taskIndex == taskIndex && markedForDeletion.contains($0.id)
        }
        guard !toDelete.isEmpty else { return true } // nothing to do — treat as success
        return await deleteMarkedItems(toDelete)
    }

    /// Fires when the user confirms the iOS PhotoKit delete sheet — the
    /// `performChanges` block only runs after they tap Delete.
    var onPhotoLibraryDeleteConfirmed: (() -> Void)?

    private var deletionMessageTask: Task<Void, Never>?

    @MainActor
    func beginDeletionStatusMessages(for filter: GuidedCleanupReviewFilter) {
        deletionMessageTask?.cancel()
        let messages = GuidedCleanupDeletionMessages.statusMessages(for: filter)
        completionDeletionMessage = messages.first ?? "Deletion is in progress."
        completionDeletionPhase = .running

        deletionMessageTask = Task { @MainActor in
            for message in messages.dropFirst() {
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled else { return }
                completionDeletionMessage = message
            }
        }
    }

    @MainActor
    func endDeletionStatusMessages() {
        deletionMessageTask?.cancel()
        deletionMessageTask = nil
    }

    @MainActor
    func showCompletionDeletionSuccess() {
        endDeletionStatusMessages()
        completionDeletionPhase = .success
    }

    @MainActor
    func resetCompletionDeletionUI() {
        endDeletionStatusMessages()
        completionDeletionPhase = .idle
        completionDeletionMessage = ""
    }

    /// Shared deletion pipeline. Triggers ONE system dialog, then does the
    /// store bookkeeping for the provided items.
    private func deleteMarkedItems(_ markedItems: [GuidedItem]) async -> Bool {
        guard !markedItems.isEmpty else { return false }
        isDeleting = true

        var photoIds: [String] = []
        var screenshotIds: [String] = []
        var videoIds: [String] = []

        for item in markedItems {
            switch item.category {
            case .duplicatePhotos, .similarPhotos, .blurryPhotos, .otherPhotos:
                photoIds.append(item.id)
            case .similarScreenshots, .screenshots:
                screenshotIds.append(item.id)
            case .similarVideos, .screenRecordings, .shortRecordings, .longVideos:
                videoIds.append(item.id)
            case .promoEmails:
                break
            }
        }

        let allIds = photoIds + screenshotIds + videoIds
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: allIds, options: nil
        )
        guard fetchResult.count > 0 else {
            isDeleting = false
            return false
        }

        do {
            let onConfirmed = onPhotoLibraryDeleteConfirmed
            try await PHPhotoLibrary.shared().performChanges {
                if let onConfirmed {
                    if Thread.isMainThread {
                        onConfirmed()
                    } else {
                        DispatchQueue.main.sync(execute: onConfirmed)
                    }
                }
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
            onPhotoLibraryDeleteConfirmed = nil
        } catch {
            onPhotoLibraryDeleteConfirmed = nil
            print("[GuidedCleanup] Delete failed: \(error)")
            isDeleting = false
            return false
        }

        let deletedSet = Set(allIds)

        // Accumulate session outcome for the persisted history (bytes actually
        // removed in this batch + per-category split). Instrumentation only.
        let batchItems = markedItems.filter { deletedSet.contains($0.id) }
        sessionBytesCleaned += batchItems.reduce(Int64(0)) { $0 + $1.fileSize }
        sessionDeletedCount += batchItems.count
        for item in batchItems {
            sessionDeletedBytesByCategory[item.category, default: 0] += item.fileSize
        }

        store.subtractFromStableClutter(assetIds: deletedSet)

        if !photoIds.isEmpty {
            let pSet = Set(photoIds)
            for gi in store.groups.indices {
                store.groups[gi].items.removeAll { pSet.contains($0.assetId) }
            }
            store.groups.removeAll { $0.items.count < 2 }
        }

        if !screenshotIds.isEmpty {
            let sSet = Set(screenshotIds)
            for gi in store.screenshotGroups.indices {
                store.screenshotGroups[gi].items.removeAll { sSet.contains($0.assetId) }
            }
            store.screenshotGroups.removeAll { $0.items.count < 2 }
        }

        if !videoIds.isEmpty {
            let vSet = Set(videoIds)
            for gi in store.videoGroups.indices {
                store.videoGroups[gi].items.removeAll { vSet.contains($0.assetId) }
            }
            store.videoGroups.removeAll { $0.items.count < 2 }
        }

        store.screenshotScanResult.screenshots.removeAll { deletedSet.contains($0.assetId) }
        store.screenshotScanResult.totalBytes = store.screenshotScanResult.screenshots.reduce(0) { $0 + $1.fileSize }
        store.screenRecordingScanResult.screenshots.removeAll { deletedSet.contains($0.assetId) }
        store.screenRecordingScanResult.totalBytes = store.screenRecordingScanResult.screenshots.reduce(0) { $0 + $1.fileSize }
        store.shortVideoScanResult.screenshots.removeAll { deletedSet.contains($0.assetId) }
        store.shortVideoScanResult.totalBytes = store.shortVideoScanResult.screenshots.reduce(0) { $0 + $1.fileSize }
        store.longVideoScanResult.screenshots.removeAll { deletedSet.contains($0.assetId) }
        store.longVideoScanResult.totalBytes = store.longVideoScanResult.screenshots.reduce(0) { $0 + $1.fileSize }

        for id in deletedSet { store.analyzedIndex.removeValue(forKey: id) }
        SimilarPersistence.deletePhotos(assetIds: Array(deletedSet))
        store.persistScanSummary()
        store.recomputeDashboardSnapshot()

        let bytesFreed = totalBytesMarked

        BeeViewModel.shared.registerCleanup(
            count: deletedSet.count,
            source: .photoDelete
        )
        // Lifetime stats + streak + backend activity-log entry.
        HiveStatsManager.shared.recordDeletion(
            itemCount: deletedSet.count,
            bytesSaved: bytesFreed
        )

        // Clear the just-deleted IDs from the marked set; everything else
        // (e.g. items marked in later tasks) stays so the run can continue.
        markedForDeletion.subtract(deletedSet)

        // Transition decisions from .pendingDelete to .deleted. PHPhotoLibrary
        // confirmed removal, so reconciliation will never re-surface these.
        for id in deletedSet {
            decisionsStore.record(id, status: .deleted)
        }
        saveProgress()

        isDeleting = false
        return true
    }

    // MARK: - Persistence

    private static let progressKey = "GuidedCleanupViewModel.savedProgress.v1"

    /// Stable fingerprint of the current item set — order-sensitive. Used to
    /// guard against restoring stale progress onto a different plan.
    private var itemsSignature: String {
        let joined = items.map { $0.id }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func saveProgress() {
        // Nothing meaningful done yet → no need to write.
        if currentIndex == 0 && markedForDeletion.isEmpty && keptIds.isEmpty {
            clearProgress()
            return
        }
        let snapshot = GuidedCleanupProgress(
            signature: itemsSignature,
            currentIndex: currentIndex,
            currentAssetId: currentItem?.id,
            markedForDeletion: Array(markedForDeletion),
            keptIds: Array(keptIds),
            pendingCheckpointTaskIndex: pendingCheckpointTaskIndex,
            planId: planId,
            taskId: taskId,
            awardedCheckpointIds: Array(awardedCheckpointIds),
            totalCoinsEarned: totalCoinsEarned,
            passedCheckpointCount: passedCheckpointCount,
            activeCheckpointGifVariant: activeCheckpointGifVariant,
            activeCompletionResultGifVariant: activeCompletionResultGifVariant
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.progressKey)
        }
    }

    private func clearProgress() {
        UserDefaults.standard.removeObject(forKey: Self.progressKey)
    }

    private func restoreProgressIfMatching() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.progressKey),
            let saved = try? JSONDecoder().decode(GuidedCleanupProgress.self, from: data)
        else {
            return
        }

        // Marked/kept are global asset-id sets — safe to restore even when
        // the plan was rebuilt with `excluding: decidedIds`. Items not in
        // the current items list just sit silently in the set and don't
        // render anywhere.
        markedForDeletion = Set(saved.markedForDeletion)
        keptIds = Set(saved.keptIds)

        // Restore award bookkeeping so a relaunch mid-task can't re-award an
        // already-credited checkpoint. Reuse the saved planId so event ids
        // stay stable; fall back to the freshly-generated one for old data.
        if !saved.planId.isEmpty { planId = saved.planId }
        if !saved.taskId.isEmpty { taskId = saved.taskId }
        awardedCheckpointIds = Set(saved.awardedCheckpointIds)
        totalCoinsEarned = saved.totalCoinsEarned

        // Anchor the cursor by asset ID when possible. The saved
        // currentIndex is almost always wrong after a re-entry (the plan
        // excludes already-decided items, shrinking the list), but the
        // saved currentAssetId still points to the user's last visible
        // card if it wasn't itself decided.
        if let savedId = saved.currentAssetId,
           let idx = items.firstIndex(where: { $0.id == savedId }) {
            currentIndex = idx
        } else {
            currentIndex = min(max(saved.currentIndex, 0), items.count)
        }

        // Clamp pendingCheckpointTaskIndex against the current task list
        // so a stale task index can't crash the checkpoint view.
        if let p = saved.pendingCheckpointTaskIndex, tasks.indices.contains(p) {
            pendingCheckpointTaskIndex = p
        } else {
            pendingCheckpointTaskIndex = nil
        }

        // Abdul: restore checkpoint + completion animation state.
        passedCheckpointCount = saved.passedCheckpointCount ?? 0
        if saved.pendingCheckpointTaskIndex != nil {
            activeCheckpointGifVariant = saved.activeCheckpointGifVariant ?? .gif1
        }
        if currentIndex >= items.count {
            activeCompletionResultGifVariant =
                saved.activeCompletionResultGifVariant ?? pickRandomCompletionResultGifVariant()
        }
        // History (for undo) is intentionally not restored — only forward
        // progress is durable; undo is a within-session affordance.
    }

    // MARK: - New Task

    /// Resolve (but don't start) the next task so the completion screen can
    /// preview its XP + storage. Mirrors `startNewTask()`'s plan build with
    /// no state mutation or pending-delete reconciliation. `nil` when no
    /// viable next task remains.
    func refreshNextTaskPreview() {
        let plan = CleanupOrchestrator.shared.buildResolvedPlan(
            from: store.dashboardSnapshot,
            cleanScore: HiveStatsManager.shared.cleanScore,
            store: store,
            excluding: decisionsStore.allDecidedIds
        )
        nextTaskPreview = !plan.tasks.isEmpty
            ? NextTaskPreview(bytes: plan.formattedRoundBytes)
            : nil
    }

    /// Builds a fresh plan via the existing orchestrator algorithm and
    /// restarts the session in place. `seenAssetIds` is within-task dedup
    /// only — reset is correct. Cross-task exclusion lives in
    /// `decisionsStore` and is intentionally *not* cleared here.
    func startNewTask() {
        // 1. Ephemeral within-task seen set is per-task; reset is correct.
        seenAssetIds = []

        // 2. Reconcile prior pendingDelete decisions before building. If
        // the user cancelled the iOS delete sheet more than 24h ago and
        // the asset is still in the library, drop the decision so it
        // becomes eligible again — otherwise it would be silently excluded
        // forever.
        reconcilePendingDeletes()

        // 3. Generate a fresh plan, excluding every prior decision (kept,
        // pendingDelete, deleted). This is what fixes the resurfacing bug.
        let snapshot = store.dashboardSnapshot
        let cleanScore = HiveStatsManager.shared.cleanScore
        let newPlan = CleanupOrchestrator.shared.buildResolvedPlan(
            from: snapshot,
            cleanScore: cleanScore,
            store: store,
            excluding: decisionsStore.allDecidedIds
        )

        // 4. Clear all per-task state, then load the new plan's items.
        // A brand-new session gets a fresh planId + empty award set so its
        // checkpoints are credited independently of the previous task.
        currentIndex = 0
        markedForDeletion = []
        keptIds = []
        history = []
        pendingCheckpointTaskIndex = nil
        planId = UUID().uuidString
        taskId = UUID().uuidString
        awardedCheckpointIds = []
        activeCheckpointGifVariant = nil
        activeCompletionResultGifVariant = nil
        passedCheckpointCount = 0
        totalCoinsEarned = 0
        sessionBytesCleaned = 0
        sessionDeletedCount = 0
        sessionDeletedBytesByCategory = [:]
        didRecordCompletion = false

        tasks = newPlan.tasks
        roundGoalBytes = newPlan.roundBytes
        items = Self.itemsFromPlan(newPlan, store: store)
        seenAssetIds = Set(items.map { $0.id })
        isPoolExhausted = newPlan.isPoolExhausted

        clearProgress()
        HapticManager.shared.impact(.medium)
    }

    /// Walks every `.pendingDelete` decision and asks PhotoKit whether the
    /// asset is still in the library. If it is — and the decision is older
    /// than 24h — the user almost certainly cancelled the system delete
    /// sheet, so we drop the decision so the photo can re-surface. Newer
    /// pendings are left alone (the deletion may still be in flight or
    /// the user may retry shortly).
    private func reconcilePendingDeletes() {
        let pending = decisionsStore.pendingDeleteIds
        guard !pending.isEmpty else { return }

        let fetched = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(pending),
            options: nil
        )
        var stillInLibrary = Set<String>()
        fetched.enumerateObjects { asset, _, _ in
            stillInLibrary.insert(asset.localIdentifier)
        }

        let now = Date()
        for id in pending where stillInLibrary.contains(id) {
            guard let decidedAt = decisionsStore.decidedAt(for: id) else { continue }
            if now.timeIntervalSince(decidedAt) > 86_400 {
                decisionsStore.remove(id)
            }
        }
    }

    // MARK: - Item Resolution

    /// Pull GuidedItems out of a plan. Prefers pre-resolved itemRefs (the
    /// checkpoint flow); falls back to walking store collections for older
    /// plans without refs.
    private static func itemsFromPlan(
        _ plan: TodayCleanupPlan,
        store: SimilarPhotosStore
    ) -> [GuidedItem] {
        let hasItemRefs = plan.tasks.contains { !$0.itemRefs.isEmpty }
        if hasItemRefs {
            var resolved: [GuidedItem] = []
            for (taskIdx, task) in plan.tasks.enumerated() {
                for ref in task.itemRefs {
                    resolved.append(GuidedItem(
                        id: ref.assetId,
                        category: ref.category,
                        taskIndex: taskIdx,
                        isBest: ref.isBest,
                        fileSize: ref.fileSize
                    ))
                }
            }
            return resolved
        }
        return resolveItems(tasks: plan.tasks, store: store)
    }

    private static func resolveItems(
        tasks: [CleanupTask],
        store: SimilarPhotosStore
    ) -> [GuidedItem] {
        var result: [GuidedItem] = []

        for (taskIdx, task) in tasks.enumerated() {
            let n = extractCount(from: task.title)

            switch task.category {
            case .duplicatePhotos:
                // Groups with confidence >= 0.85, non-best items
                let groups = store.groups.filter { $0.confidence >= 0.85 }
                appendGroupItems(
                    from: Array(groups.prefix(n)),
                    category: task.category,
                    taskIndex: taskIdx,
                    into: &result
                )

            case .similarPhotos:
                // Groups with confidence < 0.85, non-best items
                let groups = store.groups.filter { $0.confidence < 0.85 }
                appendGroupItems(
                    from: Array(groups.prefix(n)),
                    category: task.category,
                    taskIndex: taskIdx,
                    into: &result
                )

            case .similarScreenshots:
                appendGroupItems(
                    from: Array(store.screenshotGroups.prefix(n)),
                    category: task.category,
                    taskIndex: taskIdx,
                    into: &result
                )

            case .screenshots:
                let assets = Array(store.screenshotScanResult.screenshots.prefix(n))
                for asset in assets {
                    result.append(GuidedItem(
                        id: asset.assetId,
                        category: task.category,
                        taskIndex: taskIdx,
                        isBest: false,
                        fileSize: asset.fileSize
                    ))
                }

            case .blurryPhotos:
                let blurry = store.blurryPhotos
                let assets = Array(blurry.prefix(n))
                for asset in assets {
                    result.append(GuidedItem(
                        id: asset.assetId,
                        category: task.category,
                        taskIndex: taskIdx,
                        isBest: false,
                        fileSize: asset.fileSize
                    ))
                }

            case .similarVideos:
                appendGroupItems(
                    from: Array(store.videoGroups.prefix(n)),
                    category: task.category,
                    taskIndex: taskIdx,
                    into: &result
                )

            case .screenRecordings:
                let assets = Array(store.screenRecordingScanResult.screenshots.prefix(n))
                for asset in assets {
                    result.append(GuidedItem(
                        id: asset.assetId,
                        category: task.category,
                        taskIndex: taskIdx,
                        isBest: false,
                        fileSize: asset.fileSize
                    ))
                }

            case .shortRecordings:
                let assets = Array(store.shortVideoScanResult.screenshots.prefix(n))
                for asset in assets {
                    result.append(GuidedItem(
                        id: asset.assetId,
                        category: task.category,
                        taskIndex: taskIdx,
                        isBest: false,
                        fileSize: asset.fileSize
                    ))
                }

            case .longVideos:
                let assets = Array(store.longVideoScanResult.screenshots.prefix(n))
                for asset in assets {
                    result.append(GuidedItem(
                        id: asset.assetId,
                        category: task.category,
                        taskIndex: taskIdx,
                        isBest: false,
                        fileSize: asset.fileSize
                    ))
                }

            case .otherPhotos, .promoEmails:
                break
            }
        }

        return result
    }

    private static func appendGroupItems(
        from groups: [SimilarGroupVM],
        category: CleanupTaskCategory,
        taskIndex: Int,
        into result: inout [GuidedItem]
    ) {
        for group in groups {
            for item in group.items {
                result.append(GuidedItem(
                    id: item.assetId,
                    category: category,
                    taskIndex: taskIndex,
                    isBest: item.isBest,
                    fileSize: item.fileSize
                ))
            }
        }
    }

    private static func extractCount(from title: String) -> Int {
        let scanner = Scanner(string: title)
        var value: Int = 0
        if scanner.scanInt(&value) { return max(value, 1) }
        return 1
    }

    private func pickRandomCompletionResultGifVariant() -> CompletionResultGifVariant {
        CompletionResultGifVariant.allCases.randomElement() ?? .smiling
    }
}
