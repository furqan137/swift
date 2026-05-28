import SwiftUI

// MARK: - Coins View
//
// Detail screen for the BeeClean coin balance. Shows the current
// balance, how it's earned (1 coin per 10 MB freed lifetime), and
// any bonus coins on top.
struct CoinsView: View {
    @ObservedObject private var stats = HiveStatsManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                balanceCard
                breakdownCard
                howToEarnCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("BeeClean Coins")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var balanceCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(LinearGradient.honeyGradient)

            Text("\(stats.coinsBalance)")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.foreground)
            Text("BeeClean Coins")
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFE066"), Color(hex: "FFC93C")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    private var breakdownCard: some View {
        let earnedFromCleaning = Int(stats.lifetimeBytesSaved / 10_000_000)
        let bonus = stats.bonusCoins

        return VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown")
                .font(.titleSmall)
                .foregroundColor(.foreground)

            row(
                icon: "trash.fill",
                label: "From cleanups",
                value: "+\(earnedFromCleaning)",
                sub: "1 coin per 10 MB freed"
            )
            Divider()
            row(
                icon: "gift.fill",
                label: bonus >= 0 ? "Bonuses" : "Spent",
                value: bonus >= 0 ? "+\(bonus)" : "\(bonus)",
                sub: bonus >= 0 ? "Achievements & rewards" : "BitePal purchases"
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.card)
        )
    }

    private var howToEarnCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Earn More Coins")
                .font(.titleSmall)
                .foregroundColor(.foreground)
            bullet(symbol: "trash.fill", text: "Free up storage — 1 coin per 10 MB cleaned.")
            bullet(symbol: "flame.fill", text: "Keep your streak alive for daily bonuses.")
            bullet(symbol: "trophy.fill", text: "Climb the leaderboard to unlock seasonal rewards.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.surfaceLight)
        )
    }

    private func row(icon: String, label: String, value: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.labelMedium)
                    .foregroundColor(.foreground)
                Text(sub)
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground)
            }
            Spacer()
            Text(value)
                .font(.titleSmall)
                .foregroundColor(.foreground)
        }
    }

    private func bullet(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.bodySmall)
                .foregroundColor(.foreground)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack { CoinsView() }
}
