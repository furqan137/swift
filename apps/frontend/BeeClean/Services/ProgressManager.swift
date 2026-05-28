import SwiftUI
import Photos

// MARK: - Progress Math (mirror of coin-progression.service.ts)
//
// Single source of truth for the client-side optimistic coin calc. Keep these
// constants in sync with the backend (REVIEW_WEIGHT / SELECTION_WEIGHT etc.).
//
// Coins are awarded for REVIEW alone — deleting a photo must never change the
// payout, so the estimate (badge) and the award are identical by construction.
// selectionWeight / storageWeight are zeroed (kept as constants to mirror the
// backend contract). If levels feel too fast, drop reviewWeight→0.15.

enum ProgressMath {
    static let reviewWeight = 0.25
    static let selectionWeight = 0.0
    static let storageWeight = 0.0
    static let storageMBUnit = 250.0
    static let coinMin = 1
    static let coinMax = 12

    /// Level-requirement curve. Gentle single exponent so early levels are a
    /// meaningful fraction of the pool (not floored to 1) while still summing
    /// to maxLifetimeCoins across 1000 levels. Mirrors the backend.
    static let levelCurveExponent = 0.48
    static let maxLevels = 1000
    static let coinsPerAsset = 10

    struct LevelRequirement {
        let level: Int
        let coinsRequired: Int
        let cumulativeCoinsRequired: Int
    }

    struct DerivedProgress {
        let currentLevel: Int
        let maxLevel: Int
        let currentLevelCoins: Int
        let coinsNeededForNextLevel: Int
        let cleanBarPercent: Double
    }

    /// Segmented-curve level requirements. Invariant: Σ coinsRequired == max.
    /// Fallback: when max < 1000, there are only `max` levels (each ≥ 1 coin).
    static func generateLevelRequirements(_ maxLifetimeCoins: Int) -> [LevelRequirement] {
        let maxC = max(0, maxLifetimeCoins)
        let levels = min(maxLevels, maxC)
        guard levels > 0 else { return [] }

        var weights = [Double]()
        weights.reserveCapacity(levels)
        for level in 1...levels { weights.append(pow(Double(level), levelCurveExponent)) }
        let totalWeight = weights.reduce(0, +)

        var req = weights.map { Swift.max(1, Int((Double(maxC) * $0 / totalWeight).rounded())) }

        var diff = maxC - req.reduce(0, +)
        var i = req.count - 1
        while diff != 0 && i >= 0 {
            let next = req[i] + diff
            if next >= 1 { req[i] = next; diff = 0 }
            else { diff = next - 1; req[i] = 1; i -= 1 }
        }

        var cumulative = 0
        var result = [LevelRequirement]()
        result.reserveCapacity(req.count)
        for (idx, c) in req.enumerated() {
            cumulative += c
            result.append(LevelRequirement(level: idx + 1, coinsRequired: c, cumulativeCoinsRequired: cumulative))
        }
        return result
    }

    /// Derive level / bar / next-level target from earned coins + the ladder.
    static func deriveProgress(total: Int, max maxCoins: Int, reqs: [LevelRequirement]) -> DerivedProgress {
        guard !reqs.isEmpty else {
            return DerivedProgress(currentLevel: 1, maxLevel: 1, currentLevelCoins: 0, coinsNeededForNextLevel: 1, cleanBarPercent: 0)
        }
        let maxLevel = reqs.count
        let t = min(total, maxCoins)
        let lastCumulative = reqs[maxLevel - 1].cumulativeCoinsRequired
        if t >= lastCumulative {
            let need = reqs[maxLevel - 1].coinsRequired
            return DerivedProgress(currentLevel: maxLevel, maxLevel: maxLevel, currentLevelCoins: need, coinsNeededForNextLevel: need, cleanBarPercent: 1)
        }
        var level = 1
        for r in reqs where t < r.cumulativeCoinsRequired { level = r.level; break }
        let cumBefore = level > 1 ? reqs[level - 2].cumulativeCoinsRequired : 0
        let need = reqs[level - 1].coinsRequired
        let cur = t - cumBefore
        let pct = need > 0 ? Double(cur) / Double(need) : 0
        return DerivedProgress(currentLevel: level, maxLevel: maxLevel, currentLevelCoins: cur, coinsNeededForNextLevel: need, cleanBarPercent: pct)
    }

    static let categoryMultipliers: [String: Double] = [
        "duplicates": 1.15,
        "large_videos": 1.20,
        "screenshots": 1.00,
        "blurry": 0.90,
        "similar": 1.05,
        "screen_recordings": 1.15,
        "other": 1.00,
    ]

    /// Reviewed-count-weighted category multiplier. Deliberately NOT byte-
    /// weighted: the multiplier must not depend on what gets deleted, or the
    /// badge estimate and the actual award could diverge.
    static func categoryMultiplier(_ breakdown: [String: CategoryStat]) -> Double {
        guard !breakdown.isEmpty else { return 1.0 }
        var weightSum = 0.0
        var acc = 0.0
        for (key, v) in breakdown {
            let w = Double(v.reviewed)
            if w <= 0 { continue }
            acc += (categoryMultipliers[key] ?? 1.0) * w
            weightSum += w
        }
        return weightSum > 0 ? acc / weightSum : 1.0
    }

    /// Coin estimate for a guided task — review-only, so it equals exactly what
    /// completing the task awards regardless of how many items get deleted. Each
    /// task in `tasks` is one checkpoint (carries `itemRefs`); sums the
    /// per-checkpoint formula.
    static func estimatedTaskCoins(for tasks: [CleanupTask]) -> Int {
        tasks.reduce(0) { sum, task in
            let refs = task.itemRefs
            guard !refs.isEmpty else { return sum }
            var breakdown: [String: (bytes: Int64, reviewed: Int)] = [:]
            for ref in refs {
                let key = ref.category.coinCategoryKey
                var entry = breakdown[key] ?? (0, 0)
                entry.reviewed += 1
                breakdown[key] = entry
            }
            let cb = breakdown.mapValues { CategoryStat(bytes: $0.bytes, reviewed: $0.reviewed) }
            return sum + checkpointCoins(reviewed: refs.count, selected: 0, deletedBytes: 0, breakdown: cb)
        }
    }

    /// Review-only coin award for one checkpoint. `selected` / `deletedBytes`
    /// are accepted for call-site / telemetry compatibility but do not affect
    /// the payout (selectionWeight / storageWeight are 0).
    static func checkpointCoins(reviewed: Int, selected: Int, deletedBytes: Int64, breakdown: [String: CategoryStat]) -> Int {
        let raw = Double(reviewed) * reviewWeight * categoryMultiplier(breakdown)
        return max(coinMin, min(Int(raw.rounded()), coinMax))
    }
}

// MARK: - Level Up event

struct LevelUpInfo: Equatable {
    let from: Int
    let to: Int
}

// MARK: - Progress Manager
//
// Single source of truth for coin progression + bee stage on the client.
// Backed by the server (`ProgressService`); mutated optimistically on
// checkpoint award, then reconciled with the authoritative POST response.

@MainActor
final class ProgressManager: ObservableObject {
    static let shared = ProgressManager()

    @Published private(set) var totalLifetimeCoins: Int = 0
    @Published private(set) var maxLifetimeCoins: Int = 0
    @Published private(set) var currentLevel: Int = 1
    @Published private(set) var maxLevel: Int = 1
    @Published private(set) var currentLevelCoins: Int = 0
    @Published private(set) var coinsNeededForNextLevel: Int = 1
    @Published private(set) var cleanBarPercent: Double = 0
    @Published private(set) var beeStage: BeeStage = .stage1

    /// Set when a reconcile lands a level increase — views can show the moment.
    @Published var lastLevelUp: LevelUpInfo?

    private let service = ProgressService.shared

    /// Level ladder, generated locally from `maxLifetimeCoins`. The client is
    /// authoritative for DISPLAY (level / bar / stage) so the Clean Bar never
    /// depends on a backend round-trip landing. The server stays authoritative
    /// for the earned-coin COUNT (idempotent ledger + pool cap).
    private var levelRequirements: [ProgressMath.LevelRequirement] = []

    private static let totalKey = "progress.totalLifetimeCoins.v1"
    private static let maxKey = "progress.maxLifetimeCoins.v1"

    private init() {
        let savedMax = UserDefaults.standard.integer(forKey: Self.maxKey)
        let savedTotal = UserDefaults.standard.integer(forKey: Self.totalKey)
        if savedMax > 0 {
            configurePool(max: savedMax)
            setTotalCoins(savedTotal, animate: false)
        }
    }

    /// Load progress: derive the pool live from the device library (dynamic,
    /// backend-independent), then fold in the server's authoritative earned
    /// count when reachable, and best-effort sync the server row.
    func loadProgress() async {
        await service.flushPendingCoinAwards()
        refreshPoolFromLibrary()

        if let state = await service.fetchProgress(), state.totalLifetimeCoins > 0 || maxLifetimeCoins == 0 {
            // Prefer the server's earned count; if the server also has a real
            // pool and we don't, adopt it as a fallback.
            if maxLifetimeCoins == 0 && state.maxLifetimeCoins > 0 {
                configurePool(max: state.maxLifetimeCoins)
            }
            // Lifetime coins are monotonic — never let a behind/in-flight
            // backend value (or a transient dip) shrink the displayed total.
            setTotalCoins(Swift.max(state.totalLifetimeCoins, totalLifetimeCoins), animate: true)
        } else {
            setTotalCoins(totalLifetimeCoins, animate: true)
        }

        // Best-effort: keep the server row aligned with the live library.
        if maxLifetimeCoins > 0 {
            let photos = PhotoKitService.shared.fetchAllPhotos().count
            let videos = PhotoKitService.shared.fetchAllVideos().count
            if photos + videos > 0 {
                Task { _ = await service.syncLibrary(totalPhotos: photos, totalVideos: videos) }
            }
        }
    }

    /// Build the coin pool + ladder from the device's real photo+video counts.
    /// `maxLifetimeCoins = (photos + videos) * 10`. Skips when photo access
    /// isn't granted or the library is empty (keeps any persisted pool).
    func refreshPoolFromLibrary() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        let photos = PhotoKitService.shared.fetchAllPhotos().count
        let videos = PhotoKitService.shared.fetchAllVideos().count
        let max = (photos + videos) * ProgressMath.coinsPerAsset
        guard max > 0 else { return }
        configurePool(max: max)
    }

    /// Public hook for the scan pipeline — recompute the pool from fresh counts.
    func syncLibrary(totalPhotos: Int, totalVideos: Int) async {
        let max = (totalPhotos + totalVideos) * ProgressMath.coinsPerAsset
        // A 0-count sync is garbage (permission/timing) and would clamp the
        // server total to 0 — never send it.
        guard max > 0 else { return }
        configurePool(max: max)
        setTotalCoins(totalLifetimeCoins, animate: true)
        Task { _ = await service.syncLibrary(totalPhotos: totalPhotos, totalVideos: totalVideos) }
    }

    private func configurePool(max: Int) {
        guard max != maxLifetimeCoins || levelRequirements.isEmpty else { return }
        maxLifetimeCoins = max
        levelRequirements = ProgressMath.generateLevelRequirements(max)
        UserDefaults.standard.set(max, forKey: Self.maxKey)
    }

    /// Set the earned-coin count and derive level / bar / stage locally.
    private func setTotalCoins(_ total: Int, animate: Bool) {
        let previousLevel = currentLevel
        let clamped = maxLifetimeCoins > 0 ? min(total, maxLifetimeCoins) : total
        totalLifetimeCoins = clamped
        UserDefaults.standard.set(clamped, forKey: Self.totalKey)

        let d = ProgressMath.deriveProgress(total: clamped, max: maxLifetimeCoins, reqs: levelRequirements)
        currentLevel = d.currentLevel
        maxLevel = d.maxLevel
        currentLevelCoins = d.currentLevelCoins
        coinsNeededForNextLevel = d.coinsNeededForNextLevel
        cleanBarPercent = d.cleanBarPercent
        beeStage = .forCleanBarPercent(d.cleanBarPercent)

        guard animate else {
            BeeViewModel.shared.syncStage(beeStage)
            return
        }
        if d.currentLevel > previousLevel {
            lastLevelUp = LevelUpInfo(from: previousLevel, to: d.currentLevel)
            BeeViewModel.shared.playLevelUp(resettingTo: beeStage)
        } else {
            BeeViewModel.shared.applyBeeStage(beeStage)
        }
    }

    /// Award a checkpoint's coins the instant the user confirms its cleanup.
    /// Updates the bar + bee immediately (local), then folds in the server's
    /// authoritative count when the POST returns.
    func awardCheckpointCoins(
        eventId: String,
        planId: String,
        taskId: String,
        checkpointId: String,
        reviewedItemCount: Int,
        selectedItemCount: Int,
        deletedBytes: Int64,
        categoryBreakdown: [String: CategoryStat]
    ) {
        let coins = ProgressMath.checkpointCoins(
            reviewed: reviewedItemCount,
            selected: selectedItemCount,
            deletedBytes: deletedBytes,
            breakdown: categoryBreakdown
        )
        if coins > 0 { setTotalCoins(totalLifetimeCoins + coins, animate: true) }

        Task {
            let request = CheckpointCoinRequest(
                eventId: eventId,
                planId: planId,
                taskId: taskId,
                checkpointId: checkpointId,
                reviewedItemCount: reviewedItemCount,
                selectedItemCount: selectedItemCount,
                deletedBytes: deletedBytes,
                categoryBreakdown: categoryBreakdown,
                // Post-award authoritative snapshot (setTotalCoins already ran).
                maxLifetimeCoins: maxLifetimeCoins,
                totalLifetimeCoins: totalLifetimeCoins,
                currentLevel: currentLevel,
                maxLevel: maxLevel,
                currentLevelCoins: currentLevelCoins,
                coinsNeededForNextLevel: coinsNeededForNextLevel,
                cleanBarPercent: cleanBarPercent,
                beeStage: beeStage.rawValue
            )
            if let state = await service.recordCheckpoint(request), state.totalLifetimeCoins >= totalLifetimeCoins {
                setTotalCoins(state.totalLifetimeCoins, animate: true)
            }
        }
    }
}
