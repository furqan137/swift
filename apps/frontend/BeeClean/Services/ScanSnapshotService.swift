import Foundation

// MARK: - Scan Snapshot Sync
//
// Posts the user's "total space to clean" snapshot (and the per-bucket
// breakdown) to the backend so dashboards / leaderboards / aggregate
// product analytics can use a server-side view of how much clutter
// users are sitting on. Fire-and-forget: failures are logged but never
// block the UI.
//
// Backend endpoint: `POST /scan/snapshot`
// Body schema mirrors the local DashboardSnapshot subset that matters
// for the backend (counts + bytes per bucket, plus the aggregate
// totalClutterBytes that drives the headline). Backend additions later
// (e.g. accepting per-source bytes) can be added to the request body
// without a client migration — JSONEncoder skips nil fields.

struct ScanSnapshotRequest: Codable {
    let totalClutterBytes: Int64

    let duplicateGroupCount: Int
    let duplicateBytes: Int64

    let similarGroupCount: Int
    let similarBytes: Int64

    let screenshotGroupCount: Int
    let screenshotGroupBytes: Int64

    let ungroupedScreenshotCount: Int
    let ungroupedScreenshotBytes: Int64

    let blurryCount: Int
    let blurryBytes: Int64

    let videoGroupCount: Int
    let videoGroupBytes: Int64

    let screenRecordingCount: Int
    let screenRecordingBytes: Int64

    let shortVideoCount: Int
    let shortVideoBytes: Int64

    let longVideoCount: Int
    let longVideoBytes: Int64

    let lifetimeBytesSaved: Int64
    let coinsBalance: Int
    let recordedAt: String

    /// Per-source breakdown — drives the "Cleanup by App" row on the
    /// dashboard and lets the backend aggregate which sources are
    /// driving the most clutter across the user base.
    /// Keys are the PhotoSource raw values (`"instagram"`,
    /// `"snapchat"`, etc).
    let sourceCounts: [String: Int]
    let sourceBytes: [String: Int64]

    /// Apple-equivalent total photo library bytes (the same number
    /// Settings → iPhone Storage → Photos shows). Sent alongside the
    /// per-bucket clutter so backend can compute coverage ratio
    /// (cleanable / total) per user.
    let photoLibraryTotalBytes: Int64
}

@MainActor
final class ScanSnapshotService {
    static let shared = ScanSnapshotService()

    private let auth = AuthService.shared
    /// Coalesce rapid-fire snapshot updates (each scan progress tick) so
    /// we don't pound the backend during a long scan. 30s gives the
    /// dashboard time to settle between sends without missing the
    /// final-state snapshot.
    private let minInterval: TimeInterval = 30
    private var lastSentAt: Date = .distantPast
    private var lastSentTotalBytes: Int64 = -1

    private init() {}

    /// Sync the current dashboard snapshot to the backend. Idempotent /
    /// throttled — call as often as you want, only sends when (a) the
    /// throttle window has elapsed AND (b) the total clutter actually
    /// changed since the last successful send.
    func sync(snapshot: DashboardSnapshot, force: Bool = false) {
        guard AuthService.shared.isAuthenticated else { return }
        let now = Date()
        if !force {
            let elapsed = now.timeIntervalSince(lastSentAt)
            if elapsed < minInterval { return }
            if snapshot.totalClutterBytes == lastSentTotalBytes { return }
        }
        lastSentAt = now
        lastSentTotalBytes = snapshot.totalClutterBytes

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var sourceCounts: [String: Int] = [:]
        var sourceBytes: [String: Int64] = [:]
        for (source, count) in snapshot.sourceCardCounts where count > 0 {
            sourceCounts[source.rawValue] = count
        }
        for (source, bytes) in snapshot.sourceCardBytes where bytes > 0 {
            sourceBytes[source.rawValue] = bytes
        }

        let request = ScanSnapshotRequest(
            totalClutterBytes: snapshot.totalClutterBytes,
            duplicateGroupCount: snapshot.duplicateGroupCount,
            duplicateBytes: snapshot.duplicateBytes,
            similarGroupCount: snapshot.similarGroupCount,
            similarBytes: snapshot.similarBytes,
            screenshotGroupCount: snapshot.screenshotGroupCount,
            screenshotGroupBytes: snapshot.screenshotGroupBytes,
            ungroupedScreenshotCount: snapshot.ungroupedScreenshotCount,
            ungroupedScreenshotBytes: snapshot.ungroupedScreenshotBytes,
            blurryCount: snapshot.blurryCount,
            blurryBytes: snapshot.blurryBytes,
            videoGroupCount: snapshot.videoGroupCount,
            videoGroupBytes: snapshot.videoGroupBytes,
            screenRecordingCount: snapshot.screenRecordingCount,
            screenRecordingBytes: snapshot.screenRecordingBytes,
            shortVideoCount: snapshot.shortVideoCount,
            shortVideoBytes: snapshot.shortVideoBytes,
            longVideoCount: snapshot.longVideoCount,
            longVideoBytes: snapshot.longVideoBytes,
            lifetimeBytesSaved: HiveStatsManager.shared.lifetimeBytesSaved,
            coinsBalance: HiveStatsManager.shared.coinsBalance,
            recordedAt: iso.string(from: now),
            sourceCounts: sourceCounts,
            sourceBytes: sourceBytes,
            photoLibraryTotalBytes: PhotoLibraryBytesService.shared.totalLibraryBytes
        )

        Task {
            do {
                let body = try JSONEncoder().encode(request)
                _ = try await auth.authenticatedRequest(
                    to: "/scan/snapshot",
                    method: "POST",
                    body: body
                )
            } catch {
                print("[ScanSnapshotService] sync error: \(error.localizedDescription)")
            }
        }
    }
}
