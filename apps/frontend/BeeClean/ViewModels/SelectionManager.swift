import Foundation

@Observable
final class SelectionManager {
    private(set) var selectedIds: Set<String> = []

    func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll(_ ids: [String]) {
        selectedIds.formUnion(ids)
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func isSelected(_ id: String) -> Bool {
        selectedIds.contains(id)
    }

    var selectedCount: Int { selectedIds.count }
}
