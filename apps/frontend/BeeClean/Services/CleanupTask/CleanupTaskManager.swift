import SwiftUI

// MARK: - Cleanup Task Manager (Shuffling System orchestrator)
//
// The single owner of active-task persistence + rotation + history. Wraps the
// EXISTING generator (CleanupOrchestrator) — it never invents tasks, it only
// persists/validates/rotates what the generator produces. UI reads `activeTask`
// + `recentCompleted` and calls these methods; it contains no task logic.

@MainActor
final class CleanupTaskManager: ObservableObject {
    static let shared = CleanupTaskManager()

    /// The persisted current task shown on the dashboard. Survives launches.
    @Published private(set) var activeTask: ActiveCleanupTask?
    /// The 2 most-recent completed tasks (newest first) for the home stack.
    @Published private(set) var recentCompleted: [CompletedCleanupTask] = []

    private let service = CleanupTaskService.shared

    /// Executable plan (with itemRefs) for launching cleanup. In-memory only —
    /// re-resolved lazily on cold launch. The displayed snapshot stays stable.
    private var resolvedPlanCache: TodayCleanupPlan?

    /// Weak handle to the store + last clean score so completion can rotate
    /// forward without the View having to thread them through.
    private weak var storeRef: SimilarPhotosStore?
    private var lastCleanScore: Int = 0

    /// Guards against recording the same finished session more than once.
    private var isRecording = false

    private static let mirrorKey = "cleanupTask.activeMirror.v1"
    private static let completedMirrorKey = "cleanupTask.recentCompletedMirror.v1"

    private init() {
        activeTask = loadMirror()
        recentCompleted = loadCompletedMirror()
    }

    /// The number the next generated active task should carry. Client-owned and
    /// deterministic: one more than the most-recent completion (recentCompleted
    /// is newest-first), or 1 when nothing has been completed yet. This makes
    /// the rolling stack advance reliably without depending on a backend
    /// round-trip.
    private var nextNumber: Int { (recentCompleted.first?.taskNumber ?? 0) + 1 }

    // MARK: - Load / validate

    /// Load the persisted active task (server authoritative, UserDefaults
    /// mirror for instant/offline render). Generates one only when none exists
    /// and there is clutter to clean.
    func loadActiveTask(store: SimilarPhotosStore, cleanScore: Int) async {
        storeRef = store
        lastCleanScore = cleanScore

        // Local-first: render whatever we last persisted instantly.
        if activeTask == nil { activeTask = loadMirror() }
        if recentCompleted.isEmpty { recentCompleted = loadCompletedMirror() }

        // Reconcile with the backend WITHOUT regressing the visible stack.
        // Adopt the server's active task only if it's at least as advanced as
        // ours (prevents a stale "#1" row from undoing local rotation).
        if let server = await service.fetchActiveTask(),
           server.taskNumber >= (activeTask?.taskNumber ?? 0) {
            activeTask = server
            persistMirror(server)
            resolvedPlanCache = nil
        }

        // Only overwrite the greyed history when the backend actually has rows;
        // an empty/failed fetch must never wipe the local stack.
        let history = await service.fetchHistory()
        if !history.isEmpty {
            recentCompleted = Array(history.prefix(2))
            persistCompletedMirror()
        }

        // Nothing persisted anywhere yet — generate the first task.
        if activeTask == nil, store.dashboardSnapshot.totalClutterBytes > 0 {
            await generateNextTask(store: store, cleanScore: cleanScore)
        }
    }

    /// Re-validate the active task after the library changes (e.g. the user
    /// deleted assets outside the cleanup flow). Only regenerates when the
    /// current task is no longer viable — otherwise the displayed snapshot
    /// stays stable (no random changes on every dashboard appearance).
    func validateActiveTask(store: SimilarPhotosStore, cleanScore: Int) async {
        storeRef = store
        lastCleanScore = cleanScore

        guard store.dashboardSnapshot.totalClutterBytes > 0 else {
            activeTask = nil
            resolvedPlanCache = nil
            persistMirror(nil)
            return
        }

        let plan = buildPlan(store: store, cleanScore: cleanScore)
        if plan.tasks.isEmpty || plan.isPoolExhausted {
            // Current task can't be satisfied anymore — rotate to a fresh one
            // (or clear if truly nothing remains).
            await generateNextTask(store: store, cleanScore: cleanScore)
        } else if activeTask == nil {
            await generateNextTask(store: store, cleanScore: cleanScore)
        } else {
            // Still viable — refresh the executable plan, keep the snapshot.
            resolvedPlanCache = plan
        }
    }

    // MARK: - Generate (wraps the existing generator)

    func generateNextTask(store: SimilarPhotosStore, cleanScore: Int) async {
        storeRef = store
        lastCleanScore = cleanScore

        let plan = buildPlan(store: store, cleanScore: cleanScore)
        guard !plan.tasks.isEmpty else {
            activeTask = nil
            resolvedPlanCache = nil
            persistMirror(nil)
            return
        }

        resolvedPlanCache = plan
        let number = nextNumber
        let category = Self.dominantCategory(in: plan)
        let coins = ProgressMath.estimatedTaskCoins(for: plan.tasks)
        let mb = Double(plan.roundBytes) / 1_000_000
        let level = ProgressManager.shared.currentLevel

        // Set the local active task IMMEDIATELY with the client-owned number so
        // the stack advances regardless of the backend round-trip.
        let local = ActiveCleanupTask(
            taskNumber: number,
            taskTitle: "Quick Cleanup",
            taskType: "quick_cleanup",
            category: category.rawValue,
            estimatedMB: mb,
            estimatedCoins: coins,
            level: level,
            status: "active",
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
        activeTask = local
        persistMirror(local)

        // Best-effort persist to the backend with our authoritative number.
        let snapshot = ActiveTaskUpsert(
            taskNumber: number,
            taskTitle: "Quick Cleanup",
            taskType: "quick_cleanup",
            category: category.rawValue,
            estimatedMB: mb,
            estimatedCoins: coins,
            level: level
        )
        if let saved = await service.upsertActiveTask(snapshot), saved.taskNumber == number {
            activeTask = saved
            persistMirror(saved)
        }
    }

    /// The executable plan for launching guided cleanup (cached, else resolved).
    func resolvedPlanForLaunch(store: SimilarPhotosStore, cleanScore: Int) -> TodayCleanupPlan {
        if let cached = resolvedPlanCache, !cached.tasks.isEmpty { return cached }
        let plan = buildPlan(store: store, cleanScore: cleanScore)
        resolvedPlanCache = plan
        return plan
    }

    // MARK: - Complete / rotate

    /// Record the finished session in history and immediately rotate to the
    /// next active task. Idempotent per session via `isRecording`.
    func completeActiveTask(result: CompletedTaskResult) async {
        guard !isRecording else { return }
        isRecording = true
        defer { isRecording = false }

        // The number of the task being completed (client-owned).
        let n = activeTask?.taskNumber ?? nextNumber
        // Record the task's advertised MB (what the card showed), not the
        // actual-deleted bytes — a task can be completed by reviewing/keeping
        // without deleting, which would otherwise save 0 MB.
        let mb = activeTask?.estimatedMB ?? result.mbReviewed

        // Advance the visible stack LOCALLY first — this is what makes the
        // greyed rows + rotation work even if the backend call fails.
        let localCompleted = CompletedCleanupTask(
            taskNumber: n,
            taskTitle: result.taskTitle,
            taskType: result.taskType,
            category: result.category,
            mbReviewed: mb,
            coinsEarned: result.coinsEarned,
            levelAtCompletion: result.levelAtCompletion,
            assetCount: result.assetCount,
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
        recentCompleted = Array(([localCompleted] + recentCompleted).prefix(2))
        persistCompletedMirror()
        activeTask = nil
        persistMirror(nil)
        resolvedPlanCache = nil

        // Best-effort durable write (for View All); replace the local row with
        // the server's for an accurate completedAt when it succeeds.
        let request = CompletedTaskRequest(
            taskNumber: n,
            taskTitle: result.taskTitle,
            taskType: result.taskType,
            category: result.category,
            mbReviewed: mb,
            coinsEarned: result.coinsEarned,
            levelAtCompletion: result.levelAtCompletion,
            assetCount: result.assetCount
        )
        if let serverCompleted = await service.completeTask(request) {
            recentCompleted = recentCompleted.map { $0.taskNumber == n ? serverCompleted : $0 }
            persistCompletedMirror()
        }

        // Rotate forward to Task #(n+1).
        if let store = storeRef {
            await generateNextTask(store: store, cleanScore: lastCleanScore)
        }
        // If no store handle yet, the next dashboard appearance regenerates.
    }

    // MARK: - History

    func historyGroupedByDay() async -> [DayGroup] {
        let items = await service.fetchHistory()
        let cal = Calendar.current
        var buckets: [Date: [CompletedCleanupTask]] = [:]
        var order: [Date] = []   // newest-first (items are already sorted desc)
        for item in items {
            let day = cal.startOfDay(for: item.completedDate ?? Date())
            if buckets[day] == nil { buckets[day] = []; order.append(day) }
            buckets[day]?.append(item)
        }
        return order.map { day in
            let its = buckets[day] ?? []
            return DayGroup(
                id: ISO8601DateFormatter().string(from: day),
                label: Self.dayLabel(day, calendar: cal),
                items: its,
                totalMB: its.reduce(0) { $0 + $1.mbReviewed },
                totalCoins: its.reduce(0) { $0 + $1.coinsEarned },
                count: its.count
            )
        }
    }

    // MARK: - Helpers

    private func buildPlan(store: SimilarPhotosStore, cleanScore: Int) -> TodayCleanupPlan {
        CleanupOrchestrator.shared.buildResolvedPlan(
            from: store.dashboardSnapshot,
            cleanScore: cleanScore,
            store: store,
            excluding: UserDefaultsDecisionsStore.shared.allDecidedIds
        )
    }

    static func dominantCategory(in plan: TodayCleanupPlan) -> CleanupTaskCategory {
        var byCat: [CleanupTaskCategory: Int64] = [:]
        for task in plan.tasks {
            for ref in task.itemRefs { byCat[ref.category, default: 0] += ref.fileSize }
        }
        return byCat.max(by: { $0.value < $1.value })?.key
            ?? plan.tasks.first?.category
            ?? .otherPhotos
    }

    private static func dayLabel(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year) ? "MMMM d" : "MMMM d, yyyy"
        return f.string(from: day)
    }

    private func persistMirror(_ task: ActiveCleanupTask?) {
        if let task, let data = try? JSONEncoder().encode(task) {
            UserDefaults.standard.set(data, forKey: Self.mirrorKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.mirrorKey)
        }
    }

    private func loadMirror() -> ActiveCleanupTask? {
        guard let data = UserDefaults.standard.data(forKey: Self.mirrorKey) else { return nil }
        return try? JSONDecoder().decode(ActiveCleanupTask.self, from: data)
    }

    private func persistCompletedMirror() {
        if let data = try? JSONEncoder().encode(recentCompleted) {
            UserDefaults.standard.set(data, forKey: Self.completedMirrorKey)
        }
    }

    private func loadCompletedMirror() -> [CompletedCleanupTask] {
        guard let data = UserDefaults.standard.data(forKey: Self.completedMirrorKey) else { return [] }
        return (try? JSONDecoder().decode([CompletedCleanupTask].self, from: data)) ?? []
    }
}
