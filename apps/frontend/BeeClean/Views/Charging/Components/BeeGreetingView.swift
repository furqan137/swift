import SwiftUI

// MARK: - Bee Greeting View
/// Premium hero section: warm gradient background, transparent bee mascot
/// standing on a soft floor ellipse, greeting text + settings gear.
/// At night the warm gradient swaps for a deep navy sky with a moon + stars.
struct BeeGreetingView: View {
    @AppStorage("userName") private var beeName = ""
    @ObservedObject private var theme = ThemeManager.shared

    let heroHeight: CGFloat
    let safeAreaTop: CGFloat
    let progress: Double
    let isAnimating: Bool

    private var displayBeeName: String {
        let trimmedName = beeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "BeeBuddy" : trimmedName
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Day overlay (warm white wash) — only in day. In night mode the
            // bee_bg_night asset already provides the entire sky/atmosphere,
            // so we paint nothing here on top of it.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.15),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
            .opacity(theme.isNightMode ? 0 : 1)

            VStack {
                Spacer(minLength: 0)

                BeeProgressAnimationView(
                    progress: progress,
                    isAnimating: isAnimating
                )
                .frame(height: heroHeight)
                .scaleEffect(2)
                .offset(y: 64)
                .background(alignment: .bottom) {
                    BeeGroundShadow(
                        heroHeight: heroHeight,
                        progress: progress
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(x: 4, y: -12)
                }
            }
            .frame(height: heroHeight)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                // Name is rendered by NameEditOverlay in ChargingView
                // (above ScrollView so it's tappable). Reserve space here.
                Text(displayBeeName)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.clear)
                    .padding(.vertical, 6)
                    .padding(.trailing, 16)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, safeAreaTop + DesignTokens.Spacing.sm)
            .allowsHitTesting(false)

        }
        .frame(height: heroHeight)
    }

}

// Stage 1 — Sad bee (>=3% clutter, progress < 0.97)
#Preview("Stage 1 — Needs Cleaning") {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ScrollView {
            BeeGreetingView(heroHeight: 420, safeAreaTop: 59, progress: 0.50, isAnimating: true)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// Stage 2 — Slightly better (1-3% clutter, progress 0.97-0.99)
#Preview("Stage 2 — Getting Started") {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ScrollView {
            BeeGreetingView(heroHeight: 420, safeAreaTop: 59, progress: 0.98, isAnimating: true)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// Stage 3 — Making progress (0.4-1% clutter, progress 0.99-0.996)
#Preview("Stage 3 — Looking Better") {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ScrollView {
            BeeGreetingView(heroHeight: 420, safeAreaTop: 59, progress: 0.993, isAnimating: true)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// Stage 4 — Almost there (0.1-0.4% clutter, progress 0.996-0.999)
#Preview("Stage 4 — Almost There") {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ScrollView {
            BeeGreetingView(heroHeight: 420, safeAreaTop: 59, progress: 0.997, isAnimating: true)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// Stage 5 — Clean phone (<0.1% clutter, progress >= 0.999)
#Preview("Stage 5 — All Clean") {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ScrollView {
            BeeGreetingView(heroHeight: 420, safeAreaTop: 59, progress: 1.0, isAnimating: true)
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct BeeGroundShadow: View {
    let heroHeight: CGFloat
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var baseWidth: CGFloat {
        heroHeight * 0.2
    }

    var body: some View {
        Ellipse()
            .fill(Color.black.opacity(0.5))
            .frame(width: baseWidth, height: 24)
    }
}
