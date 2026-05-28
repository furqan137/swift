import Foundation
import SwiftUI

// MARK: - Hive Stats Manager
/// Lightweight singleton tracking lifetime gamification stats via @AppStorage.
@MainActor
final class HiveStatsManager: ObservableObject {

    static let shared = HiveStatsManager()
    private init() {
        // Kick off initial cache refresh asynchronously
        Task { await refreshPendingItemCount() }
    }

    // MARK: - Cached Values (non-blocking)

    /// Cached pending item count. Updated asynchronously via refreshPendingItemCount().
    @Published private(set) var cachedPendingItemCount: Int = 0

    /// Cached clean score. Updated asynchronously via refreshCleanScore().
    @Published private(set) var cachedCleanScore: Int = 0

    // MARK: - Persisted Stats

    @AppStorage("hive_lifetimeItemsCleaned") var lifetimeItemsCleaned: Int = 0
    @AppStorage("hive_lifetimeBytesSaved") var lifetimeBytesSavedRaw: String = "0"
    @AppStorage("hive_totalScansCompleted") var totalScansCompleted: Int = 0
    @AppStorage("hive_currentStreak") var currentStreak: Int = 0
    @AppStorage("hive_lastCleanDateRaw") var lastCleanDateRaw: Double = 0
    @AppStorage("hive_bestStreak") var bestStreak: Int = 0

    // MARK: - 30-Day Reset Journey
    //
    // Set on the user's first cleanup ever; the journey then runs as a
    // 30-day arc the user can re-trigger. Day 1 starts at 24h after the
    // start, so the first day of a fresh install reads as "Day 1 of 30"
    // not "Day 0".
    @AppStorage("hive_resetStartTimestamp") var resetStartTimestamp: Double = 0

    // MARK: - Today's bucket (rolls on calendar day change)
    @AppStorage("hive_dailyKey") var dailyKey: String = ""
    @AppStorage("hive_dailyBytesRaw") var dailyBytesRaw: String = "0"
    @AppStorage("hive_dailyItems") var dailyItems: Int = 0

    // MARK: - Personal records
    @AppStorage("hive_bestDayBytesRaw") var bestDayBytesRaw: String = "0"
    @AppStorage("hive_bestDayItems") var bestDayItems: Int = 0
    @AppStorage("hive_bestSessionItems") var bestSessionItems: Int = 0
    @AppStorage("hive_bestSessionBytesRaw") var bestSessionBytesRaw: String = "0"

    // MARK: - Weekly history (last 7 day-keys → bytes/items)
    //
    // Stored as a single JSON string instead of a Dictionary @AppStorage
    // (which is not natively supported). Truncated to the last 8 entries
    // on every write so the value never grows beyond a few hundred bytes.
    @AppStorage("hive_weekHistoryRaw") var weekHistoryRaw: String = "{}"

    // MARK: - Milestones (comma-separated list of unlocked ids)
    @AppStorage("hive_milestonesUnlockedRaw") var milestonesUnlockedRaw: String = ""

    // MARK: - BeeClean Coins
    //
    // Coins are the single ranking metric on the leaderboard and the
    // currency of the BitePal shop. The total balance is derived from
    // two parts:
    //
    //   • Earned automatically as lifetimeBytesSaved accrues — one coin
    //     per 10 MB freed. No extra plumbing in `recordCleanup` needed.
    //   • A persisted `bonusCoins` integer that captures grants
    //     (achievements, daily bonuses) minus spends (BitePal purchases).
    //     Allowed to go negative — `coinsBalance` clamps at zero so a
    //     purchase that costs more than the auto-accrued slice debits
    //     against future cleanups instead of failing outright.
    @AppStorage("hive_bonusCoins") var bonusCoins: Int = 0

    /// Coins balance shown in the top-nav pill, BitePal header, and
    /// leaderboard rows.
    var coinsBalance: Int {
        let earned = Int(lifetimeBytesSaved / 10_000_000)
        return max(0, earned + bonusCoins)
    }

    /// Grant N coins (achievement, daily bonus, etc).
    func grantCoins(_ amount: Int) {
        guard amount > 0 else { return }
        bonusCoins += amount
        objectWillChange.send()
    }

    /// Spend N coins. Returns `false` and does nothing if the balance
    /// would go negative.
    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard amount > 0 else { return true }
        guard coinsBalance >= amount else { return false }
        bonusCoins -= amount
        objectWillChange.send()
        return true
    }

    // MARK: - Computed

    var lifetimeBytesSaved: Int64 {
        get { Int64(lifetimeBytesSavedRaw) ?? 0 }
        set { lifetimeBytesSavedRaw = String(newValue) }
    }

    var lastCleanDate: Date? {
        lastCleanDateRaw > 0 ? Date(timeIntervalSince1970: lastCleanDateRaw) : nil
    }

    var dailyBytes: Int64 {
        get { Int64(dailyBytesRaw) ?? 0 }
        set { dailyBytesRaw = String(newValue) }
    }

    var bestDayBytes: Int64 {
        get { Int64(bestDayBytesRaw) ?? 0 }
        set { bestDayBytesRaw = String(newValue) }
    }

    var bestSessionBytes: Int64 {
        get { Int64(bestSessionBytesRaw) ?? 0 }
        set { bestSessionBytesRaw = String(newValue) }
    }

    /// Day number inside the 30-day Clean Phone Reset (clamped 1...30).
    /// Returns 1 until the user has actually started (no cleanup logged).
    var resetDay: Int {
        guard resetStartTimestamp > 0 else { return 1 }
        let start = Date(timeIntervalSince1970: resetStartTimestamp)
        let cal = Calendar.current
        let daysSince = cal.dateComponents([.day],
            from: cal.startOfDay(for: start),
            to: cal.startOfDay(for: Date())).day ?? 0
        return min(max(daysSince + 1, 1), 30)
    }

    /// Whether the user has completed the 30-day arc at least once.
    var resetCompleted: Bool { resetDay >= 30 && resetStartTimestamp > 0 }

    /// Per-day bucket history. Keys are "yyyy-MM-dd" strings, values are
    /// the bytes saved + items cleaned on that day. Decoded lazily; never
    /// stored back into a property — write through `setWeekHistory`.
    var weekHistory: [String: DailyBucket] {
        guard let data = weekHistoryRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: DailyBucket].self, from: data)
        else { return [:] }
        return dict
    }

    /// Convenience: last 7 calendar days (today-6 → today) in order.
    /// Days with no activity surface as `.zero` so the timeline always
    /// renders 7 slots even on a fresh install.
    var lastSevenDays: [DailyBucket] {
        let f = Self.dayKeyFormatter
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let store = weekHistory
        return (0..<7).reversed().map { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else {
                return .zero
            }
            let key = f.string(from: d)
            if let b = store[key] { return b }
            // If this is today and we haven't flushed to history yet,
            // surface the live daily bucket so the rightmost bar reflects
            // mid-day cleanup activity immediately.
            if key == dailyKey {
                return DailyBucket(dayKey: key, items: dailyItems, bytes: dailyBytes)
            }
            return DailyBucket(dayKey: key, items: 0, bytes: 0)
        }
    }

    var milestonesUnlocked: Set<String> {
        Set(milestonesUnlockedRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    // MARK: - Daily Commitment
    //
    // The "Today's Clean Commitment" pledge. Three independent rails —
    // the user clears the day by satisfying ANY one of them, so a
    // light-touch session (one quick cleanup) still rewards a streak.
    /// User-customizable via Settings → Daily Goal. Backed by
    /// `UserDefaults` so the user's pick survives a relaunch. The
    /// nil-coalesce + nonZero check guards against fresh installs and
    /// legacy users whose key was never written — both fall back to
    /// the original 10 items / 100 MB defaults so behavior is
    /// untouched until the user actively picks a new target.
    var dailyItemsGoal: Int {
        let stored = UserDefaults.standard.integer(forKey: "preferences.dailyItemsGoal")
        return stored > 0 ? stored : 10
    }
    var dailyBytesGoal: Int64 {
        // `@AppStorage` in SettingsView writes this as `Int` (NSNumber
        // under the hood) — the previous `as? Int64` cast on the raw
        // `.object(forKey:)` returned nil for every NSNumber, silently
        // falling back to the 100 MB default and ignoring whatever the
        // user picked in Settings. Reading as `Int` and widening to
        // `Int64` round-trips correctly because iOS `Int` is 64-bit.
        let stored = UserDefaults.standard.integer(forKey: "preferences.dailyBytesGoal")
        return stored > 0 ? Int64(stored) : 100_000_000   // 100 MB default
    }
    var dailyMetCommitment: Bool {
        let didActOnce = isSameCalendarDay(lastCleanDate, Date())
        return didActOnce
            && (dailyItems >= dailyItemsGoal
                || dailyBytes >= dailyBytesGoal)
    }
    var dailyDidAct: Bool { isSameCalendarDay(lastCleanDate, Date()) }

    private func isSameCalendarDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func todayKey() -> String { Self.dayKeyFormatter.string(from: Date()) }

    /// Pending items across all groups (photos + screenshots + videos).
    /// Returns cached value - call refreshPendingItemCount() to update.
    var pendingItemCount: Int {
        cachedPendingItemCount
    }

    /// Clean score 0-100 based on recency, activity, and thoroughness.
    /// Returns cached value - call refreshCleanScore() to update.
    var cleanScore: Int {
        cachedCleanScore
    }

    // MARK: - Async Cache Refresh

    /// Refresh pending item count from database asynchronously.
    func refreshPendingItemCount() async {
        let count = await Task.detached(priority: .userInitiated) {
            let summary = SimilarPersistence.loadScanSummary()
            let photoGroups = summary.similarGroupsCount + summary.duplicateGroupsCount
            let ssGroups = summary.screenshotGroupsCount
            let vidGroups = summary.videoGroupsCount
            return photoGroups + ssGroups + vidGroups
        }.value

        cachedPendingItemCount = count
        // Recalculate clean score since thoroughness depends on pending count
        await refreshCleanScore()
    }

    /// Refresh clean score calculation asynchronously.
    func refreshCleanScore() async {
        let score = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return 0 }
            let recency = await MainActor.run { self.recencyScore }
            let activity = await MainActor.run { self.activityScore }
            let thoroughness = await MainActor.run { self.thoroughnessScore }
            return min(recency + activity + thoroughness, 100)
        }.value

        cachedCleanScore = score
    }

    // MARK: - Score Components

    private var recencyScore: Int {
        guard let last = lastCleanDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? Int.max
        if days <= 0 { return 40 }
        if days <= 3 { return 30 }
        if days <= 7 { return 20 }
        if days <= 14 { return 10 }
        return 0
    }

    private var activityScore: Int {
        if currentStreak >= 7 { return 30 }
        if currentStreak >= 4 { return 20 }
        if currentStreak >= 2 { return 12 }
        if currentStreak >= 1 { return 6 }
        return 0
    }

    private var thoroughnessScore: Int {
        guard totalScansCompleted >= 1 else { return 0 }
        let pending = pendingItemCount
        if pending == 0 { return 30 }
        if pending <= 5 { return 20 }
        if pending <= 15 { return 10 }
        return 0
    }

    // MARK: - Actions

    /// Category-tagged variant of `recordCleanup`. Encodes the leaf
    /// category into the `action` string as `"deletion:duplicates"`,
    /// `"compression:longVideos"`, etc — the Progress chart parses
    /// it back via `ActivityEntry.category` so the timeline can be
    /// filtered by source without a backend schema migration. Falls
    /// through to the existing untagged path when category is nil so
    /// call sites that genuinely don't have a category (Email,
    /// Contacts, generic Scan) keep their current behavior.
    func recordCleanup(
        action: String,
        itemCount: Int,
        bytesSaved: Int64,
        category: SavedFindSourceCategory?
    ) {
        let taggedAction = category.map { "\(action):\($0.rawValue)" } ?? action
        recordCleanup(action: taggedAction, itemCount: itemCount, bytesSaved: bytesSaved)
    }

    /// Canonical cleanup entry point. Routes through the same lifetime
    /// stats + daily/weekly/best-record bookkeeping regardless of the
    /// source flow (photos, videos, screenshots, emails, contacts,
    /// compression). The `action` tag is what surfaces in the activity
    /// ledger on the Progress tab and on the backend `streak_activities`
    /// table — historically one of "deletion", "scan", "compression",
    /// "email_cleanup", "contact_cleanup", "plan_generated", and now
    /// optionally suffixed with `":<category>"` (e.g.
    /// `"deletion:duplicates"`) when the category-tagged overload
    /// above composes it.
    func recordCleanup(action: String, itemCount: Int, bytesSaved: Int64) {
        lifetimeItemsCleaned += itemCount
        lifetimeBytesSaved += bytesSaved
        lastCleanDateRaw = Date().timeIntervalSince1970

        if resetStartTimestamp == 0 {
            resetStartTimestamp = Date().timeIntervalSince1970
        }

        rollDailyBucketIfNeeded()
        dailyItems += itemCount
        dailyBytes += bytesSaved
        flushDailyToWeekHistory()

        updateBestRecords(itemCount: itemCount, bytesSaved: bytesSaved)
        updateStreak()
        unlockMilestonesIfNeeded()
        objectWillChange.send()

        // Push the runway forecast immediately so the Hive card shows the
        // "+N days" extension before iOS / PhotoKit actually frees the
        // bytes on disk (Recently Deleted holds for 30 days).
        if bytesSaved > 0 {
            StorageForecastManager.shared.recordCleanup(bytesSaved: bytesSaved)
        }
        // Forced snapshot so the next real free-byte reading lands in the
        // history right after the cleanup, not at the next 6h throttle tick.
        StorageForecastManager.shared.recordSnapshot(forced: true)

        Task {
            await refreshPendingItemCount()
            syncToBackend()
        }

        logActivity(action: action, itemCount: itemCount, bytesSaved: Int(bytesSaved))
    }

    /// Back-compat shim for photo/video deletion call sites that pre-date
    /// the action-tagged API. Equivalent to
    /// `recordCleanup(action: "deletion", …)`.
    func recordDeletion(itemCount: Int, bytesSaved: Int64) {
        recordCleanup(action: "deletion", itemCount: itemCount, bytesSaved: bytesSaved)
    }

    /// Public entry point so app lifecycle (scene → .active) can advance
    /// the live `dailyKey` at midnight without waiting for a cleanup
    /// to land. Previously the key could stay stale for 36+ hours,
    /// backdating a fresh cleanup into yesterday's bucket.
    func ensureDailyBucketFresh() {
        if rollDailyBucketIfNeeded() {
            objectWillChange.send()
        }
    }

    /// Roll the daily bucket if the calendar day has changed since the
    /// last cleanup. Writes the prior day into `weekHistory` first so the
    /// 7-day timeline always sees the closed-out totals. Returns `true`
    /// if the bucket actually rolled, so callers can decide whether to
    /// trigger an `objectWillChange.send()`.
    @discardableResult
    private func rollDailyBucketIfNeeded() -> Bool {
        let today = todayKey()
        guard dailyKey != today else { return false }
        // Persist the previous day before resetting the live bucket so
        // yesterday's bar shows up on tomorrow's timeline.
        if !dailyKey.isEmpty && (dailyItems > 0 || dailyBytes > 0) {
            writeDayToHistory(key: dailyKey, items: dailyItems, bytes: dailyBytes)
        }
        dailyKey = today
        dailyItems = 0
        dailyBytes = 0
        return true
    }

    /// Mirror the live daily bucket into the persisted week history so
    /// the timeline reflects activity even before midnight rollover.
    private func flushDailyToWeekHistory() {
        writeDayToHistory(key: dailyKey, items: dailyItems, bytes: dailyBytes)
    }

    private func writeDayToHistory(key: String, items: Int, bytes: Int64) {
        var store = weekHistory
        store[key] = DailyBucket(dayKey: key, items: items, bytes: bytes)
        // Keep only the most recent 8 keys so the value never grows.
        if store.count > 8 {
            let sorted = store.keys.sorted()
            for old in sorted.dropLast(8) { store.removeValue(forKey: old) }
        }
        if let data = try? JSONEncoder().encode(store),
           let str = String(data: data, encoding: .utf8) {
            weekHistoryRaw = str
        }
    }

    private func updateBestRecords(itemCount: Int, bytesSaved: Int64) {
        if itemCount > bestSessionItems { bestSessionItems = itemCount }
        if bytesSaved > bestSessionBytes { bestSessionBytes = bytesSaved }
        if dailyItems > bestDayItems { bestDayItems = dailyItems }
        if dailyBytes > bestDayBytes { bestDayBytes = dailyBytes }
    }

    private func unlockMilestonesIfNeeded() {
        var unlocked = milestonesUnlocked
        let before = unlocked.count
        for milestone in MilestoneCatalog.all {
            if !unlocked.contains(milestone.id) && milestone.isUnlocked(self) {
                unlocked.insert(milestone.id)
            }
        }
        if unlocked.count != before {
            milestonesUnlockedRaw = unlocked.sorted().joined(separator: ",")
        }
    }

    func recordScanCompleted() {
        totalScansCompleted += 1
        objectWillChange.send()

        // Refresh cached values asynchronously
        Task {
            await refreshCleanScore()
            syncToBackend()
        }

        logActivity(action: "scan", itemCount: 1)
    }

    /// Call on app launch to check if the streak is still active.
    func refreshStreak() {
        guard let last = lastCleanDate else {
            // First ever launch — start the streak
            currentStreak = 1
            bestStreak = 1
            lastCleanDateRaw = Date().timeIntervalSince1970
            objectWillChange.send()
            Task { await refreshCleanScore() }
            return
        }
        // `daysSince` clamped to 0 — if the device clock skewed
        // backwards (manual change, network sync) the raw value can be
        // negative and silently fall through every comparison below.
        let cal = Calendar.current
        let raw = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: Date())).day ?? Int.max
        let daysSince = max(0, raw)
        if daysSince == 1 {
            // Next day — extend streak
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            lastCleanDateRaw = Date().timeIntervalSince1970
            objectWillChange.send()
            Task { await refreshCleanScore() }
        } else if daysSince > 1 {
            // Missed a day — reset
            currentStreak = 1
            lastCleanDateRaw = Date().timeIntervalSince1970
            objectWillChange.send()
            Task { await refreshCleanScore() }
        }
        // daysSince == 0 (same day) — do nothing, streak already counted
    }

    // MARK: - Private

    private func updateStreak() {
        guard let last = lastCleanDate else {
            currentStreak = 1
            bestStreak = max(bestStreak, 1)
            return
        }

        let cal = Calendar.current
        let raw = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: Date())).day ?? Int.max
        let daysSince = max(0, raw)

        if daysSince <= 1 {
            // Same day or next day — extend streak
            if daysSince == 1 {
                currentStreak += 1
            } else if currentStreak == 0 {
                currentStreak = 1
            }
        } else {
            // Gap > 1 day — reset
            currentStreak = 1
        }

        bestStreak = max(bestStreak, currentStreak)
    }

    // MARK: - Backend Sync

    /// Sync local streak state to the backend. Fire-and-forget — never blocks UI.
    func syncToBackend() {
        guard AuthService.shared.isAuthenticated else { return }

        let dateStr: String? = lastCleanDate.map {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: $0)
        }

        let request = StreakSyncRequest(
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastActivityDate: dateStr,
            lifetimeItemsCleaned: lifetimeItemsCleaned,
            lifetimeBytesSaved: Int(lifetimeBytesSaved),
            totalScansCompleted: totalScansCompleted,
            cleanScore: cleanScore
        )

        Task {
            if let remote = await StreakService.shared.syncStreak(request) {
                // Server wins for best streak (may be higher from another device)
                if remote.bestStreak > bestStreak {
                    bestStreak = remote.bestStreak
                }
            }
        }
    }

    /// Pull streak from backend and merge (server wins for best streak).
    func pullFromBackend() async {
        guard AuthService.shared.isAuthenticated else { return }
        guard let remote = await StreakService.shared.fetchStreak() else { return }

        if remote.bestStreak > bestStreak {
            bestStreak = remote.bestStreak
            objectWillChange.send()
        }

        // If local has no data but server does, restore from server
        if currentStreak == 0 && remote.currentStreak > 0 {
            currentStreak = remote.currentStreak
            lifetimeItemsCleaned = remote.lifetimeItemsCleaned
            lifetimeBytesSaved = Int64(remote.lifetimeBytesSaved)
            totalScansCompleted = remote.totalScansCompleted
            if let dateStr = remote.lastActivityDate {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let date = f.date(from: dateStr) {
                    lastCleanDateRaw = date.timeIntervalSince1970
                }
            }
            objectWillChange.send()
        }
    }

    /// Log an activity to the backend for analytics.
    func logActivity(action: String, itemCount: Int, bytesSaved: Int = 0) {
        Task {
            await StreakService.shared.recordActivity(action: action, itemCount: itemCount, bytesSaved: bytesSaved)
        }
    }

    // MARK: - Formatting Helpers

    var formattedBytesSaved: String {
        let bytes = lifetimeBytesSaved
        if bytes < 1_000_000 {
            return "\(bytes / 1_000)KB"
        } else if bytes < 1_000_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1fMB", mb)
        } else {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.1fGB", gb)
        }
    }

    var streakMessage: String {
        if currentStreak >= 30 { return "Legendary" }
        if currentStreak >= 14 { return "On Fire" }
        if currentStreak >= 7  { return "Crushing It" }
        if currentStreak >= 3  { return "Building Momentum" }
        if currentStreak >= 1  { return "Getting Started" }
        return "Start Cleaning"
    }
}

// MARK: - Daily Bucket
//
// Per-day cleanup totals used by the weekly timeline + best-day record.
// Codable so the dictionary can survive a single JSON @AppStorage value.
struct DailyBucket: Codable, Equatable {
    let dayKey: String
    let items: Int
    let bytes: Int64

    static let zero = DailyBucket(dayKey: "", items: 0, bytes: 0)
}

// MARK: - Milestone Catalog
//
// Static catalog of the achievements shown on the Progress tab's
// Milestone Roadmap. Each entry knows how to (a) check whether it's
// unlocked from the live HiveStats snapshot and (b) report progress as a
// 0…1 fraction so the locked card can show a "X / target" rail. The
// catalog is the single source of truth — the Roadmap UI iterates `all`
// in order, so adding a milestone is a one-line change.
@MainActor
struct Milestone: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let isUnlocked: (HiveStatsManager) -> Bool
    let progress: (HiveStatsManager) -> Double
    let target: String
}

@MainActor
enum MilestoneCatalog {
    static var all: [Milestone] {
        [
            Milestone(
                id: "first_clean",
                title: "First Cleanup",
                subtitle: "Open the journey.",
                symbol: "sparkles",
                isUnlocked: { $0.lifetimeItemsCleaned >= 1 },
                progress: { min(Double($0.lifetimeItemsCleaned) / 1.0, 1.0) },
                target: "1 item"
            ),
            Milestone(
                id: "pocket_saver",
                title: "Pocket Saver",
                subtitle: "Free your first 500 MB.",
                symbol: "tray.full.fill",
                isUnlocked: { $0.lifetimeBytesSaved >= 500_000_000 },
                progress: { min(Double($0.lifetimeBytesSaved) / 500_000_000.0, 1.0) },
                target: "500 MB"
            ),
            Milestone(
                id: "gigabyte",
                title: "Gigabyte Crusher",
                subtitle: "Free 1 GB total.",
                symbol: "externaldrive.fill",
                isUnlocked: { $0.lifetimeBytesSaved >= 1_000_000_000 },
                progress: { min(Double($0.lifetimeBytesSaved) / 1_000_000_000.0, 1.0) },
                target: "1 GB"
            ),
            Milestone(
                id: "power_cleaner",
                title: "Power Cleaner",
                subtitle: "Free 5 GB total.",
                symbol: "bolt.fill",
                isUnlocked: { $0.lifetimeBytesSaved >= 5_000_000_000 },
                progress: { min(Double($0.lifetimeBytesSaved) / 5_000_000_000.0, 1.0) },
                target: "5 GB"
            ),
            Milestone(
                id: "streak_3",
                title: "3-Day Streak",
                subtitle: "Three days in a row.",
                symbol: "flame.fill",
                isUnlocked: { $0.bestStreak >= 3 },
                progress: { min(Double($0.bestStreak) / 3.0, 1.0) },
                target: "3 days"
            ),
            Milestone(
                id: "week_warrior",
                title: "Week Warrior",
                subtitle: "Seven-day streak.",
                symbol: "flame.fill",
                isUnlocked: { $0.bestStreak >= 7 },
                progress: { min(Double($0.bestStreak) / 7.0, 1.0) },
                target: "7 days"
            ),
            Milestone(
                id: "fortnight",
                title: "Fortnight Beacon",
                subtitle: "Two clean weeks.",
                symbol: "flame.fill",
                isUnlocked: { $0.bestStreak >= 14 },
                progress: { min(Double($0.bestStreak) / 14.0, 1.0) },
                target: "14 days"
            ),
            Milestone(
                id: "reset_complete",
                title: "30-Day Reset",
                subtitle: "Complete the journey.",
                symbol: "trophy.fill",
                isUnlocked: { $0.bestStreak >= 30 },
                progress: { min(Double($0.bestStreak) / 30.0, 1.0) },
                target: "30 days"
            ),
            Milestone(
                id: "bee_stage_2",
                title: "Stage 2 Bee",
                subtitle: "Wake the hive up.",
                symbol: "hexagon.fill",
                isUnlocked: { _ in BeeViewModel.shared.stage.rawValue >= BeeStage.stage2.rawValue },
                progress: { _ in
                    let s = BeeViewModel.shared.stage.rawValue + 1
                    return min(Double(s) / 2.0, 1.0)
                },
                target: "Stage 2"
            ),
            Milestone(
                id: "bee_stage_3",
                title: "Stage 3 Bee",
                subtitle: "Halfway healthy.",
                symbol: "hexagon.fill",
                isUnlocked: { _ in BeeViewModel.shared.stage.rawValue >= BeeStage.stage3.rawValue },
                progress: { _ in
                    let s = BeeViewModel.shared.stage.rawValue + 1
                    return min(Double(s) / 3.0, 1.0)
                },
                target: "Stage 3"
            ),
            Milestone(
                id: "bee_stage_5",
                title: "Master Bee",
                subtitle: "Spotless hive.",
                symbol: "crown.fill",
                isUnlocked: { _ in BeeViewModel.shared.stage.rawValue >= BeeStage.stage5.rawValue },
                progress: { _ in
                    let s = BeeViewModel.shared.stage.rawValue + 1
                    return min(Double(s) / 5.0, 1.0)
                },
                target: "Stage 5"
            ),
            Milestone(
                id: "session_record",
                title: "Big Sweep",
                subtitle: "Clear 50 items in one go.",
                symbol: "wind",
                isUnlocked: { $0.bestSessionItems >= 50 },
                progress: { min(Double($0.bestSessionItems) / 50.0, 1.0) },
                target: "50 items"
            )
        ]
    }
}
