import Foundation
import Combine

// MARK: - SavedFindsStore
//
// On-device persistence for "Saved Finds" — items the user explicitly
// bookmarked while reviewing a Photos / Videos cleanup category. Mirrors
// LocalKeptStore's pattern: one JSON file under Application Support/
// BeeClean/savedFinds.json, @MainActor singleton, published collection so
// SwiftUI surfaces stay in sync with adds and removes.
//
// Stores references only — never the underlying photo/video bytes. The
// asset itself lives in the user's Photos library; if they later delete it
// through the cleanup flow, the saved entry may become stale. The
// resolution / staleness handling is the view-layer's responsibility
// (see SavedFindsViewModel).

@MainActor
final class SavedFindsStore: ObservableObject {
    static let shared = SavedFindsStore()

    @Published private(set) var items: [SavedFind] = []

    /// Flips to `true` for one cycle when the on-disk JSON failed to
    /// decode and was quarantined. Views observe this to surface a
    /// "Saved Finds recovered — some bookmarks may have been lost"
    /// banner so the user isn't silently wiped. Call `acknowledgeRecovery()`
    /// after presenting to reset.
    @Published private(set) var recoveredFromCorruption = false

    private let fileManager = FileManager.default
    private let fileURL: URL

    /// Serializes background persist tasks so two near-simultaneous
    /// `saveFind` / `removeFind` calls can't land their disk writes out
    /// of order (later write losing to earlier one). Each persist awaits
    /// the previous one before starting its own encode + write.
    private var pendingPersist: Task<Void, Never>?

    private init() {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("BeeClean", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("savedFinds.json")

        // Background load mirrors LocalKeptStore — disk read off main, then
        // a single batched main-actor write. Items start empty until the
        // load lands; @Published fires once and any observing view
        // re-renders.
        Task { [weak self] in await self?.loadAsync() }
    }

    // MARK: - Reads

    var count: Int { items.count }

    func isSaved(assetLocalIdentifier: String) -> Bool {
        items.contains { $0.assetLocalIdentifier == assetLocalIdentifier }
    }

    /// Kind-scoped check. The Quick Cleanup swipe rail exposes heart and
    /// bookmark as independent toggles, so the rail buttons need to know
    /// whether each kind is currently active for the active card.
    func isSaved(assetLocalIdentifier: String, kind: SavedFindKind) -> Bool {
        items.contains {
            $0.assetLocalIdentifier == assetLocalIdentifier
                && $0.effectiveKind == kind
        }
    }

    /// Newest-first snapshot — what the Saved Finds grid renders.
    func allSorted() -> [SavedFind] {
        items.sorted { $0.savedAt > $1.savedAt }
    }

    /// Newest-first snapshot filtered to a single kind. Used by the two
    /// sections of SavedFindsView so each tab only renders entries that
    /// match its intent.
    func allSorted(kind: SavedFindKind) -> [SavedFind] {
        items
            .filter { $0.effectiveKind == kind }
            .sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: - Writes

    /// Add a save. Idempotent: if an entry for `assetLocalIdentifier`
    /// already exists, no duplicate is created and `savedAt` is left
    /// untouched (so "Already saved" toasts read as expected).
    ///
    /// `sourceApp` carries app provenance (Snapchat / Instagram / etc.)
    /// when known — surfaced as a badge on the Saved Finds tile and as
    /// a filter chip when at least one save has it. Defaults to nil so
    /// older call sites that don't know the source compile unchanged.
    @discardableResult
    func saveFind(
        assetLocalIdentifier: String,
        mediaType: SavedFindMediaType,
        sourceCategory: SavedFindSourceCategory,
        sourceApp: PhotoSource? = nil,
        kind: SavedFindKind = .bookmarked
    ) -> Bool {
        guard !assetLocalIdentifier.isEmpty else { return false }
        if isSaved(assetLocalIdentifier: assetLocalIdentifier, kind: kind) {
            return false
        }
        let find = SavedFind(
            assetLocalIdentifier: assetLocalIdentifier,
            mediaType: mediaType,
            sourceCategory: sourceCategory,
            sourceApp: sourceApp,
            kind: kind
        )
        items.append(find)
        persist()
        return true
    }

    /// Remove every entry for `assetLocalIdentifier` regardless of kind.
    /// Used by stale-asset pruning and the legacy unsave path that
    /// doesn't know the kind.
    func removeFind(assetLocalIdentifier: String) {
        let before = items.count
        items.removeAll { $0.assetLocalIdentifier == assetLocalIdentifier }
        if items.count != before { persist() }
    }

    /// Kind-scoped removal. Used by the swipe-rail toggle so untapping
    /// the heart on a card that's ALSO bookmarked doesn't wipe the
    /// bookmark entry.
    func removeFind(assetLocalIdentifier: String, kind: SavedFindKind) {
        let before = items.count
        items.removeAll {
            $0.assetLocalIdentifier == assetLocalIdentifier
                && $0.effectiveKind == kind
        }
        if items.count != before { persist() }
    }

    /// Restore a previously-removed find with its original UUID + savedAt.
    /// Used by the Undo flow in SavedFindsView so a tap on "Undo" puts
    /// the bookmark back exactly where it was (same id, same timestamp),
    /// not as a fresh save at the top of the grid. Idempotent against
    /// the asset id: if a fresh save sneaked in between remove and undo,
    /// the restore is a no-op.
    @discardableResult
    func restoreFind(_ find: SavedFind) -> Bool {
        guard !find.assetLocalIdentifier.isEmpty else { return false }
        if isSaved(assetLocalIdentifier: find.assetLocalIdentifier) { return false }
        items.append(find)
        persist()
        return true
    }

    /// Drop saved entries whose underlying PhotoKit asset is known to
    /// be deleted. Caller passes the explicit set of ids to remove —
    /// the inverse-keep API (pass valid ids, nuke everything else) was
    /// unsafe because:
    ///   - Under `.limited` Photos access, assets outside the granted
    ///     set return no fetch result, so the "valid" set was missing
    ///     real saves that the user just couldn't enumerate, and they
    ///     got wiped from disk.
    ///   - When a fresh `saveFind(...)` lands between the VM's pre- and
    ///     post-await snapshots, the new id isn't in the "valid" set
    ///     either, so the just-saved bookmark got nuked.
    /// Explicit-removal semantics close both: only ids the caller has
    /// confirmed are gone get removed.
    func removeStaleFinds(idsKnownDeleted: Set<String>) {
        guard !idsKnownDeleted.isEmpty else { return }
        let before = items.count
        items.removeAll { idsKnownDeleted.contains($0.assetLocalIdentifier) }
        if items.count != before { persist() }
    }

    // MARK: - Disk I/O

    /// Called by the UI after surfacing the corruption banner so the
    /// signal doesn't stick across navigation.
    func acknowledgeRecovery() {
        recoveredFromCorruption = false
    }

    /// Awaits the in-flight persist chain so callers can guarantee disk
    /// state is up to date before doing something destructive (app
    /// backgrounding, force-quit grace window, store reset). No-op if
    /// nothing is queued — `.value` on a completed Task returns
    /// instantly, and a nil chain head returns immediately.
    /// Wired into `BeeCleanApp`'s scenePhase `.background` branch so
    /// detached persist tasks don't get dropped when iOS suspends us.
    func flushPendingWrites() async {
        _ = await pendingPersist?.value
    }

    private func loadAsync() async {
        let url = fileURL
        let result: (items: [SavedFind], wasCorrupt: Bool) = await Task.detached(priority: .userInitiated) {
            Self.readPersisted(at: url)
        }.value
        let loaded = result.items
        if result.wasCorrupt {
            recoveredFromCorruption = true
        }
        // Merge instead of clobber. MainActor serializes the user's
        // `saveFind(...)` taps against this continuation, but if the tap
        // lands first, `items` already holds an in-flight save —
        // assigning `items = loaded` here would wipe it out. Dedupe on
        // asset id so the merge stays clean.
        let hadInFlightSaves = !items.isEmpty
        let existingIds = Set(items.map(\.assetLocalIdentifier))
        let toAdd = loaded.filter { !existingIds.contains($0.assetLocalIdentifier) }
        if !toAdd.isEmpty {
            items.append(contentsOf: toAdd)
            // If `items` had pre-existing entries before this merge, a
            // Save tap raced the disk read. The detached persist that
            // tap fired may have already replaced the file with just
            // the new save (the load captured the old bytes BEFORE the
            // write landed). Re-persist the merged set so the disk
            // catches up. Order is guaranteed by the serialized
            // `pendingPersist` chain — this write lands after the
            // in-flight save's write.
            if hadInFlightSaves {
                persist()
            }
        }
    }

    /// Disk-side read. Pulled out so the failure / recovery path is
    /// testable and explicit instead of buried in a `?? []` silent
    /// fallback. The previous shape — `(try? decode) ?? []` — would
    /// nuke the user's entire bookmark list on a single corrupt write
    /// (force-shutdown, low-disk truncate) with no log, no backup, and
    /// no way for support to recover the file. Now: decode failures are
    /// logged and the corrupt file is moved aside under a timestamped
    /// `.corrupt` name, so the original bytes are preserved on disk for
    /// recovery while the live store starts clean.
    /// `nonisolated` so `loadAsync()` can call it from a `Task.detached`
    /// off the main actor — pure disk I/O, no shared state to protect.
    nonisolated private static func readPersisted(at url: URL) -> (items: [SavedFind], wasCorrupt: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return ([], false) }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            print("[SavedFindsStore] read failed: \(error.localizedDescription)")
            return ([], false)
        }

        // Empty file = brand-new install path; treat as empty store.
        guard !data.isEmpty else { return ([], false) }

        do {
            return (try JSONDecoder().decode([SavedFind].self, from: data), false)
        } catch {
            print("[SavedFindsStore] decode failed: \(error.localizedDescription) — quarantining file")
            quarantineCorruptFile(at: url, fm: fm)
            return ([], true)
        }
    }

    /// Move a corrupt savedFinds.json aside so the live store can recover,
    /// but the original bytes stay on disk under a timestamped `.corrupt`
    /// name. Best-effort: if the rename itself fails (read-only volume,
    /// permission issue) we log and fall through, the live store still
    /// starts clean.
    /// `nonisolated` for the same reason as `readPersisted` — pure file
    /// system work, called from the same detached task.
    nonisolated private static func quarantineCorruptFile(at url: URL, fm: FileManager) {
        let ts = Int(Date().timeIntervalSince1970)
        let corruptURL = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(ts).json")
        do {
            try fm.moveItem(at: url, to: corruptURL)
            print("[SavedFindsStore] quarantined corrupt file → \(corruptURL.lastPathComponent)")
        } catch {
            print("[SavedFindsStore] quarantine rename failed: \(error.localizedDescription)")
        }
    }

    /// Async JSON write. Snapshots `items` on the main actor (cheap —
    /// Swift array CoW), then hands the encode + atomic disk write to a
    /// background task. Writes are serialized through `pendingPersist`
    /// so two near-simultaneous taps can't land their bytes out of order.
    /// Previously: sync `JSONEncoder().encode(items) + data.write(to:)`
    /// on `@MainActor` blocked the UI for ~5–15ms per save tap once the
    /// bookmark list grew past a few hundred entries.
    private func persist() {
        let snapshot = items
        let url = fileURL
        let previous = pendingPersist
        pendingPersist = Task.detached(priority: .utility) {
            _ = await previous?.value
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("[SavedFindsStore] persist failed: \(error.localizedDescription)")
            }
        }
    }
}
