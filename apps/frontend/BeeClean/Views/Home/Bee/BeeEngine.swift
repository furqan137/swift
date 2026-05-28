import Foundation

enum BeeCleanupSource: String, Codable {
    case photoDelete
    case videoDelete
    case emailCleanup
    case compression
    case aiCleanup
    case generic
}

enum BeeEngine {
    static let dripThreshold = 5
    static let maxProgress = 100
    static let honeycombThresholds: [Int] = [15, 30, 50, 80, 100]

    // MARK: - Stage Thresholds (Strict)
    //
    // Designed so the average user lands at stage 1-2 on their first scan.
    // A phone with ~1% clutter (common for 30K+ photo libraries) = stage 1.
    // Users must genuinely clean to see improvement. Duolingo guilt model.

    // Percentage thresholds (cleanRatio values)
    // Stage 1: cleanRatio < 0.97  → >=3% clutter
    // Stage 2: cleanRatio < 0.99  → 1-3% clutter
    // Stage 3: cleanRatio < 0.996 → 0.4-1% clutter
    // Stage 4: cleanRatio < 0.999 → 0.1-0.4% clutter
    // Stage 5: cleanRatio >= 0.999 → <0.1% clutter (extremely clean)

    // Absolute byte floors — even on a 1TB phone with tiny percentages,
    // the bee stays sad if there's real cleanable volume.
    private static let absoluteFloors: [(maxStage: BeeStage, bytes: Int64)] = [
        (.stage1, 5 * 1024 * 1024 * 1024),    // >5 GB → locked at stage 1
        (.stage2, 2 * 1024 * 1024 * 1024),    // >2 GB → max stage 2
        (.stage3, 800 * 1024 * 1024),          // >800 MB → max stage 3
        (.stage4, 200 * 1024 * 1024),          // >200 MB → max stage 4
        // Stage 5 requires <200 MB clutter AND <0.1% ratio
    ]

    // MARK: - Decay (inactivity-driven regression)
    //
    // Tuning goals: fair, recoverable, clearly gamified.
    //
    //   • Grace period — first 3 days after the last cleanup incur no
    //     regression. Matches the "streak freeze" expectation users have
    //     from apps like Duolingo — a short trip shouldn't punish them.
    //
    //   • Interval — past grace, one stage is shed every 3 days. Gentle
    //     enough that a two-week lapse still leaves the bee above stage 1.
    //
    //   • Per-session floor — even if decay math says we should drop 5
    //     stages (coming back after a month), we never drop more than
    //     `maxStageDropPerSession` in a single app run. The user sees the
    //     regression, reacts, and can keep chipping away on subsequent
    //     launches until reality catches up.
    //
    // Decay never applies to regressions caused by a scan finding real
    // new clutter — those are truth-based and stay immediate & uncapped.

    /// Days of inactivity that incur zero regression.
    static let decayGraceDays = 3

    /// After the grace period, one stage is shed every N days.
    static let decayIntervalDays = 3

    /// Max stages a user can lose to inactivity decay within a single
    /// app session. Decay beyond this is deferred until the next launch.
    static let maxStageDropPerSession = 2

    // MARK: - Momentum (upgrade cap)
    //
    // Max stages the bee can improve in a single app session.
    // Matched to `maxStageDropPerSession` so the game feels symmetric —
    // one strong cleaning spree is rewarded with a visible 2-stage jump,
    // but users still need multiple sessions to reach stage 5 so the
    // progression feels earned.
    static let maxStageJumpPerSession = 2

    /// Legacy alias for callers still referencing the old name. The new
    /// code uses `decayGraceDays` / `decayIntervalDays` directly.
    static let decayDays = decayIntervalDays

    /// Converts days-since-last-cleanup into how many stages should decay.
    ///
    /// - 0–2 days → 0 (grace)
    /// - 3–5 days → 1
    /// - 6–8 days → 2
    /// - 9–11 days → 3
    /// - 12+ → keeps climbing, but final drop is clamped by
    ///   `maxStageDropPerSession` in `resolvedStage`.
    static func decayStepCount(daysSinceCleanup days: Int) -> Int {
        guard days >= decayGraceDays else { return 0 }
        return (days - decayGraceDays) / decayIntervalDays + 1
    }

    // MARK: - Honeycomb Helpers

    static func clamp(_ value: Int) -> Int {
        min(max(value, 0), maxProgress)
    }

    static func filledCells(for total: Int) -> Int {
        honeycombThresholds.filter { total >= $0 }.count
    }

    static func nextThreshold(after total: Int) -> Int? {
        honeycombThresholds.first(where: { total < $0 })
    }

    static func cellIndexFilled(onCrossing total: Int) -> Int? {
        honeycombThresholds.firstIndex(of: total).map { $0 + 1 }
    }

    static func didActivateDrip(old: Int, new: Int) -> Bool {
        old < dripThreshold && new >= dripThreshold
    }

    static func crossedThresholds(old: Int, new: Int) -> [Int] {
        guard new > old else { return [] }
        return honeycombThresholds.filter { old < $0 && new >= $0 }
    }

    /// Stage from daily action count (honeycomb only)
    static func stage(for total: Int) -> BeeStage {
        BeeStage.stage(forTotalActions: total)
    }

    // MARK: - Raw Stage Calculation

    /// Calculates the "raw" stage from clutter data — before momentum/decay caps.
    /// This represents where the user SHOULD be based on their phone's current state.
    static func rawStage(
        forCleanRatio ratio: Double,
        clutterBytes: Int64,
        hasScanned: Bool
    ) -> BeeStage {
        // No scan yet → stage 1. Never pretend the phone is clean.
        guard hasScanned else { return .stage1 }

        // Percentage-based stage (strict thresholds)
        let pctStage: BeeStage
        switch ratio {
        case ..<0.97:  pctStage = .stage1   // >=3% clutter
        case ..<0.99:  pctStage = .stage2   // 1-3% clutter
        case ..<0.996: pctStage = .stage3   // 0.4-1% clutter
        case ..<0.999: pctStage = .stage4   // 0.1-0.4% clutter
        default:       pctStage = .stage5   // <0.1% clutter
        }

        // Absolute floor — cap stage based on byte volume
        var capped = pctStage
        for floor in absoluteFloors {
            if clutterBytes > floor.bytes && capped.rawValue > floor.maxStage.rawValue {
                capped = floor.maxStage
                break // floors are ordered strictest first
            }
        }

        return capped
    }

    /// Full stage calculation with momentum and decay.
    ///
    /// - Parameters:
    ///   - ratio: clean ratio (0 = filthy, 1 = pristine)
    ///   - clutterBytes: total clutter bytes
    ///   - hasScanned: whether any scan has completed
    ///   - currentStage: the bee's current displayed stage
    ///   - sessionBaseStage: the stage when this app session started (for momentum cap)
    ///   - lastCleanupDate: when the user last cleaned something (for decay)
    static func resolvedStage(
        forCleanRatio ratio: Double,
        clutterBytes: Int64,
        hasScanned: Bool,
        currentStage: BeeStage,
        sessionBaseStage: BeeStage,
        lastCleanupDate: Date?
    ) -> BeeStage {
        let raw = rawStage(forCleanRatio: ratio, clutterBytes: clutterBytes, hasScanned: hasScanned)

        // 1. Never-cleaned rule — must earn the first upgrade. Without a
        //    cleanup history, clamp at stage 1 regardless of what the
        //    current clutter ratio says.
        guard let lastCleanup = lastCleanupDate else {
            if hasScanned { return min(raw, .stage1) }
            return currentStage
        }

        // 2. Truth-based downgrade — a scan found more clutter than the
        //    current stage allows (byte floor or ratio drop). This is
        //    reality, not decay, so it bypasses the session cap and
        //    takes effect immediately. Red signal the user needs to see.
        if raw.rawValue < currentStage.rawValue {
            return raw
        }

        // 3. Inactivity decay — only runs when the phone is clean enough
        //    to hold the current stage (raw >= current). This is the
        //    "you haven't cleaned in a while" pull-down.
        let daysSince = Calendar.current
            .dateComponents([.day], from: lastCleanup, to: Date()).day ?? 0
        let steps = decayStepCount(daysSinceCleanup: daysSince)
        if steps > 0 {
            // Decay the CURRENT stage, not the raw. Decaying raw would
            // mean "every 3 days without cleaning, drop from wherever
            // you theoretically could be" — that can nuke a user who
            // came back after a short break. Decaying from current
            // stage means the user only slides down from where they
            // actually are.
            let decayedValue = max(currentStage.rawValue - steps, BeeStage.stage1.rawValue)

            // Per-session floor — don't let decay pull more than
            // `maxStageDropPerSession` below where this session began.
            // A user coming back after a month loses two stages now,
            // then more on subsequent launches until it catches up.
            let sessionFloor = max(
                sessionBaseStage.rawValue - maxStageDropPerSession,
                BeeStage.stage1.rawValue
            )
            let cappedDecay = max(decayedValue, sessionFloor)

            if cappedDecay < currentStage.rawValue {
                return BeeStage(rawValue: cappedDecay) ?? .stage1
            }
        }

        // 4. Upgrade — capped by momentum. Mirrors the decay cap so
        //    evolution and devolution feel symmetric and fair.
        if raw.rawValue > currentStage.rawValue {
            let maxAllowed = sessionBaseStage.rawValue + maxStageJumpPerSession
            let cappedRaw = min(raw.rawValue, maxAllowed)
            return BeeStage(rawValue: cappedRaw) ?? raw
        }

        // 5. No change
        return currentStage
    }

    /// Clean ratio for progress bar (0-1 scale)
    static func cleanRatio(clutterBytes: Int64, usedBytes: Int64) -> Double {
        guard usedBytes > 0 else { return 1.0 }
        let fraction = min(max(Double(clutterBytes) / Double(usedBytes), 0), 1)
        return 1.0 - fraction
    }

    static func rewardPulse(forThreshold threshold: Int) -> RewardPulseType {
        if threshold >= maxProgress { return .hiveComplete }
        if let index = cellIndexFilled(onCrossing: threshold) {
            return .cellFilled(index)
        }
        return .none
    }

    static func progressWithinCurrentCell(total: Int) -> Double {
        let clamped = clamp(total)
        let previous = [0] + honeycombThresholds.dropLast()
        let cellIndex = filledCells(for: clamped)
        guard cellIndex < honeycombThresholds.count, cellIndex < previous.count else { return 1.0 }
        let lower = previous[cellIndex]
        let upper = honeycombThresholds[cellIndex]
        guard upper > lower else { return 1.0 }
        return Double(clamped - lower) / Double(upper - lower)
    }
}

// MARK: - BeeStage Comparable
extension BeeStage: Comparable {
    static func < (lhs: BeeStage, rhs: BeeStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
