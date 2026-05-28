import Foundation
import Photos
import SwiftUI

// MARK: - SavedFindsViewModel
//
// Loads the Saved Finds store, resolves each entry's underlying PHAsset,
// and silently drops references whose asset no longer exists (the
// "user saved then swiped-left to delete" edge case). The view layer
// reads from `resolved` — already filtered, newest-first.
//
// Lifecycle: registers as a PHPhotoLibraryChangeObserver while the
// Saved Finds screen is on-screen, so if the user deletes a saved
// photo through Apple Photos (or finishes a cleanup pass that deletes
// one) the grid updates without needing a manual refresh.

@MainActor
final class SavedFindsViewModel: NSObject, ObservableObject {
    @Published private(set) var resolved: [SavedFind] = []
    @Published private(set) var isLoading: Bool = false

    private let store: SavedFindsStore
    private var isObservingLibrary = false

    convenience override init() {
        // Default-argument expression `= .shared` was evaluated in the
        // caller's nonisolated context, which trips Swift 6 strict
        // concurrency the moment HapticManager / SavedFindsStore go
        // @MainActor. Wrapping the access in an explicit MainActor init
        // body keeps the seam (tests can still inject a custom store).
        self.init(store: SavedFindsStore.shared)
    }

    init(store: SavedFindsStore) {
        self.store = store
        super.init()
    }

    deinit {
        if isObservingLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    var isEmpty: Bool { resolved.isEmpty }
    var count: Int { resolved.count }

    // MARK: - Lifecycle hooks (call from .onAppear / .onDisappear)

    func startObservingLibrary() {
        guard !isObservingLibrary else { return }
        // Read-status check is cheap and the observer is a no-op until a
        // change lands — register unconditionally so the user gets live
        // updates as soon as they grant permission.
        PHPhotoLibrary.shared().register(self)
        isObservingLibrary = true
    }

    func stopObservingLibrary() {
        guard isObservingLibrary else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isObservingLibrary = false
    }

    // MARK: - Loading

    /// Pull from the store, resolve assets off the main actor, prune
    /// stale references, and publish the filtered list.
    ///
    /// The detached PhotoKit fetch is an `await` suspension point —
    /// during it, other MainActor work runs freely, including
    /// `remove()` calls from the user tapping Remove on a tile. If we
    /// blindly published `raw.filter(...)` afterwards (using the pre-
    /// suspension snapshot), the just-removed entry would zombie back
    /// into `resolved` and the tile would re-appear until the next
    /// reload pass. Re-snapshotting the store post-suspension closes
    /// the race: the validated id set still tells us which assets
    /// PhotoKit could resolve, but we apply it against the *current*
    /// store contents.
    func reload() async {
        isLoading = true
        let raw = store.allSorted()
        let attemptedIds = Set(raw.map(\.assetLocalIdentifier))

        // PhotoKit's verdict is only a complete census under
        // `.authorized`. Under `.limited`, assets outside the granted
        // set are silently absent from fetch results — that's NOT the
        // same as "deleted", and pruning on that basis would wipe real
        // bookmarks from disk every time the user opens this screen.
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let hasFullAccess = (auth == .authorized)

        let valid: Set<String> = await Task.detached(priority: .userInitiated) {
            guard !attemptedIds.isEmpty else { return Set<String>() }
            let fetched = PHAsset.fetchAssets(
                withLocalIdentifiers: Array(attemptedIds),
                options: nil
            )
            var valid: Set<String> = []
            fetched.enumerateObjects { asset, _, _ in
                valid.insert(asset.localIdentifier)
            }
            return valid
        }.value

        // Re-snapshot AFTER the await — `remove()`, `restore()`, or a
        // fresh `saveFind(...)` may have mutated the store while the
        // PhotoKit fetch was in flight. The user's most recent action
        // must win over the stale `raw` we captured before suspending.
        let freshRaw = store.allSorted()

        // Only prune when PhotoKit returned an authoritative census,
        // and only for ids we explicitly asked about. A find added
        // after `attemptedIds` was computed is NOT a candidate for
        // removal here — it just hasn't been validated yet.
        if hasFullAccess {
            let staleIds = attemptedIds.subtracting(valid)
            store.removeStaleFinds(idsKnownDeleted: staleIds)
        }

        resolved = freshRaw.filter { find in
            // PhotoKit returned this asset — always render it.
            if valid.contains(find.assetLocalIdentifier) { return true }
            // We didn't ask PhotoKit about this id (it was added to the
            // store after our snapshot). Optimistically render — the
            // next reload pass will validate.
            if !attemptedIds.contains(find.assetLocalIdentifier) { return true }
            // Asked about, not returned. Under full access this is a
            // confirmed-deleted asset and the prune above already
            // removed it from the store; skip rendering. Under
            // limited/denied access keep rendering — the asset may
            // still exist, just not be enumerable from our process.
            return !hasFullAccess
        }
        isLoading = false
    }

    func remove(_ find: SavedFind) {
        store.removeFind(assetLocalIdentifier: find.assetLocalIdentifier)
        resolved.removeAll { $0.id == find.id }
    }

    /// View-only prune. Removes a find from the published `resolved`
    /// array without touching the store. Used by `SavedFindTile` when
    /// PhotoKit can't render a thumbnail — under `.limited` access the
    /// asset may still exist outside the granted set, so we hide the
    /// tile but keep the bookmark on disk. Re-granting full access and
    /// reloading will surface the tile again. This closes the same
    /// over-prune hole the auth-gated `reload()` closed for the store
    /// — the tile path needs the same guarantee.
    func dropFromResolvedOnly(_ find: SavedFind) {
        resolved.removeAll { $0.id == find.id }
    }

    /// Restore a previously-removed find (single or as part of a bulk
    /// remove) back into the store + the resolved working set. Keeps
    /// the original UUID + savedAt so the grid re-renders the tile in
    /// its original sort position rather than at the top as a fresh
    /// save. Used by the Undo bar in SavedFindsView.
    @discardableResult
    func restore(_ find: SavedFind) -> Bool {
        let added = store.restoreFind(find)
        guard added else { return false }
        // Insert back into the resolved list so the SwiftUI grid
        // refreshes immediately instead of waiting for the next
        // reload pass.
        if !resolved.contains(where: { $0.id == find.id }) {
            resolved.append(find)
            // Re-sort newest-first to match `allSorted()` semantics.
            resolved.sort { $0.savedAt > $1.savedAt }
        }
        return true
    }

    /// Bulk variant — used by SavedFindsView's bulk-remove Undo.
    func restore(_ finds: [SavedFind]) {
        guard !finds.isEmpty else { return }
        var anyRestored = false
        for find in finds {
            if store.restoreFind(find) {
                anyRestored = true
                if !resolved.contains(where: { $0.id == find.id }) {
                    resolved.append(find)
                }
            }
        }
        if anyRestored {
            resolved.sort { $0.savedAt > $1.savedAt }
        }
    }
}

// MARK: - PHPhotoLibraryChangeObserver

extension SavedFindsViewModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // PhotoKit fires this on a background queue. Hop to main and
        // re-resolve — same code path as a manual refresh, so anything
        // deleted upstream gets pruned and the grid re-renders.
        Task { @MainActor [weak self] in
            await self?.reload()
        }
    }
}
