import SwiftUI

// MARK: - Design Tokens
enum DesignTokens {

    // MARK: Corner Radii
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 30
        static let full: CGFloat = 9999
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40
    }
}

// MARK: - Shadow Modifiers
extension View {
    /// Small shadow — subtle UI elements
    func shadowSm() -> some View {
        self.shadow(
            color: Color.black.opacity(0.08),
            radius: 4, x: 0, y: 2
        )
    }

    /// Medium shadow — cards
    func shadowMd() -> some View {
        self.shadow(
            color: Color.black.opacity(0.10),
            radius: 12, x: 0, y: 4
        )
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 2, x: 0, y: 1
        )
    }

    /// Large shadow — elevated / modals
    func shadowLg() -> some View {
        self.shadow(
            color: Color.black.opacity(0.14),
            radius: 24, x: 0, y: 10
        )
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 3, x: 0, y: 1
        )
    }

    /// Honey glow — CTAs, primary actions
    func shadowHoney() -> some View {
        self.shadow(
            color: Color.primaryColor.opacity(0.30),
            radius: 16, x: 0, y: 6
        )
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 4, x: 0, y: 2
        )
    }

    /// Deep shadow — nav bar, hero cards
    func shadowDeep() -> some View {
        self.shadow(
            color: Color.black.opacity(0.20),
            radius: 30, x: 0, y: 12
        )
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 6, x: 0, y: 3
        )
    }
}

// MARK: - Glass Surfaces
// Shared glass primitives used across Compress, Email, Settings, and Contacts.
// Previously duplicated per-view — consolidated so any polish adjustment is a
// one-file change.

enum GlassElevation {
    /// Floating card — subtle shadow, sits in a list (email rows, settings groups).
    case card
    /// Lifted panel — pronounced upward lift, for bottom sheets/hero panels
    /// (Compress bottom controls).
    case lifted
}

/// Solid premium card surface: opaque white-to-warm-off-white gradient,
/// soft sheen border, and an elevation-based drop shadow. Originally
/// layered `.ultraThinMaterial` for a translucent glass feel, but the
/// nav bar (white pill, sits at zIndex 1000 below scrolling content)
/// kept bleeding through the material and visually merging with the
/// cards. This is now solid: cards fully block whatever is behind them
/// so the nav bar always reads as its own layer.
///
/// Night vs day differs only in shadow strength — surface stays the
/// same warm-white in both modes. Day/night branch is via
/// `@Environment(\.colorScheme)`, which only flips on the charging tab
/// (ContentView forces `.light` on every other tab).
struct GlassPanel: View {
    let cornerRadius: CGFloat
    let elevation: GlassElevation
    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat, elevation: GlassElevation = .card) {
        self.cornerRadius = cornerRadius
        self.elevation = elevation
    }

    private var isNight: Bool { colorScheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Adaptive fill: `Color.card` is white in light env and a
        // slate dark in dark env. The previous hardcoded white kept
        // cards bright on dark canvases (Personal Hub / Quick Access
        // pages in dark mode), creating the high-contrast "broken"
        // look the user flagged. With this token, cards flip with
        // their parent's colorScheme — homepage at day stays white
        // (env=.light), night flips dark (env=.dark, coherent with
        // the night bg image), and Quick Access dark-mode pages get
        // a proper dark card.
        return shape.fill(Color.card)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.foreground.opacity(0.06),
                        Color.foreground.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .modifier(GlassShadow(elevation: elevation, isNight: isNight))
    }
}

private struct GlassShadow: ViewModifier {
    let elevation: GlassElevation
    let isNight: Bool

    func body(content: Content) -> some View {
        switch elevation {
        case .card:
            content.shadow(
                color: Color.black.opacity(isNight ? 0.32 : 0.06),
                radius: 14, y: 4
            )
        case .lifted:
            content
                .shadow(color: Color.black.opacity(isNight ? 0.40 : 0.10), radius: 28, x: 0, y: -10)
                .shadow(color: Color.black.opacity(isNight ? 0.20 : 0.05), radius: 4, x: 0, y: -1)
        }
    }
}

/// Premium pearl backdrop used by the Compress flow — clean neutral gradient
/// with a single faint gold halo for brand warmth. Replaces the earlier warm
/// cream look. Call as the root of a `ZStack`.
struct WarmGoldBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FAFAF7"), Color(hex: "EDECE7")],
                startPoint: .top,
                endPoint: .bottom
            )
            // Top-left subtle cool highlight — adds depth without warmth.
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -160, y: -300)
            // Bottom-right muted gold whisper — brand nod, deliberately faint.
            Circle()
                .fill(Color(hex: "CFAF5F").opacity(0.07))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: 160, y: 340)
            // Fine grain veil — keeps the surface from feeling flat / plastic.
            Color.black.opacity(0.015)
        }
        .ignoresSafeArea()
    }
}
