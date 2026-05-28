import SwiftUI

// MARK: - Home View
struct HomeView: View {
    @Environment(SimilarPhotosStore.self) private var similarVM
    @StateObject private var theme = ThemeService.shared
    @ObservedObject private var beeVM = BeeViewModel.shared
    @State private var showScanningOverlay = false
    @State private var selectedCategory: MediaCategory? = nil
    @State private var categories: [MediaCategory] = []
    @State private var topDestination: TopDestination? = nil

    enum TopDestination: Hashable {
        case shop, leaderboard, coins
    }

    // MARK: - Layout Constants
    private let hPad: CGFloat = 24
    private let sectionGap: CGFloat = 6
    private let cardGap: CGFloat = 6
    /// How far the card tucks under the bee (positive = overlap)
    private let beeCardOverlap: CGFloat = 0
    /// How far the content tucks under the hive card (positive = overlap)
    private let contentOverlap: CGFloat = 60

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let screenW = geo.size.width
                let screenH = geo.size.height
                let safeTop = geo.safeAreaInsets.top
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Bee Hero Mascot ──────────────────────
                        HeroMascot(screenWidth: screenW, screenHeight: screenH, safeAreaTop: safeTop)
                            .zIndex(1)

                        // ── Hive Status Card (overlaps under bee) ──
                        HiveScoreCard(
                            stage: beeVM.stage,
                            clutterBytes: similarVM.totalClutterBytes
                        )
                        .padding(.top, -beeCardOverlap)
                        .zIndex(1)

                        // ── Content ──────────────────────────────
                        VStack(spacing: sectionGap) {

                            // Scan button
                            PrimaryButton(
                                similarVM.isScanning ? "Scanning…" : "Scan for Duplicates",
                                iconName: "magnifyingglass"
                            ) {
                                showScanningOverlay = true
                                Task { await similarVM.runFullScan(force: true) }
                            }
                            .disabled(similarVM.isScanning)

                            // Results text
                            if similarVM.groupCount > 0 && !similarVM.isScanning {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.success)
                                    Text("Found \(similarVM.totalSelectedForDelete) similar photos to clean")
                                        .font(.bodyMedium)
                                        .foregroundColor(.mutedForeground)
                                }
                                .transition(.slideUpFade)
                            }

                            // Categories
                            categoriesSection

                            // Compress shortcut
                            compressShortcut
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeTopBar(
                    onShop:        { topDestination = .shop },
                    onLeaderboard: { topDestination = .leaderboard },
                    onCoins:       { topDestination = .coins }
                )
            }
            .background {
                ZStack {
                    // Day → bee_bg_structured, Night → bee_bg_night.
                    // Driven by the same ThemeService that flips the
                    // .preferredColorScheme below: 06:00 local → day,
                    // 18:00 local → night.
                    // Anchor to .top so any vertical crop happens at the
                    // bottom of the asset (an endless green field with no
                    // detail) rather than clipping the sky — both night
                    // clouds sit in the upper-left/upper-right and would
                    // otherwise get sliced by `.scaledToFill`'s default
                    // center-crop on screens where aspect ratios diverge
                    // from the asset by even a few pixels.
                    Image(theme.scheduleMode == .dark ? "bee_bg_night" : "bee_bg_structured")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .ignoresSafeArea()
                        .id(theme.scheduleMode)            // force redraw on flip
                        .transition(.opacity)              // soft cross-fade

                    // Subtle vignette — slightly heavier at night for depth
                    LinearGradient(
                        colors: theme.scheduleMode == .dark
                            ? [
                                Color.black.opacity(0.25),
                                Color.clear,
                                Color.black.opacity(0.35)
                              ]
                            : [
                                Color.black.opacity(0.12),
                                Color.clear,
                                Color.black.opacity(0.08)
                              ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
                .animation(.easeInOut(duration: 0.6), value: theme.scheduleMode)
            }
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(category: category)
            }
            .navigationDestination(item: $topDestination) { destination in
                switch destination {
                case .shop:        BitePalView()
                case .leaderboard: LeaderboardView()
                case .coins:       CoinsView()
                }
            }
        }
        .overlay {
            if showScanningOverlay && similarVM.isScanning {
                ScanningOverlay(isPresented: $showScanningOverlay) {}
                    .transition(.opacity)
            }
        }
        .task { await similarVM.loadFromCache() }
        .onChange(of: similarVM.isScanning) { _, scanning in
            if !scanning { withAnimation { showScanningOverlay = false } }
        }
        // Local env override — we deliberately do NOT call
        // `.preferredColorScheme` here. That modifier propagates to the
        // scene and gets resolved at the WINDOW root, so an outer modifier
        // (BeeCleanApp's `themeService.mode`) wins regardless. The env
        // override flows DOWN to HomeView's subtree only, so the homepage
        // stays locked to the schedule even when the user picks Light or
        // Dark in Settings. The user's pick still drives every other
        // surface via the window scheme.
        .environment(\.colorScheme, theme.scheduleMode)
    }

    // MARK: - Categories Section
    //
    // The legacy Media Categories grid was driven by `@State categories: [MediaCategory]`
    // that was never populated from anywhere — so on the rendered Home it
    // showed up as a "Media Categories" header sitting above an empty grid:
    // the literal graybox the user complained about. Render the section only
    // when there's actually data to show; the real cleanup entry-points live
    // on ChargingView's IntelligentPreviewCards.
    @ViewBuilder
    private var categoriesSection: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Media Categories")
                    .font(.titleMedium)
                    .foregroundColor(.foreground)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: cardGap),
                        GridItem(.flexible(), spacing: cardGap)
                    ],
                    spacing: cardGap
                ) {
                    // Index-based — `categories` is a stable ordered list of
                    // 6–8 enum cases, so identity-by-index is safe and skips
                    // the per-render `[(Int, MediaCategory)]` allocation.
                    ForEach(categories.indices, id: \.self) { index in
                        let category = categories[index]
                        StaggeredAnimation(index: index) {
                            CategoryCard(category: category) {
                                selectedCategory = category
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compress Shortcut
    private var compressShortcut: some View {
        NavigationLink {
            CompressView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primaryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Compress Files")
                        .font(.labelLarge)
                        .foregroundColor(.foreground)
                    Text("Save up to 2.5 GB")
                        .font(.bodySmall)
                        .foregroundColor(.mutedForeground)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(DesignTokens.Spacing.lg)
            .cardSurface(.elevated)
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
