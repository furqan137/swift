import SwiftUI

// MARK: - Leaderboard View
//
// One ladder, no toggle. Coins are the single ranking metric. Storage
// freed shows alongside as the secondary stat. Caption under the
// subtitle sets the expectation so nobody wonders why the GB numbers
// don't always march in order.
struct LeaderboardView: View {
    @StateObject private var vm = LeaderboardViewModel.shared
    @State private var detailEntry: LeaderboardEntry?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                header
                podium
                listSection
                if let selfEntry = vm.selfEntry, selfEntry.rank > 100 {
                    selfSticky(entry: selfEntry)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.refresh() }
        .navigationDestination(item: $detailEntry) { entry in
            LeaderboardDetailView(entry: entry)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Top 100 Cleaners")
                .font(.titleLarge)
                .foregroundColor(.foreground)
            Text("Ranked by coins · storage freed shown alongside")
                .font(.bodySmall)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    // MARK: Podium

    private var podium: some View {
        let top3 = Array(vm.entries.prefix(3))
        return HStack(alignment: .bottom, spacing: 10) {
            if top3.count >= 2 { podiumCard(top3[1], place: 2) }
            if top3.count >= 1 { podiumCard(top3[0], place: 1) }
            if top3.count >= 3 { podiumCard(top3[2], place: 3) }
        }
        .frame(maxWidth: .infinity)
    }

    private func podiumCard(_ entry: LeaderboardEntry, place: Int) -> some View {
        let medal = medalColor(place: place)
        let height: CGFloat = place == 1 ? 140 : 112
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(medal.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image("BeeHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                    ForEach(entry.equippedAccessoryIds.prefix(2), id: \.self) { id in
                        if let accessory = BeeAccessoryCatalog.item(id: id) {
                            AccessoryImage(accessory: accessory, size: 22)
                                .offset(y: accessory.category == .hats ? -16 : 4)
                        }
                    }
                }
                Image(systemName: "medal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(medal)
                    .offset(x: 6, y: -4)
            }
            Text(entry.displayName)
                .font(.labelMedium)
                .foregroundColor(.foreground)
                .lineLimit(1)
            HStack(spacing: 3) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(LinearGradient.honeyGradient)
                Text("\(entry.coins)")
                    .font(.titleSmall)
                    .foregroundColor(.foreground)
            }
            HStack(spacing: 3) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.mutedForeground)
                Text(String(format: "%.1f GB", entry.storageFreedGB))
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(medal.opacity(0.6), lineWidth: 1.5)
        )
        .onTapGesture { detailEntry = entry }
    }

    private func medalColor(place: Int) -> Color {
        switch place {
        case 1: return Color(hex: "D4A01C")
        case 2: return Color(hex: "B0B6BA")
        case 3: return Color(hex: "B87333")
        default: return .mutedForeground
        }
    }

    // MARK: List 4..100

    private var listSection: some View {
        VStack(spacing: 8) {
            ForEach(Array(vm.entries.dropFirst(3).prefix(97))) { entry in
                Button {
                    detailEntry = entry
                } label: {
                    LeaderboardRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Self Sticky

    private func selfSticky(entry: LeaderboardEntry) -> some View {
        VStack(spacing: 6) {
            Text("Your Rank")
                .font(.bodySmall)
                .foregroundColor(.mutedForeground)
            LeaderboardRow(entry: entry)
        }
        .padding(.top, 12)
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
    }
}
