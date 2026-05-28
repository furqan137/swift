import SwiftUI

/// Top-right "Select All / Deselect All" pill used by every similar /
/// duplicate / screenshots / videos review screen. The label flips based
/// on `isAllSelected`; the icon chip swaps between a check and an X to
/// give the user an at-a-glance read of what tapping will do.
///
/// Best-safe semantics live with the caller — this view is just the pill.
/// See `SimilarPhotosStore+Selection.swift` for the global selection
/// methods these pills are wired to.
struct TopBarSelectAllPill: View {
    let isAllSelected: Bool
    let onTap: () -> Void
    /// Bumps the chip's font + padding so it reads as a primary action
    /// rather than a discreet utility chip. Used on Duplicate Photos
    /// to mirror the larger Cleanup-style pill the user wanted there;
    /// the rest of the app keeps the compact chip.
    var prominent: Bool = false

    var body: some View {
        Button {
            // Top-bar bulk select / deselect — fires the primary
            // buttonTap so the user feels the mass-action commit.
            // Distinct from the per-row checkbox tick (lighter
            // `.selection()`) so bulk vs single feels different in
            // the hand.
            HapticManager.shared.buttonTap()
            onTap()
        } label: {
            HStack(spacing: prominent ? 7 : 5) {
                Image(systemName: isAllSelected ? "xmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: prominent ? 15 : 12, weight: .bold))
                    .foregroundColor(
                        isAllSelected
                            ? Color(hex: "1C1917")
                            : Color(hex: "1C1917").opacity(0.55)
                    )
                    .symbolRenderingMode(.hierarchical)

                Text(isAllSelected ? "Deselect All" : "Select All")
                    .font(.system(size: prominent ? 15 : 12.5, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .tracking(-0.1)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, prominent ? 14 : 10)
            .padding(.vertical, prominent ? 9 : 5.5)
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)

                    // Active state nudges the fill toward ink so the
                    // "Deselect All" affordance reads as the destructive
                    // toggle without going full-color.
                    if isAllSelected {
                        Capsule()
                            .fill(Color(hex: "1C1917").opacity(0.06))
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        Color(hex: "1C1917").opacity(isAllSelected ? 0.16 : 0.10),
                        lineWidth: prominent ? 0.75 : 0.5
                    )
            )
            .animation(.easeOut(duration: 0.18), value: isAllSelected)
        }
        .buttonStyle(.plain)
    }
}
