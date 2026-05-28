import SwiftUI

// MARK: - Leaderboard Row
//
// Single ladder row outside the podium. Coins headline the rank, storage
// freed sits underneath as the honest flex.
struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(.labelMedium)
                .foregroundColor(.mutedForeground)
                .frame(width: 38, alignment: .leading)

            ZStack {
                Circle()
                    .fill(entry.isSelf ? Color.accentColor.opacity(0.18) : Color.surfaceLight)
                    .frame(width: 40, height: 40)
                Image("BeeHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                if let firstId = entry.equippedAccessoryIds.first,
                   let accessory = BeeAccessoryCatalog.item(id: firstId) {
                    AccessoryImage(accessory: accessory, size: 18)
                        .offset(y: -8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.labelMedium)
                    .foregroundColor(.foreground)
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.mutedForeground)
                    Text(String(format: "%.1f GB", entry.storageFreedGB))
                        .font(.bodySmall)
                        .foregroundColor(.mutedForeground)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(LinearGradient.honeyGradient)
                Text("\(entry.coins)")
                    .font(.titleSmall)
                    .foregroundColor(.foreground)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(entry.isSelf ? Color.accentColor.opacity(0.08) : Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(
                    entry.isSelf ? Color.accentColor : Color.border,
                    lineWidth: entry.isSelf ? 1.5 : 0.5
                )
        )
    }
}
