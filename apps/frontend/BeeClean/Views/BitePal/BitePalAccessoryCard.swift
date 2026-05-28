import SwiftUI

// MARK: - BitePal Accessory Card
//
// Single grid cell in the BitePal shop. Three terminal states drive
// the button label and tint:
//
//   • Locked  — user doesn't own it. Tap → Buy (debits coins).
//   • Owned   — user owns it, not equipped. Tap → Equip.
//   • Equipped — currently on the bee. Tap → Unequip.
struct BitePalAccessoryCard: View {
    let accessory: BeeAccessory
    @ObservedObject var vm: BitePalViewModel = .shared
    @ObservedObject var stats: HiveStatsManager = .shared

    @State private var deniedFlash: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(Color.surfaceLight)
                    .frame(height: 100)
                    .overlay(
                        AccessoryImage(accessory: accessory, size: 72)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .strokeBorder(
                                vm.isEquipped(accessory)
                                    ? Color.accentColor
                                    : Color.border,
                                lineWidth: vm.isEquipped(accessory) ? 2 : 0.5
                            )
                    )

                if accessory.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.accentColor))
                        .padding(8)
                }
            }

            Text(accessory.displayName)
                .font(.labelMedium)
                .foregroundColor(.foreground)
                .lineLimit(1)

            Button(action: tap) {
                HStack(spacing: 4) {
                    if vm.isEquipped(accessory) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Equipped")
                    } else if vm.isOwned(accessory) {
                        Text("Equip")
                    } else {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundColor(.white)
                        Text("\(accessory.price)")
                    }
                }
                .font(.labelSmall)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(buttonColor)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(deniedFlash ? 1.08 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: deniedFlash)
        }
        .padding(8)
    }

    private var buttonColor: Color {
        if vm.isEquipped(accessory) { return .success }
        if vm.isOwned(accessory) { return .accentColor }
        return stats.coinsBalance >= accessory.price ? .primaryColor : .mutedForeground
    }

    private func tap() {
        if vm.isEquipped(accessory) {
            vm.unequip(category: accessory.category)
        } else if vm.isOwned(accessory) {
            vm.equip(accessory)
        } else {
            if !vm.buy(accessory) {
                deniedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    deniedFlash = false
                }
            }
        }
    }
}
