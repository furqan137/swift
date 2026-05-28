import Foundation

// MARK: - Decision Status

enum DecisionStatus: String, Codable {
    case kept
    case pendingDelete   // user swiped delete, OS hasn't confirmed yet
    case deleted         // OS-level deletion confirmed
}

struct Decision: Codable {
    let assetId: String
    var status: DecisionStatus
    var decidedAt: Date
}

// MARK: - Protocol
//
// The orchestrator never sees this protocol — callers materialize the
// excluded `Set<String>` and pass it in via `buildResolvedPlan(excluding:)`.
// Keeping the seam at the data layer (not the dependency) means we can
// swap UserDefaults for SQLite/Core Data later without touching the
// orchestrator.

protocol DecisionsStore: AnyObject, Sendable {
    func record(_ assetId: String, status: DecisionStatus)
    func status(for assetId: String) -> DecisionStatus?
    func decidedAt(for assetId: String) -> Date?
    func remove(_ assetId: String)
    var allDecidedIds: Set<String> { get }
    var pendingDeleteIds: Set<String> { get }
}

// MARK: - UserDefaults-backed default impl
//
// v1 stores the whole map in one UserDefaults blob. Acceptable up to a
// few thousand decisions. If the set grows past that, swap the backing
// store — the protocol surface is unchanged.

final class UserDefaultsDecisionsStore: DecisionsStore, @unchecked Sendable {

    static let shared = UserDefaultsDecisionsStore()

    private let key = "GuidedCleanup.decisions.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var decisions: [String: Decision] = [:]

    /// Hard cap to prevent unbounded UserDefaults growth: a power user
    /// with 10k+ cleanup sessions would otherwise re-encode the entire
    /// blob on every tap. When we exceed this, drop the oldest decisions
    /// by `decidedAt` until we're back under the cap.
    private let maxDecisions = 5000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Decision].self, from: data) {
            self.decisions = decoded
        }
    }

    func record(_ assetId: String, status: DecisionStatus) {
        lock.lock(); defer { lock.unlock() }
        decisions[assetId] = Decision(
            assetId: assetId,
            status: status,
            decidedAt: Date()
        )
        persistLocked()
    }

    func status(for assetId: String) -> DecisionStatus? {
        lock.lock(); defer { lock.unlock() }
        return decisions[assetId]?.status
    }

    func decidedAt(for assetId: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return decisions[assetId]?.decidedAt
    }

    func remove(_ assetId: String) {
        lock.lock(); defer { lock.unlock() }
        if decisions.removeValue(forKey: assetId) != nil {
            persistLocked()
        }
    }

    var allDecidedIds: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(decisions.keys)
    }

    var pendingDeleteIds: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(decisions.compactMap { $0.value.status == .pendingDelete ? $0.key : nil })
    }

    /// Must be called with `lock` already held.
    private func persistLocked() {
        if decisions.count > maxDecisions {
            pruneOldestLocked()
        }
        if let data = try? JSONEncoder().encode(decisions) {
            defaults.set(data, forKey: key)
        }
    }

    /// Must be called with `lock` already held. Drops the oldest entries
    /// by `decidedAt` until the dictionary is back under `maxDecisions`,
    /// keeping the most-recent 90% so we don't prune on every single
    /// write once we cross the threshold.
    private func pruneOldestLocked() {
        let target = (maxDecisions * 9) / 10
        let sorted = decisions.sorted { $0.value.decidedAt < $1.value.decidedAt }
        let toRemove = sorted.prefix(decisions.count - target)
        for (id, _) in toRemove { decisions.removeValue(forKey: id) }
    }
}
