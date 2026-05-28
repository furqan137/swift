import Foundation

// MARK: - Stable group ordering (kills mid-scroll list shuffling)
//
// `SimilarPhotosStore.groups` is mutated as the scan completes
// (waves of detection results land asynchronously, and confidence
// re-sorting can reorder the array). When a view binds the rendered
// list directly to `vm.groups`, every mutation triggers a re-render
// AND can move items mid-scroll — the user reports "everything
// shuffles as I scroll." That's the bug.
//
// `StableGroupOrder` solves this by tracking the FIRST-SEEN order
// of group ids. Once a group has been rendered, its position is
// pinned. New groups append at the end. Deleted groups vanish.
// Selection / contents stay live because we look the VM up by id
// from the store on every read.
//
// Usage:
//   @State private var order = StableGroupOrder()
//   ForEach(order.ordered(from: vm.groups)) { group in ... }
//   .onChange(of: vm.groups.count) { _, _ in order.absorb(vm.groups) }
//   .task { order.absorb(vm.groups) }
struct StableGroupOrder: Equatable {
    /// First-seen ordering. Append-only during scan; deletions prune.
    private(set) var renderOrder: [UUID] = []

    /// Returns the live `groups` reordered by first-seen position.
    /// Anything in the store but not yet in `renderOrder` is appended
    /// at the end (in the store's current order among themselves).
    func ordered<T: Identifiable>(from store: [T]) -> [T] where T.ID == UUID {
        let byId = Dictionary(uniqueKeysWithValues: store.map { ($0.id, $0) })
        var out: [T] = []
        out.reserveCapacity(store.count)
        // Pinned positions first
        for id in renderOrder {
            if let item = byId[id] { out.append(item) }
        }
        // Newly-seen (not in renderOrder yet) at the end. Caller
        // typically calls `absorb` after this on the next render
        // tick to lock these positions for the NEXT render.
        let pinned = Set(renderOrder)
        for item in store where !pinned.contains(item.id) {
            out.append(item)
        }
        return out
    }

    /// Append never-seen ids and prune deleted ones. Idempotent.
    mutating func absorb<T: Identifiable>(_ store: [T]) where T.ID == UUID {
        let storeIds = Set(store.map(\.id))
        // Drop ids that no longer exist (user deleted, scanner pruned, etc.)
        renderOrder.removeAll { !storeIds.contains($0) }
        // Append any new ids the store has that we haven't pinned yet
        let pinned = Set(renderOrder)
        for item in store where !pinned.contains(item.id) {
            renderOrder.append(item.id)
        }
    }

    /// Wipe the rendered order and re-seed from the store. Use for
    /// pull-to-refresh / explicit user re-syncs.
    mutating func reseed<T: Identifiable>(from store: [T]) where T.ID == UUID {
        renderOrder = store.map(\.id)
    }
}
