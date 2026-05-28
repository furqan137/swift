import Foundation

// MARK: - Storage Forecast Types

/// One point-in-time observation of device free space.
/// Persisted as JSON inside a single `@AppStorage` string so the snapshot
/// history survives relaunches without needing a new persistence layer.
struct StorageSnapshot: Codable, Equatable, Hashable {
    let date: Date
    let freeBytes: Int64
}

/// Confidence flag the UI uses to hedge wording — low while still
/// learning, high once we have ≥ `highConfidenceSpanDays` of history.
enum ForecastConfidence: String, Codable, Equatable {
    case low
    case high
}

/// Public forecast surface consumed by `StorageRunwayCard`.
/// - `.calibrating` — not enough data; UI says "Learning your pace…"
/// - `.stable`      — fill rate ≈ 0 or net-freeing; UI says "Holding steady"
/// - `.days(n, c)`  — projected days-until-full + confidence flag
enum RunwayForecast: Equatable {
    case calibrating
    case stable
    case days(Int, ForecastConfidence)
}

/// Result returned by the pure estimator. Carries both the categorical
/// forecast and the underlying fill rate (bytes consumed per day, after
/// median + cleaning-spike filtering) so the UI can render the sub-line
/// "{free} free · filling ~{rate}/day" without reaching back into the
/// algorithm.
struct ForecastResult: Equatable {
    let forecast: RunwayForecast
    let fillRatePerDay: Int64
}

// MARK: - Pure Estimator
//
// Intentionally a stateless `enum` so it stays trivially unit-testable:
// feed it any `[StorageSnapshot]` + `currentFree`, get back a
// `ForecastResult`. No I/O, no global state, no MainActor.
enum StorageForecastEstimator {

    // MARK: Tunables

    /// Need at least this many consumption-only intervals before we trust
    /// the median. With 6h snapshot throttle, 2 days of data delivers
    /// ~8 intervals, so a real-world install clears this within 24-36h.
    static let minConsumptionIntervals: Int = 2

    /// History must span this many days end-to-end before leaving the
    /// `.calibrating` state — one snapshot per day for 2 days minimum.
    static let minSnapshotSpanDays: Double = 2.0

    /// History spanning at least this many days is considered confident.
    static let highConfidenceSpanDays: Double = 7.0

    /// Any interval where free space INCREASED by more than this is a
    /// cleaning event (user purged Photos, iOS evicted caches, app
    /// uninstalled, etc.). Excluded from the consumption-rate sample so a
    /// single big cleanup doesn't fool the algorithm into "your phone is
    /// gaining space forever".
    static let cleaningJumpThresholdBytes: Int64 = 50_000_000   // 50 MB

    /// Below this median consumption rate the runway reads as `.stable`
    /// rather than a misleadingly large day count.
    static let stableFillThresholdBytesPerDay: Int64 = 5_000_000   // 5 MB/day

    /// Hard ceiling on the day count we hand to the UI. Anything above
    /// this is rendered as "6+ months" rather than an absurd integer.
    static let maxDisplayDays: Int = 180

    // MARK: Estimate

    /// Compute a forecast from the snapshot history + the user's current
    /// free bytes. `currentFree` is passed in (rather than derived from
    /// the last snapshot) so callers can project a post-cleanup runway by
    /// supplying `lastFree + bytesSaved`.
    static func estimate(
        snapshots: [StorageSnapshot],
        currentFree: Int64
    ) -> ForecastResult {
        // Sort defensively — persistence layer guarantees order, but the
        // estimator shouldn't trust callers.
        let sorted = snapshots.sorted { $0.date < $1.date }

        guard sorted.count >= 2,
              let first = sorted.first,
              let last = sorted.last
        else {
            return ForecastResult(forecast: .calibrating, fillRatePerDay: 0)
        }

        let spanDays = last.date.timeIntervalSince(first.date) / 86_400.0
        guard spanDays >= minSnapshotSpanDays else {
            return ForecastResult(forecast: .calibrating, fillRatePerDay: 0)
        }

        // Walk consecutive pairs and turn each into a bytes/day rate.
        // Negative `freeDelta` = the user CONSUMED space during that
        // interval (free shrank). Positive `freeDelta` = space appeared
        // (cleanup / cache eviction / OTA storage release).
        var consumptionRates: [Int64] = []
        consumptionRates.reserveCapacity(sorted.count - 1)

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let dt = curr.date.timeIntervalSince(prev.date)
            // Out-of-order / clock-skewed pairs — ignore.
            guard dt > 0 else { continue }
            let freeDelta = curr.freeBytes - prev.freeBytes
            // Cleaning spike — discard.
            if freeDelta > cleaningJumpThresholdBytes { continue }
            let dtDays = dt / 86_400.0
            let consumedPerDay = Int64((Double(-freeDelta) / dtDays).rounded())
            consumptionRates.append(consumedPerDay)
        }

        guard consumptionRates.count >= minConsumptionIntervals else {
            return ForecastResult(forecast: .calibrating, fillRatePerDay: 0)
        }

        let median = Self.median(consumptionRates)

        // Net-freeing OR effectively static → not a meaningful runway.
        if median <= stableFillThresholdBytesPerDay {
            return ForecastResult(forecast: .stable, fillRatePerDay: max(median, 0))
        }

        let confidence: ForecastConfidence = spanDays >= highConfidenceSpanDays ? .high : .low
        let rawDays = Double(currentFree) / Double(median)
        let clampedDays = max(0, min(Int(rawDays.rounded()), maxDisplayDays))
        return ForecastResult(
            forecast: .days(clampedDays, confidence),
            fillRatePerDay: median
        )
    }

    // MARK: Helpers

    /// Median of an Int64 array. Defined here (not via Algorithms package)
    /// so the estimator stays dependency-free for the test target.
    static func median(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
