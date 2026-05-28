import SwiftUI

// MARK: - Home Top Bar
//
// Floating top row over the HomeView hero. Three sleek icons:
//   • Shop (BitePal accessory store)
//   • Trophy (Leaderboard)
//   • Coins (balance pill with live count → CoinsView)
//
// Rendered inside HomeView's `.safeAreaInset(edge: .top)` so the icons
// pin to the top of the screen and don't get scrolled away with the
// content.
struct HomeTopBar: View {
    @ObservedObject private var stats = HiveStatsManager.shared
    let onShop: () -> Void
    let onLeaderboard: () -> Void
    let onCoins: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton(systemName: "bag.fill", tint: .categoryRose, action: onShop)
            iconButton(systemName: "trophy.fill", tint: .categoryHoney, action: onLeaderboard)

            Spacer()

            Button(action: onCoins) {
                HStack(spacing: 6) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LinearGradient.honeyGradient)
                    Text("\(stats.coinsBalance)")
                        .font(.labelMedium)
                        .foregroundColor(.foreground)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func iconButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
