import SwiftUI

// MARK: - Quick Access Card
//
// 2x2 entry grid: Photos / Videos / Emails / Compress. Header in the
// same gold gradient as SPACE TO CLEAN. Each tile is its own bordered
// white card — the user wants four distinctly outlined targets.
struct QuickAccessCard: View {
    let onPhotos: () -> Void
    let onVideos: () -> Void
    let onEmail: () -> Void
    let onCompress: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    // Solid espresso ink — gradients on small uppercase 11.5pt text
    // (which is what both dashboard headers are) tend to render as a
    // muddy wash on-device. A single dark color is unambiguously legible
    // and matches the Compress/More page titles for one type system.
    // Both QUICK ACCESS (here) and TOTAL SPACE TO CLEAN (HiveScoreCard)
    // reference this so the dashboard ink reads consistently.
    /// Adaptive header ink — espresso black in light, soft white in
    /// dark so the small uppercase 11.5pt label still reads cleanly
    /// against the dark glass surface in night mode.
    static let headerColor = Color(light: Color(hex: "1C1917"), dark: Color(hex: "F1F1F2"))
    static let headerGradient = LinearGradient(
        colors: [headerColor, headerColor],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BCLoc.quickAccess.tr)
                .font(.custom("Poppins-Bold", size: 11.5))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(QuickAccessCard.headerColor)
                .lineLimit(1)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    QuickAccessTile(icon: "photo.fill", title: "Photos", tint: .categorySky, action: onPhotos)
                    QuickAccessTile(icon: "play.rectangle.fill", title: "Videos", tint: .categoryRose, action: onVideos)
                }
                HStack(spacing: 8) {
                    QuickAccessTile(icon: "envelope.fill", title: "Emails", tint: .categoryMint, action: onEmail)
                    QuickAccessTile(icon: "arrow.down.forward.and.arrow.up.backward", title: "Compress", tint: .categoryViolet, action: onCompress)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .stroke(cardBorder, lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 18, x: 0, y: 8)
    }

    /// Card surface fill — pure white in light mode so the card
    /// matches the bright-white "Space to Clean" card above it. The
    /// previous white→#F2F3F5 wash read as a dingy gray gradient
    /// next to a true-white sibling.
    private var cardFill: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color(hex: "1B1C21"), Color(hex: "131418")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Color.white, Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Hairline border — neutral monochrome (was a warm gold gradient
    /// that fought the bright-white surface). Top is near-white, bottom
    /// fades to a soft mid-gray.
    private var cardBorder: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                Color.white.opacity(0.5),
                Color.black.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Quick Access Tile
private struct QuickAccessTile: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Manual press-state flag — driven by a tap gesture below so the
    /// dim + scale animation is GUARANTEED visible even on micro-quick
    /// taps. With a vanilla Button the press visual was vanishing
    /// before the eye could catch it (action fires + navigation starts
    /// in the same frame).
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // Two-beat "press → go" haptic — soft initial touch
            // followed 28ms later by a snappier confirmation. Reads as
            // one decisive tap with commitment, distinct from the
            // nav-bar's single switch-click tick.
            HapticManager.shared.quickAccessCommit()

            // Pin the press visual ON for ~140ms so the user sees the
            // tile darken + shrink even on the quickest tap, THEN fire
            // the actual navigation action. Without this the
            // navigation transition would start in the same frame as
            // the press release and the user never sees the press.
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    isPressed = false
                }
                action()
            }
        }) {
            HStack(spacing: 8) {
                QuickAccessIcon(icon: icon, tint: tint)

                Text(title)
                    // Uniform 13pt across all 4 tiles — fits "Compress"
                    // at full size with no `minimumScaleFactor` shrink.
                    // Photos / Videos / Emails / Compress all render at
                    // the exact same character height.
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundStyle(Color.foreground)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                SleekArrowChip(tint: tint, size: 18)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tileBackground)
            .overlay(tileTopHighlight)
            .overlay(tileOutline)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            // Manual press-state visual driven by `isPressed` —
            // unmissable dark overlay + scale compression that's
            // pinned ON for ~140ms (see action above) regardless of
            // how fast the user releases.
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(isPressed ? 0.22 : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(isPressed ? 0.93 : 1)
            .brightness(isPressed ? -0.06 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // Tile surface — pure white in light mode. The previous 3-layer
    // recipe (category tint + white wash + specular sheen + diagonal
    // band) baked a faint colored gradient into every tile that read
    // as "weird wash" against the bright-white parent card. Color
    // identity now lives ONLY on the per-tile icon + arrow chip; the
    // tile body itself is neutral white so the row reads cleanly
    // against the parent.
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if colorScheme == .dark {
            return AnyView(shape.fill(Color(hex: "1F2026").opacity(0.85)))
        }
        return AnyView(shape.fill(Color.white))
    }

    // Crisp top rim-light — same lit-from-above stroke signature the FAB
    // and strip pill use. Ties Quick Access into one lighting model with
    // the rest of the nav surfaces.
    private var tileTopHighlight: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.6
            )
            .blendMode(.plusLighter)
    }

    private var tileOutline: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.10),
                lineWidth: 1
            )
    }
}

// MARK: - Quick Access Icon
//
// Tinted-square treatment — same BitePal pattern the More page's
// Contacts / Secret Space cards use: a light tint of the category's
// color as the container, with the icon in the darker saturated tone.
// Each Quick Access tile gets its own category color so the four
// surfaces read as distinct destinations at a glance.
//
// Extracted from QuickAccessTile to keep Swift's type-checker happy —
// the inline ZStack with gradient + 3 overlays + shadow was timing
// out type inference inside the parent view chain.
private struct QuickAccessIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconFill)
                .overlay(iconHairline)
                .frame(width: 34, height: 34)
                .shadow(color: tint.opacity(0.18), radius: 5, x: 0, y: 2)

            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var iconFill: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.20), tint.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconHairline: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(tint.opacity(0.20), lineWidth: 0.5)
    }
}

// MARK: - Press Style
//
// More visible press state so the user gets unambiguous "tap
// acknowledged" feedback before the navigation transition kicks in.
// Combined scale + brightness dim + dark overlay reads on the first
// frame of contact.
private struct QuickAccessTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Stronger press state — the tap must register
            // unambiguously before the navigation transition starts.
            .brightness(configuration.isPressed ? -0.12 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                .spring(response: 0.20, dampingFraction: 0.68),
                value: configuration.isPressed
            )
    }
}

#Preview {
    ZStack {
        Color(hex: "3A6B3A").ignoresSafeArea()
        QuickAccessCard(
            onPhotos: {},
            onVideos: {},
            onEmail: {},
            onCompress: {}
        )
        .padding(16)
    }
}

// Compatibility alias — the QuickAccessIcon initializer changed from
// `(icon:)` to `(icon:tint:)`. Anything that previously instantiated
// the icon without a tint should now pass a tint explicitly.

