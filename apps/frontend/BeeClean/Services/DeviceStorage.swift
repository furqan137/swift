import Foundation

// MARK: - Device Storage
/// Single source of truth for reading the device's free / total volume
/// capacity. Mirrors the iOS Settings app exactly:
///   • `.volumeTotalCapacityKey` for total
///   • `.volumeAvailableCapacityForImportantUsageKey` for free,
///     falling back to the classic `.volumeAvailableCapacityKey`
///     when the system hasn't computed the "important" value yet
///     (rare on simulators / fresh installs).
///
/// All I/O is intentionally synchronous + cheap — callers MUST wrap in
/// `Task.detached(priority: .utility)` so the disk read never lands on
/// the main thread.
enum DeviceStorage {

    struct Snapshot: Equatable {
        let total: Int64
        let free: Int64

        static let zero = Snapshot(total: 0, free: 0)
    }

    /// Synchronous read. Call OFF the main thread.
    static func read() -> Snapshot {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? home.resourceValues(forKeys: keys) else {
            return .zero
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return Snapshot(total: total, free: free)
    }

    /// Async wrapper — always reads on a utility-priority detached task.
    static func readAsync() async -> Snapshot {
        await Task.detached(priority: .utility) { read() }.value
    }
}
