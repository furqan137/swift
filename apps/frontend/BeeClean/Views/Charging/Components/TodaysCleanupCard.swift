import SwiftUI

// MARK: - Today's Cleanup Card
/// Gamified cleanup mission panel replacing the old HiveScoreCard.
/// Hierarchy: big storage value → Clean Bar progression → status text → tasks → CTA.
struct TodaysCleanupCard: View {
    let plan: TodayCleanupPlan
    let stage: BeeStage
    let potentialCoins: Int
    /// Persisted active task (Shuffling System). Drives the numbered label.
    var activeTask: ActiveCleanupTask? = nil
    /// Up to 2 most-recent completed tasks (newest first) for the greyed stack.
    var recentCompleted: [CompletedCleanupTask] = []
    let onStartCleanup: () -> Void
    var onViewAll: () -> Void = {}

    @ObservedObject private var statsManager = HiveStatsManager.shared
    @ObservedObject private var progress = ProgressManager.shared
    @ObservedObject private var libraryBytes = PhotoLibraryBytesService.shared
    @State private var animatedScore: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1
    @State private var appeared = false
    @State private var topDestination: CardTopDestination?

    enum CardTopDestination: Hashable {
        case shop, leaderboard, coins
    }

    /// The "Space to Clean" headline. Defaults to our scan-derived
    /// clutter bytes, but we ceiling on Apple Photos' library total —
    /// because the user has called us out for showing 45.8 GB when
    /// Photos shows 50.67 GB. Until our scan covers every asset class
    /// Photos counts (Live Photos, RAW, edited originals), surfacing
    /// the Apple-equivalent total as the headline keeps us honest.
    /// When our scan eventually equals or exceeds Photos' number,
    /// `formattedHeadlineBytes` becomes a pure pass-through.
    private var formattedHeadlineBytes: String {
        let scan = plan.totalRecoverableBytes
        let library = libraryBytes.totalLibraryBytes
        guard library > scan else { return plan.formattedTotalBytes }
        return Self.formatBytes(library)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var isEmpty: Bool { plan.tasks.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Big headline value (primary)
            headlineSection
                .padding(.bottom, 14)

            // 2. Clean Bar progression (prominent, emotionally rewarding)
            cleanBarSection
                .padding(.bottom, isEmpty ? 0 : 16)

            // 4. Today's tasks
            if !isEmpty {
                taskListSection
                    .padding(.bottom, 18)

                // 5. CTA button
                ctaButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, isEmpty ? 20 : 18)
        .frame(maxWidth: .infinity)
        .background(cardSurface)
        .shadow(
            color: stage.isUnclean
                ? Color.destructive.opacity(0.15)
                : Color(hex: "C4850A").opacity(0.10),
            radius: 18, x: 0, y: 8
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).delay(0.25)) {
                animatedScore = CGFloat(progress.cleanBarPercent)
            }
            withAnimation(
                .linear(duration: 2.0)
                .delay(0.8)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 2
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .onChange(of: progress.cleanBarPercent) { _, newValue in
            withAnimation(.easeOut(duration: 0.8)) {
                animatedScore = CGFloat(newValue)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: stage)
    }

    // MARK: - Headline Section

    private var headlineSection: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BCLoc.totalSpaceToClean.tr)
                    .font(.custom("Poppins-Bold", size: 11.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Color(hex: "1C1917"))
                    .lineLimit(1)

                Text(formattedHeadlineBytes)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(Color.foreground)
                    .tracking(-1.0)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            cardTopActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        // Shop opens as a bottom sheet (BitePal-style: it overtakes the
        // lower half of the dashboard and the grip-handle drag drops
        // back to the homepage). Leaderboard + Coins still push as
        // regular destinations.
        .sheet(isPresented: Binding(
            get: { topDestination == .shop },
            set: { if !$0 { topDestination = nil } }
        )) {
            // Sheet top edge lands exactly where the Total Space to
            // Clean card starts. The bee hero takes ~50% of screen
            // height, so a 0.50 detent puts the sheet's top edge
            // right at the card's top edge — the store visually
            // "replaces" the lower stack (TSC + Quick Access + Source
            // row) without covering the bee. Drag up to expand to
            // full screen, drag down to dismiss.
            // Sheet top edge sits AT the Total Space to Clean card's
            // top edge — covers the card + Quick Access row + Source
            // row in one sweep, matching BitePal's "store takes over
            // the lower half of the home" pattern.
            BitePalView()
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .navigationDestination(item: Binding(
            get: { topDestination != .shop ? topDestination : nil },
            set: { if $0 == nil && topDestination != .shop { topDestination = nil } }
        )) { dest in
            switch dest {
            case .shop:        EmptyView()
            case .leaderboard: LeaderboardView().hidesBottomNavBar()
            case .coins:       CoinsView().hidesBottomNavBar()
            }
        }
    }

    // MARK: - Card Top Actions
    //
    // Sleek icon strip in the top-right of the Total Space to Clean card.
    // Sits on the white card surface so the dark monochrome glyphs read
    // clearly (the screen-header version was getting drowned by the
    // night sky). Anchored to the card means the icons scroll WITH the
    // card content — they're a card affordance, not screen chrome.
    private var cardTopActions: some View {
        HStack(spacing: 6) {
            cardIconButton(systemName: "storefront") {
                topDestination = .shop
            }
            cardIconButton(systemName: "trophy.fill") {
                topDestination = .leaderboard
            }
            Button {
                topDestination = .coins
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LinearGradient.honeyGradient)
                    Text("\(statsManager.coinsBalance)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "1C1917"))
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Capsule().fill(Color(hex: "F5F1EC")))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func cardIconButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        // Sleek glyph chip: 28pt soft white circle with a hairline
        // border + featherweight shadow. Thin SF Symbol weight (.regular)
        // and `symbolRenderingMode(.monochrome)` so the glyph reads as
        // a sharp etched mark, not a chunky filled badge.
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(Color(hex: "1C1917"))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
                )
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clean Bar Section

    private var cleanBarSection: some View {
        VStack(spacing: 7) {
            // Label row
            HStack(alignment: .firstTextBaseline) {
                Text("Clean Bar · Lv \(progress.currentLevel)")
                    .font(.custom("Poppins-Bold", size: 12.5))
                    .foregroundColor(Color.foreground.opacity(0.72))
                    .tracking(0.4)

                Spacer()

                Text("\(progress.currentLevelCoins)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(scoreColor)
                +
                Text(" / \(progress.coinsNeededForNextLevel) coins")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.mutedForeground.opacity(0.55))
            }

            // Progress pill — taller, glowing, game-like
            GeometryReader { geo in
                let fillWidth = geo.size.width * min(max(animatedScore, 0.02), 1.0)

                ZStack(alignment: .leading) {
                    // Track — subtle warm tint
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "EDE8E2").opacity(0.7),
                                    Color(hex: "E7E1DA").opacity(0.5)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    // Fill — flat solid color matching CTA button
                    Capsule()
                        .fill(scoreGradient)
                        .frame(width: fillWidth)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
    }

    // MARK: - Status Subtitle

    private var statusSubtitle: some View {
        Text(plan.subtitle)
            .font(.custom("Poppins-Medium", size: 12.5))
            .foregroundColor(Color.mutedForeground.opacity(0.65))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 4)
    }

    // MARK: - Task List Section

    /// Capped task stack: up to 2 greyed-out recently-completed tasks above the
    /// full-color active task (max 3 rows total). Plus a "View All" entry to the
    /// full history. Labels are the numbered "Task #X" progression.
    private var taskListSection: some View {
        VStack(spacing: 8) {
            // Header + View All
            HStack {
                Text("Cleanup Tasks")
                    .font(.custom("Poppins-Bold", size: 12.5))
                    .foregroundColor(Color.foreground.opacity(0.72))
                    .tracking(0.4)
                Spacer()
                Button(action: { HapticManager.shared.impact(.light); onViewAll() }) {
                    HStack(spacing: 2) {
                        Text("View All")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "C4850A"))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                // Greyed completed cards — oldest on top, newest just above active.
                let completed = Array(recentCompleted.prefix(2).reversed())
                ForEach(Array(completed.enumerated()), id: \.element.taskNumber) { _, t in
                    stackRow(
                        title: t.displayTitle,
                        bytesText: Self.mbText(t.mbReviewed),
                        coins: t.coinsEarned,
                        category: Self.category(from: t.category),
                        greyed: true
                    )
                    stackDivider
                }

                // Active task — full color, the one the CTA launches.
                stackRow(
                    title: activeTask?.displayTitle ?? BCLoc.quickCleanup.tr,
                    bytesText: plan.formattedRoundBytes,
                    coins: potentialCoins,
                    category: Self.category(from: activeTask?.category),
                    greyed: false
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(Color(hex: "F8F6F2"))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
            )
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 4)
    }

    private var stackDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 34)
    }

    private func stackRow(title: String, bytesText: String, coins: Int, category: CleanupTaskCategory, greyed: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(greyed ? Color(hex: "E7E1DA") : Color(hex: "FFC648"))
                    .frame(width: 24, height: 24)
                Image(systemName: greyed ? "checkmark" : "flag.fill")
                    .font(.system(size: greyed ? 11 : 12, weight: .semibold))
                    .foregroundColor(greyed ? Color.mutedForeground : .black)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundColor(Color.foreground)
                .lineLimit(1)

            Text(bytesText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color.mutedForeground)

            Spacer(minLength: 4)

            if coins > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "centsign.circle.fill")
                    Text("+\(coins)")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "C4850A"))
            }
        }
        .padding(.vertical, 10)
        .opacity(greyed ? 0.5 : 1.0)
    }

    static func mbText(_ mb: Double) -> String {
        CleanupRound.formatBytes(Int64(mb * 1_000_000))
    }

    static func category(from raw: String?) -> CleanupTaskCategory {
        CleanupTaskCategory(rawValue: raw ?? "") ?? .otherPhotos
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button(action: {
            HapticManager.shared.primaryCommit()
            onStartCleanup()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))

                Text("Start Quick Cleanup")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(-0.2)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(ctaBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.75)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
    }

    private var ctaBackground: some View {
        Color(hex: "FFC648")
    }

    // MARK: - Card Surface

    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
        return ZStack {
            shape.fill(Color.card)
            shape.stroke(borderGradient, lineWidth: 0.9)
        }
        .compositingGroup()
    }

    private var borderGradient: LinearGradient {
        if stage.isUnclean {
            return LinearGradient(
                colors: [
                    Color.destructive.opacity(0.30),
                    Color.destructive.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color(hex: "CFAF5F").opacity(0.28),
                Color(hex: "7A5C2E").opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Colors

    private var scoreColor: Color {
        Color.foreground
    }

    private var scoreGradient: some ShapeStyle {
        Color(hex: "FFC648")
    }

    private func iconColor(for category: CleanupTaskCategory) -> Color {
        switch category {
        case .duplicatePhotos: return .categorySky
        case .similarPhotos: return .categoryViolet
        case .similarScreenshots: return .categoryTeal
        case .screenshots: return .categoryAmber
        case .blurryPhotos: return .categoryRose
        case .similarVideos: return .categoryCrimson
        case .screenRecordings: return .categoryIndigo
        case .shortRecordings: return .categoryMint
        case .longVideos: return .categoryCocoa
        case .otherPhotos: return .categorySlate
        case .promoEmails: return .categorySlate
        }
    }
}

#Preview {
    let fullPlan = TodayCleanupPlan(
        totalRecoverableBytes: 2_400_000_000,
        roundBytes: 1_200_000_000,
        tasks: [
            CleanupTask(id: "1", icon: "doc.on.doc.fill", title: "5 duplicate screenshots", estimatedBytes: 450_000_000, category: .duplicatePhotos),
            CleanupTask(id: "2", icon: "film.fill", title: "1 large video", estimatedBytes: 380_000_000, category: .longVideos),
            CleanupTask(id: "3", icon: "camera.metering.unknown", title: "3 blurry photos", estimatedBytes: 220_000_000, category: .blurryPhotos),
            CleanupTask(id: "4", icon: "rectangle.on.rectangle", title: "4 similar screenshots", estimatedBytes: 150_000_000, category: .similarScreenshots),
        ],
        estimatedSeconds: 45,
        beeHealthScore: 58,
        subtitle: "Bee found a quick cleanup for you"
    )

    let scanningPlan = TodayCleanupPlan(
        totalRecoverableBytes: 0,
        roundBytes: 0,
        tasks: [],
        estimatedSeconds: 0,
        beeHealthScore: 12,
        subtitle: "Scanning for cleanup tasks..."
    )

    ScrollView {
        VStack(spacing: 24) {
            TodaysCleanupCard(plan: fullPlan, stage: .stage3, potentialCoins: 8) {}
            TodaysCleanupCard(plan: fullPlan, stage: .stage1, potentialCoins: 8) {}
            TodaysCleanupCard(plan: scanningPlan, stage: .stage2, potentialCoins: 0) {}
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 40)
    }
    .background(Color.background)
}
