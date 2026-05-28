import SwiftUI

// MARK: - BitePal View
//
// The accessory shop. Modeled on the BitePal raccoon-store reference:
//   • Top hero — bee preview with whatever's equipped, name, hearts,
//     and a coin balance pill on the trailing edge.
//   • Category tab strip — one icon per AccessoryCategory.
//   • Grid of accessory cards filtered to the selected category.
struct BitePalView: View {
    @StateObject private var vm = BitePalViewModel.shared
    @ObservedObject private var stats = HiveStatsManager.shared
    @State private var selectedCategory: AccessoryCategory = .hats

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                categoryTabs
                grid
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "FFE066"), Color(hex: "FFC93C")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("BitePal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("BitePal")
                    .font(.titleMedium)
                    .foregroundColor(.foreground)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                // Bee preview with equipped accessories overlaid.
                ZStack {
                    Image("BeeHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)

                    ForEach(vm.equippedIds, id: \.self) { id in
                        if let accessory = BeeAccessoryCatalog.item(id: id) {
                            AccessoryImage(accessory: accessory, size: 60)
                                .offset(equipOffset(for: accessory.category))
                        }
                    }
                }
                .frame(height: 220)

                Text("Caramel")
                    .font(.titleLarge)
                    .foregroundColor(.foreground)

                HStack(spacing: 6) {
                    ForEach(0..<4) { i in
                        Image(systemName: i < 1 ? "heart.fill" : "heart")
                            .foregroundColor(i < 1 ? .red : .red.opacity(0.4))
                    }
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(LinearGradient.honeyGradient)
                Text("\(stats.coinsBalance)")
                    .font(.labelMedium)
                    .foregroundColor(.foreground)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .padding(.trailing, 16)
            .padding(.top, 12)
        }
    }

    /// Rough positions for accessory overlays on the bee preview.
    /// Real artwork will need a registered anchor table — this is a
    /// fast approximation that puts hats up top, glasses on the face,
    /// shoes near the feet, etc.
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

    // MARK: Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(AccessoryCategory.allCases) { category in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.sfSymbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(
                                    selectedCategory == category ? .white : category.tint
                                )
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(
                                            selectedCategory == category
                                                ? category.tint
                                                : Color.white.opacity(0.85)
                                        )
                                )
                            Text(category.displayName)
                                .font(.labelSmall)
                                .foregroundColor(.foreground)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .padding(.horizontal, 12)
        )
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(BeeAccessoryCatalog.items(in: selectedCategory)) { accessory in
                BitePalAccessoryCard(accessory: accessory, vm: vm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .fill(Color.card)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }
}

#Preview {
    NavigationStack {
        BitePalView()
    }
}
