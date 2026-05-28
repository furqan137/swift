import Foundation
import SwiftUI

// MARK: - Storage Forecast Manager
/// Owns the rolling history of free-bytes snapshots, persists them via
/// `@AppStorage` (JSON-encoded), and exposes a live `RunwayForecast` for
/// `StorageRunwayCard` to render.
///
/// Snapshot triggers:
///   • App foreground (via AppLifecycleManager)
///   • Forced immediately after a cleanup (via HiveStatsManager)
///   • Piggybacked off HiveScoreCard's existing disk read (zero extra I/O)
///
/// The cleanup → forecast loop intentionally projects a synthetic free
/// bytes value (`lastReadFreeBytes + projectedSavingsAccumulator`) so the
/// runway can extend *instantly* on cleanup — actual device free bytes
/// only update once iOS / PhotoKit purges the deleted assets, which can
/// take up to 30 days for photos sitting in Recently Deleted.
@MainActor
final class StorageForecastManager: ObservableObject {

    static let shared = StorageForecastManager()

    // MARK: - Persistence (AppStorage)
    //
    // All keys prefixed `forecast_` so the namespace is grep-able.
    // Snapshot array stored as JSON in a single string — AppStorage can't
    // hold arrays natively, mirrors the pattern HiveStatsManager uses for
    // `weekHistoryRaw`.

    @AppStorage("forecast_snapshotsJSON") private var snapshotsJSON: String = "[]"
    @AppStorage("forecast_lastSnapshotTimestamp") private var lastSnapshotTimestamp: Double = 0
    @AppStorage("forecast_lastFreeBytesRaw") private var lastFreeBytesRaw: String = "0"

    // MARK: - Published

    /// Categorical forecast — drives the entire card UI state machine.
    @Published private(set) var forecast: RunwayForecast = .calibrating
    /// Bytes/day consumed (median, cleaning-spike-filtered). 0 when
    /// calibrating; small positive number when stable; meaningful value
    /// when `.days`. Used for the "{free} free · filling ~{rate}/day" sub-line.
    @Published private(set) var fillRatePerDay: Int64 = 0
    /// What the UI should show as "{free} free". Combines the last real
    /// reading with the post-cleanup projection so deletions visibly bump
    /// the number before iOS actually frees the bytes.
    @Published private(set) var displayedFreeBytes: Int64 = 0
    /// Non-zero for a few seconds after a cleanup if the runway extended.
    /// UI surfaces this as a brief "+N days" accent.
    @Published private(set) var runwayDeltaDays: Int = 0

    // MARK: - Internals

    private var lastReadFreeBytes: Int64 = 0
    private var projectedSavingsAccumulator: Int64 = 0

    /// At most one snapshot per 6h of wall-clock unless `forced=true`.
    /// 6h × 4 = ~4 snapshots/day → easily clears the estimator's
    /// `minConsumptionIntervals` gate within 24-36h of normal use.
    private let throttleInterval: TimeInterval = 6 * 60 * 60
    /// Cap snapshot list size — 60 entries × ~70 bytes JSON ≈ 4 KB AppStorage.
    private let maxSnapshots: Int = 60
    /// Drop snapshots older than this — 30 days is enough history for the
    /// estimator's needs without bloating the value.
    private let maxAge: TimeInterval = 30 * 86_400
    /// How long the "+N days" accent stays visible after a cleanup.
    private let deltaSurfaceDuration: TimeInterval = 4.0

    // MARK: - Init

    private init() {
        let lastFree = Int64(lastFreeBytesRaw) ?? 0
        self.lastReadFreeBytes = lastFree
        self.displayedFreeBytes = lastFree
        recomputeForecast()
    }

    // MARK: - Public API

    /// Read disk off-main, then record. Foreground hook + scan-completed
    /// hook both come through here.
    func recordSnapshot(forced: Bool = false) {
        Task {
            let snap = await DeviceStorage.readAsync()
            recordSnapshot(free: snap.free, forced: forced)
        }
    }

    /// Direct entry — caller already has free bytes (HiveScoreCard reuses
    /// its existing read instead of double-hitting the disk).
    func recordSnapshot(free: Int64, forced: Bool = false) {
        // 0 means the volume read failed — typically sim / fresh install
        // before iOS has computed `importantUsage`. Don't pollute history.
        guard free > 0 else { return }

        let nowEpoch = Date().timeIntervalSince1970
        let elapsed = nowEpoch - lastSnapshotTimestamp
        let shouldAppend = forced
            || lastSnapshotTimestamp == 0
            || elapsed >= throttleInterval

        // Consume the pending cleanup projection only as the REAL free
        // reading climbs to meet it. iOS holds deleted photos in
        // Recently Deleted for up to 30 days, so the disk number lags
        // the user's intent — we keep the optimistic "+N days" on
        // screen until reality catches up rather than snapping back the
        // instant the next snapshot lands.
        if projectedSavingsAccumulator > 0 {
            let freedSinceLastRead = max(0, free - lastReadFreeBytes)
            projectedSavingsAccumulator = max(
                0,
                projectedSavingsAccumulator - freedSinceLastRead
            )
        }
        lastReadFreeBytes = free
        displayedFreeBytes = lastReadFreeBytes + projectedSavingsAccumulator
        lastFreeBytesRaw = String(free)

        if shouldAppend {
            var arr = persistedSnapshots
            arr.append(StorageSnapshot(date: Date(), freeBytes: free))
            writeSnapshots(arr)
            lastSnapshotTimestamp = nowEpoch
        }

        recomputeForecast()
    }

    /// Called from `HiveStatsManager.recordCleanup` immediately after a
    /// deletion. Projects the freed bytes onto the displayed free count
    /// and re-estimates the runway, surfacing any "+N days" extension as
    /// a brief UI accent.
    func recordCleanup(bytesSaved: Int64) {
        guard bytesSaved > 0 else { return }

        let priorDays: Int? = {
            if case let .days(d, _) = forecast { return d }
            return nil
        }()

        projectedSavingsAccumulator += bytesSaved
        displayedFreeBytes = lastReadFreeBytes + projectedSavingsAccumulator
        recomputeForecast()

        if let prior = priorDays,
           case let .days(d, _) = forecast,
           d > prior {
            surfaceDelta(d - prior)
        }
    }

    // MARK: - Private

    private var persistedSnapshots: [StorageSnapshot] {
        guard let data = snapshotsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([StorageSnapshot].self, from: data)
        else { return [] }
        return arr
    }

    private func writeSnapshots(_ snaps: [StorageSnapshot]) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let pruned = snaps
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
        let capped = pruned.count > maxSnapshots
            ? Array(pruned.suffix(maxSnapshots))
            : pruned
        if let data = try? JSONEncoder().encode(capped),
           let str = String(data: data, encoding: .utf8) {
            snapshotsJSON = str
        }
    }

    private func recomputeForecast() {
        let res = StorageForecastEstimator.estimate(
            snapshots: persistedSnapshots,
            currentFree: displayedFreeBytes
        )
        forecast = res.forecast
        fillRatePerDay = res.fillRatePerDay
    }

    private func surfaceDelta(_ days: Int) {
        runwayDeltaDays = days
        let captured = days
        Task {
            try? await Task.sleep(nanoseconds: UInt64(deltaSurfaceDuration * 1_000_000_000))
            // Only clear if we're still showing the same delta — a second
            // cleanup mid-window shouldn't be snuffed out by our timer.
            if runwayDeltaDays == captured { runwayDeltaDays = 0 }
        }
    }
}
