import Foundation

// MARK: - StorageForecastEstimator Tests
//
// DEBUG-only self-tests for the pure StorageForecastEstimator. Mirrors
// the `CLIPEmbeddingStoreTests` pattern already used in the project — no
// XCTest target needed. Run via `StorageForecastEstimatorTests.runAll()`
// from `BeeCleanApp.init` (DEBUG build only) or invoke a specific
// scenario from the LLDB prompt.
//
// Synthetic snapshot arrays exercise:
//   1. Steady fill                → .days(_, low)
//   2. Steady fill long span      → .days(_, high)
//   3. Fill with cleaning spike   → ignores the spike, returns .days
//   4. Net-freeing                → .stable
//   5. Sparse / short history     → .calibrating
//   6. Cold start (empty)         → .calibrating
//   7. Out-of-order timestamps    → still produces a forecast
//   8. Day-count cap              → clamps at maxDisplayDays
enum StorageForecastEstimatorTests {

    // MARK: - Entry point

    /// Run every scenario. Asserts via `precondition` so a regression
    /// trips the debugger immediately during development.
    static func runAll() {
        #if DEBUG
        steadyFill_lowConfidence()
        steadyFill_highConfidence()
        fillWithCleaningSpike()
        netFreeing_isStable()
        sparseHistory_isCalibrating()
        emptyHistory_isCalibrating()
        outOfOrderTimestamps_stillForecast()
        runwayClampedToMaxDisplayDays()
        print("✅ StorageForecastEstimatorTests — all scenarios passed")
        #endif
    }

    // MARK: - Scenarios

    /// 4 snapshots, ~2 days, losing 200 MB/day → ~25 days for 5 GB free.
    /// Span < highConfidenceSpanDays → confidence is `.low`.
    static func steadyFill_lowConfidence() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let snapshots = buildSnapshots(
            startFreeBytes: 5_000 * mb,
            ratePerDay: -200 * mb,
            spacingHours: 12,
            count: 5,
            anchor: now
        )
        let result = StorageForecastEstimator.estimate(
            snapshots: snapshots,
            currentFree: 5_000 * mb
        )
        guard case let .days(n, conf) = result.forecast else {
            preconditionFailure("expected .days, got \(result.forecast)")
        }
        precondition(conf == .low, "expected low confidence on 2-day span, got \(conf)")
        precondition((20...30).contains(n), "expected ~25 days, got \(n)")
        precondition(result.fillRatePerDay > 0, "expected positive fill rate")
        #endif
    }

    /// 8 days of history → confidence flips to `.high`.
    static func steadyFill_highConfidence() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let snapshots = buildSnapshots(
            startFreeBytes: 10_000 * mb,
            ratePerDay: -100 * mb,
            spacingHours: 24,
            count: 9,
            anchor: now
        )
        let result = StorageForecastEstimator.estimate(
            snapshots: snapshots,
            currentFree: 10_000 * mb
        )
        guard case let .days(_, conf) = result.forecast else {
            preconditionFailure("expected .days for 8-day steady fill")
        }
        precondition(conf == .high, "expected high confidence on 8-day span")
        #endif
    }

    /// Steady consumption with one huge cleanup partway through — the
    /// estimator must DROP the cleaning interval and still return a
    /// plausible projection.
    static func fillWithCleaningSpike() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let day: TimeInterval = 86_400
        // Real consumption pattern around the spike:
        //   t-4d: 10 GB free
        //   t-3d:  9.8 GB (consumed 200 MB)
        //   t-2d:  9.6 GB
        //   t-1d:  11.0 GB  ← user purged 1.4 GB (cleaning spike — must be discarded)
        //   t-0:   10.8 GB
        let snaps: [StorageSnapshot] = [
            .init(date: now.addingTimeInterval(-4 * day), freeBytes: 10_000 * mb),
            .init(date: now.addingTimeInterval(-3 * day), freeBytes:  9_800 * mb),
            .init(date: now.addingTimeInterval(-2 * day), freeBytes:  9_600 * mb),
            .init(date: now.addingTimeInterval(-1 * day), freeBytes: 11_000 * mb),
            .init(date: now,                              freeBytes: 10_800 * mb),
        ]
        let result = StorageForecastEstimator.estimate(
            snapshots: snaps,
            currentFree: 10_800 * mb
        )
        guard case let .days(n, _) = result.forecast else {
            preconditionFailure("expected .days, got \(result.forecast)")
        }
        // Without spike filtering the median would dip into negative
        // territory (looks like the user keeps gaining space) and the
        // forecast would slide to `.stable`. With filtering, we expect a
        // realistic medium runway — order of weeks, not days.
        precondition(n >= 14,
            "expected runway ≥ 2 weeks when cleaning spike is filtered, got \(n)")
        #endif
    }

    /// Free space INCREASING over time → no meaningful runway → `.stable`.
    static func netFreeing_isStable() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let snapshots = buildSnapshots(
            startFreeBytes: 4_000 * mb,
            ratePerDay: 30 * mb,   // gaining 30 MB/day (small enough not to spike-filter)
            spacingHours: 24,
            count: 5,
            anchor: now
        )
        let result = StorageForecastEstimator.estimate(
            snapshots: snapshots,
            currentFree: 4_200 * mb
        )
        // Every interval shows free GROWING by 30 MB → consumption is
        // negative, falls below the stable threshold → `.stable`.
        precondition(result.forecast == .stable,
            "expected .stable on net-freeing series, got \(result.forecast)")
        #endif
    }

    /// Only one snapshot (or short span) → `.calibrating`.
    static func sparseHistory_isCalibrating() {
        #if DEBUG
        let now = Date()
        let single: [StorageSnapshot] = [
            .init(date: now, freeBytes: 5_000_000_000)
        ]
        precondition(
            StorageForecastEstimator.estimate(snapshots: single, currentFree: 5_000_000_000).forecast == .calibrating,
            "single snapshot must be .calibrating"
        )

        // Two snapshots but < 2-day span → still calibrating.
        let oneDay: [StorageSnapshot] = [
            .init(date: now.addingTimeInterval(-86_400), freeBytes: 5_100_000_000),
            .init(date: now,                              freeBytes: 5_000_000_000),
        ]
        precondition(
            StorageForecastEstimator.estimate(snapshots: oneDay, currentFree: 5_000_000_000).forecast == .calibrating,
            "1-day span must be .calibrating"
        )
        #endif
    }

    static func emptyHistory_isCalibrating() {
        #if DEBUG
        let result = StorageForecastEstimator.estimate(snapshots: [], currentFree: 5_000_000_000)
        precondition(result.forecast == .calibrating, "empty history must be .calibrating")
        precondition(result.fillRatePerDay == 0, "empty history must have 0 fill rate")
        #endif
    }

    /// Snapshots intentionally fed in reverse — estimator must sort and
    /// produce the same result as the sorted version.
    static func outOfOrderTimestamps_stillForecast() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let sorted = buildSnapshots(
            startFreeBytes: 5_000 * mb,
            ratePerDay: -100 * mb,
            spacingHours: 12,
            count: 5,
            anchor: now
        )
        let reversed = Array(sorted.reversed())
        let a = StorageForecastEstimator.estimate(snapshots: sorted, currentFree: 5_000 * mb)
        let b = StorageForecastEstimator.estimate(snapshots: reversed, currentFree: 5_000 * mb)
        precondition(a == b, "estimator must be order-invariant")
        #endif
    }

    /// Tiny consumption rate vs huge free → would project >> maxDisplayDays.
    /// Verify the forecast clamps cleanly instead of returning an absurd integer.
    static func runwayClampedToMaxDisplayDays() {
        #if DEBUG
        let now = Date()
        let mb: Int64 = 1_000_000
        let day: TimeInterval = 86_400
        // 6 KB/day over 8 days → ~6 KB/day median fill, but that's
        // below `stableFillThresholdBytesPerDay` (5 MB/day) so this
        // case actually falls into `.stable`. Use a meaningfully larger
        // rate that still produces a > maxDisplayDays result: 10 MB/day
        // against 200 GB free.
        var snaps: [StorageSnapshot] = []
        var free: Int64 = 200_000 * mb   // 200 GB
        for i in (0..<9).reversed() {
            snaps.append(.init(date: now.addingTimeInterval(-Double(i) * day), freeBytes: free))
            free -= 10 * mb              // 10 MB/day
        }
        let result = StorageForecastEstimator.estimate(
            snapshots: snaps,
            currentFree: 200_000 * mb
        )
        guard case let .days(n, _) = result.forecast else {
            preconditionFailure("expected .days with huge runway, got \(result.forecast)")
        }
        precondition(n == StorageForecastEstimator.maxDisplayDays,
            "expected clamped to \(StorageForecastEstimator.maxDisplayDays), got \(n)")
        #endif
    }

    // MARK: - Helpers

    /// Build N snapshots starting at `startFreeBytes`, applying
    /// `ratePerDay` (positive = freeing, negative = consuming) over
    /// `spacingHours` between samples, anchored so the LAST snapshot
    /// sits at `anchor`.
    private static func buildSnapshots(
        startFreeBytes: Int64,
        ratePerDay: Int64,
        spacingHours: Double,
        count: Int,
        anchor: Date
    ) -> [StorageSnapshot] {
        let spacing = spacingHours * 3_600.0
        let perStep = Int64(Double(ratePerDay) * (spacingHours / 24.0))
        var out: [StorageSnapshot] = []
        var free = startFreeBytes
        for i in (0..<count).reversed() {
            let d = anchor.addingTimeInterval(-spacing * Double(i))
            out.append(StorageSnapshot(date: d, freeBytes: free))
            free += perStep   // step toward the future as we walk forward
        }
        return out
    }
}
