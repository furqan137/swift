import SwiftUI

// MARK: - DeletionGateView
//
// Backward-compatible wrapper around GateCoordinator configured for
// the Photos section. Existing call sites that use DeletionGateView
// continue to work identically without any changes needed.

struct DeletionGateView: View {
    let selectedCount: Int
    let onDeleteApproved: (Int) async -> Int
    let onPaywall: (String) -> Void

    var body: some View {
        GateCoordinator(
            config: .config(for: .photos),
            selectedCount: selectedCount,
            onActionApproved: onDeleteApproved,
            onPaywall: onPaywall
        )
    }
}
