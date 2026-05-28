import SwiftUI

// MARK: - Leaderboard Preview Card
//
// Compact leaderboard surface rendered on the Progress tab. Shows the
// top 3 in a gold/silver/bronze podium, the user's own row, and a CTA
// to push into the full LeaderboardView.
struct LeaderboardPreviewCard: View {
    @StateObject private var vm = LeaderboardViewModel.shared
    @State private var pushFull: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            podium
            if let me = vm.selfEntry {
                Divider().opacity(0.5)
                LeaderboardRow(entry: me)
            }
            seeAllButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 0.5)
        )
        .navigationDestination(isPresented: $pushFull) {
            LeaderboardView()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.honeyGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leaderboard")
                    .font(.titleSmall)
                    .foregroundColor(.foreground)
                Text("Ranked by coins · storage freed shown alongside")
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground)
            }
            Spacer()
        }
    }

    private var podium: some View {
        let top3 = Array(vm.entries.prefix(3))
        return HStack(alignment: .bottom, spacing: 8) {
            if top3.count >= 2 { podiumTile(top3[1], place: 2) }
            if top3.count >= 1 { podiumTile(top3[0], place: 1) }
            if top3.count >= 3 { podiumTile(top3[2], place: 3) }
        }
    }

    private func podiumTile(_ entry: LeaderboardEntry, place: Int) -> some View {
        let medal = medalColor(place)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(medal.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image("BeeHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }
                Image(systemName: "medal.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(medal)
                    .offset(x: 4, y: -2)
            }
            Text(entry.displayName)
                .font(.bodySmall)
                .foregroundColor(.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 3) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(LinearGradient.honeyGradient)
                Text("\(entry.coins)")
                    .font(.labelSmall)
                    .foregroundColor(.foreground)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.surfaceLight)
        )
    }

    private func medalColor(_ place: Int) -> Color {
        switch place {
        case 1: return Color(hex: "D4A01C")
        case 2: return Color(hex: "B0B6BA")
        case 3: return Color(hex: "B87333")
        default: return .mutedForeground
        }
    }

    private var seeAllButton: some View {
        Button {
            HapticManager.shared.buttonTap()
            pushFull = true
        } label: {
            HStack {
                Text("See full leaderboard")
                    .font(.labelMedium)
                    .foregroundColor(.foreground)
                Spacer()
                ChevronGlyph()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(Color.surfaceLight)
            )
        }
        .buttonStyle(.plain)
    }
}
