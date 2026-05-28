import SwiftUI

// MARK: - Leaderboard Detail View
//
// Drill-down profile for a single leaderboard entry. Top 3 get a
// gold/silver/bronze ribbon at the top. The bee is rendered with all
// equipped accessories overlaid.
struct LeaderboardDetailView: View {
    let entry: LeaderboardEntry

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                if entry.rank <= 3 {
                    ribbon
                }
                beePreview
                statsCard
                accessoriesCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Ribbon

    private var ribbon: some View {
        HStack(spacing: 8) {
            Image(systemName: "medal.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(medalColor)
            Text(ribbonLabel)
                .font(.titleSmall)
                .foregroundColor(.foreground)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(medalColor.opacity(0.18))
        )
        .overlay(
            Capsule().strokeBorder(medalColor.opacity(0.6), lineWidth: 1)
        )
    }

    private var ribbonLabel: String {
        switch entry.rank {
        case 1: return "1st — Gold Hive"
        case 2: return "2nd — Silver Hive"
        case 3: return "3rd — Bronze Hive"
        default: return "Rank #\(entry.rank)"
        }
    }

    private var medalColor: Color {
        switch entry.rank {
        case 1: return Color(hex: "D4A01C")
        case 2: return Color(hex: "B0B6BA")
        case 3: return Color(hex: "B87333")
        default: return .accentColor
        }
    }

    // MARK: Bee Preview

    private var beePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFE066"), Color(hex: "FFC93C")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 280)

            Image("BeeHero")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            ForEach(entry.equippedAccessoryIds, id: \.self) { id in
                if let accessory = BeeAccessoryCatalog.item(id: id) {
                    AccessoryImage(accessory: accessory, size: 60)
                        .offset(equipOffset(for: accessory.category))
                }
            }
        }
    }

    private func equipOffset(for category: AccessoryCategory) -> CGSize {
        switch category {
        case .hats:        return CGSize(width: 0,   height: -80)
        case .antennae:    return CGSize(width: 0,   height: -95)
        case .sunglasses:  return CGSize(width: 0,   height: -25)
        case .ties:        return CGSize(width: 0,   height: 25)
        case .bracelets:   return CGSize(width: 55,  height: 35)
        case .belts:       return CGSize(width: 0,   height: 50)
        case .wings:       return CGSize(width: -75, height: 0)
        case .watch:       return CGSize(width: -55, height: 35)
        case .diamonds:    return CGSize(width: 0,   height: 5)
        case .shoes:       return CGSize(width: 0,   height: 80)
        case .backgrounds: return CGSize(width: 0,   height: 0)
        }
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Stats")
                    .font(.titleSmall)
                    .foregroundColor(.foreground)
                Spacer()
            }
            HStack(spacing: 10) {
                statTile(
                    icon: "bitcoinsign.circle.fill",
                    label: "Coins",
                    value: "\(entry.coins)",
                    tint: .accentColor
                )
                statTile(
                    icon: "externaldrive.fill",
                    label: "Freed",
                    value: String(format: "%.1f GB", entry.storageFreedGB),
                    tint: .categoryTeal
                )
                statTile(
                    icon: "flame.fill",
                    label: "Streak",
                    value: "\(entry.streak)",
                    tint: .categoryRose
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.card)
        )
    }

    private func statTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.titleSmall)
                .foregroundColor(.foreground)
            Text(label)
                .font(.bodySmall)
                .foregroundColor(.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.surfaceLight)
        )
    }

    // MARK: Accessories

    private var accessoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bling")
                .font(.titleSmall)
                .foregroundColor(.foreground)
            if entry.equippedAccessoryIds.isEmpty {
                Text("Nothing equipped yet.")
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(entry.equippedAccessoryIds, id: \.self) { id in
                        if let accessory = BeeAccessoryCatalog.item(id: id) {
                            VStack(spacing: 4) {
                                AccessoryImage(accessory: accessory, size: 48)
                                Text(accessory.displayName)
                                    .font(.bodySmall)
                                    .foregroundColor(.mutedForeground)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                                    .fill(Color.surfaceLight)
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.card)
        )
    }
}
