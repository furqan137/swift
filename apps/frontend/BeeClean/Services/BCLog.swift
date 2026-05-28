import Foundation
import os

// MARK: - Debug Log Gate
//
// Tiny wrapper around `print` that compiles out of release builds.
//
// Why this exists: production builds were shipping ~120 active `print(…)`
// calls, several of which fire per-asset inside scan loops. On a 4.5k-photo
// library with a partial iCloud sync, the per-asset "decode failed" /
// "image load failed" / "labels for …" lines log thousands of times into
// `os_log` — each one round-trips into the unified logging daemon and
// blocks the calling thread for a few hundred microseconds. In aggregate
// those pile up into visible scan-progress hitches that real users feel.
//
// The fix is structural, not a sed-and-hope: every per-iteration log site
// in the scan paths now goes through `BCLog.debug(…)`, which is empty in
// release and a normal `print(…)` in DEBUG. One-off logs (e.g. "scan
// started", "X results returned") still use `print` directly — they cost
// nothing and are useful for live triage if a TestFlight user is on a
// console session.
//
// We intentionally do NOT route through `os.Logger` here. Logger respects
// the unified-logging system in production, but the goal is to remove the
// cost entirely from release builds, not just relabel the persistent log.
// `#if DEBUG` is the only guard that actually deletes the call site at
// compile time.
enum BCLog {
    /// Compiles to a no-op in release builds. Use for any log that fires
    /// inside a per-asset / per-iteration scan loop.
    @inline(__always)
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
}
