import SwiftUI

// MARK: - Streak Counter View
/// Premium streak counter card — Whoop-inspired with gold accents.
/// Shows current streak, best streak, clean score ring, and lifetime stats.
struct StreakCounterView: View {
    @ObservedObject private var stats = HiveStatsManager.shared

    @State private var ringProgress: CGFloat = 0
    @State private var appear = false

    private var scoreColor: Color {
        let s = stats.cleanScore
        if s >= 80 { return Color(hex: "34D399") }   // green
        if s >= 50 { return Color(hex: "FBBF24") }   // amber
        if s >= 25 { return Color(hex: "FB923C") }    // orange
        return Color(hex: "EF4444")                    // red
    }

    private var streakTier: StreakTier {
        StreakTier.from(stats.currentStreak)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section — streak number + ring
            HStack(spacing: DesignTokens.Spacing.xl) {
                streakDisplay
                Spacer()
                cleanScoreRing
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Spacing.lg)

            divider

            // Bottom section — stats row
            HStack(spacing: 0) {
                statCell(
                    value: "\(stats.bestStreak)",
                    label: "Best",
                    icon: "trophy.fill"
                )
                statDivider
                statCell(
                    value: "\(stats.lifetimeItemsCleaned)",
                    label: "Cleaned",
                    icon: "trash.fill"
                )
                statDivider
                statCell(
                    value: stats.formattedBytesSaved,
                    label: "Saved",
                    icon: "arrow.down.circle.fill"
                )
                statDivider
                statCell(
                    value: "\(stats.totalScansCompleted)",
                    label: "Scans",
                    icon: "magnifyingglass"
                )
            }
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(Color.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(LinearGradient.cardSheen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .strokeBorder(Color.border.opacity(0.5), lineWidth: 1)
                )
        )
        .shadowMd()
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                ringProgress = CGFloat(stats.cleanScore) / 100.0
                appear = true
            }
        }
        .onChange(of: stats.cleanScore) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                ringProgress = CGFloat(newValue) / 100.0
            }
        }
    }

    // MARK: - Streak Display (left side)

    private var streakDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(stats.currentStreak)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient.honeyGradient)
                    .contentTransition(.numericText())

                Text("day\(stats.currentStreak == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.foregroundSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: streakTier.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.honeyGradient)

                Text(stats.streakMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.foregroundSecondary)
            }

            // Streak tier dots
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < streakTier.filledDots
                              ? AnyShapeStyle(LinearGradient.honeyGradient)
                              : AnyShapeStyle(Color.surfaceMedium))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Clean Score Ring (right side)

    private var cleanScoreRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.surfaceMedium, lineWidth: 6)
                .frame(width: 72, height: 72)

            // Progress
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        colors: [scoreColor.opacity(0.6), scoreColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))

            // Score label
            VStack(spacing: 0) {
                Text("\(stats.cleanScore)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.foreground)
                    .contentTransition(.numericText())
                Text("score")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.foregroundSecondary)
            }
        }
    }

    // MARK: - Stats Row

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LinearGradient.honeyGradient)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.foregroundSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.border.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.border.opacity(0.4))
            .frame(width: 1, height: 32)
    }
}

// MARK: - Streak Badge (compact, for top bar)
//
// Multi-layer flame glyph (halo + body + white-hot core + drifting
// spark) on the FuturisticPillSurface. The user explicitly asked for
// "unreal" and "futuristic" — this version delivers that via three
// changes the previous version didn't have:
//   1. The flame is no longer a flat colored silhouette — it's a
//      stacked composition that emits light, has a hot core, and
//      throws a spark.
//   2. The pill itself uses a chrome-glass surface (top rim + inner
//      shadow + body gradient) instead of a flat fill, so it reads
//      as a physical object lit from above rather than a sticker.
//   3. A subtle ambient amber glow sits under the entire pill in
//      night mode — when the streak is active, the badge
//      "radiates."
struct StreakBadge: View {
    @ObservedObject private var stats = HiveStatsManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    private var isNight: Bool { theme.isNightMode }

    private var flameBodyGradient: LinearGradient {
        LinearGradient(
            colors: isNight
                ? [Color(hex: "FFE08A"), Color(hex: "F58B2E"), Color(hex: "C4521B")]
                : [Color(hex: "FFC04A"), Color(hex: "EE7B12"), Color(hex: "B25502")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var flameHaloColor: Color {
        isNight
            ? Color(hex: "F2A04A").opacity(0.85)
            : Color(hex: "F2A04A").opacity(0.45)
    }

    var body: some View {
        HStack(spacing: 7) {
            StreakFlameGlyph(
                size: 14,
                bodyGradient: flameBodyGradient,
                haloColor: flameHaloColor,
                showCore: true
            )

            Text("\(stats.currentStreak)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isNight ? Color(hex: "FFF6E0") : Color(hex: "0F0F10"))
                .contentTransition(.numericText())
                .monospacedDigit()
                .kerning(0.2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(FuturisticPillSurface(isNight: isNight))
        // Ambient amber under-glow — night mode only. Day mode's
        // bright canvas would just look smudged with a colored wash.
        .background(
            Capsule()
                .fill(Color(hex: "F2A04A"))
                .opacity(isNight ? 0.20 : 0)
                .blur(radius: 12)
                .scaleEffect(1.1)
        )
        .shadow(
            color: Color.black.opacity(isNight ? 0.40 : 0.10),
            radius: isNight ? 12 : 7,
            x: 0,
            y: isNight ? 5 : 2
        )
    }
}

#Preview {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        VStack(spacing: 20) {
            StreakCounterView()
            StreakBadge()
        }
    }
}
