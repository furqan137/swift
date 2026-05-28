import SwiftUI

// MARK: - Adaptive Color Helper
extension Color {
    /// Creates an adaptive color that switches between light and dark mode values.
    init(light lightColor: Color, dark darkColor: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(darkColor)
                : UIColor(lightColor)
        })
    }
}

// MARK: - Color Theme (Adaptive)
extension Color {
    // Base — dark palette retuned to feel premium / intentional.
    // Previous values (#161618 bg, #1F1F22 card) only had ~3 luminance
    // points of separation, so cards blended into the background. New
    // ramp:  bg #0B0B0E (true dark)  →  card #18181B (clearly lifted)
    // →  surfaceLight #1F1F23  →  surfaceMedium #26262B. Matches the
    // ramp Linear / Cal AI / Notion use for their dark UIs.
    static let background = Color(light: Color(hex: "FAFAFA"), dark: Color(hex: "0B0B0E"))
    /// Muted honey ground — sampled from hero image, desaturated for a premium feel
    static let honeyCanvas = Color(hue: 0.11, saturation: 0.55, brightness: 0.92)
    static let foreground = Color(light: Color(hex: "1C1917"), dark: Color(hex: "FAFAFA"))
    static let foregroundSecondary = Color(light: Color(hex: "57534E"), dark: Color(hex: "A1A1AA"))

    // Surfaces
    static let card = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "18181B"))
    static let surfaceLight = Color(light: Color(hex: "F5F1EC"), dark: Color(hex: "1F1F23"))
    static let surfaceMedium = Color(light: Color(hex: "EDE8E2"), dark: Color(hex: "26262B"))
    static let surfaceDark = Color(light: Color(hex: "E7E1DA"), dark: Color(hex: "303035"))

    // Primary & Secondary
    static let primaryColor = Color(hex: "1C1917")     // neutral black
    static let primaryLight = Color(light: Color(hex: "D4940A"), dark: Color(hex: "EDAE1A"))
    static let secondaryColor = Color(hex: "2D9B8A")   // jewel teal

    // Muted
    static let muted = Color(light: Color(hex: "F2EDE8"), dark: Color(hex: "1F1F23"))
    static let mutedForeground = Color(light: Color(hex: "8A837C"), dark: Color(hex: "8E8E93"))

    // Border & Input — subtler in dark, just a hairline lift not a hard line.
    static let border = Color(light: Color(hex: "E7E1DA"), dark: Color(hex: "27272A"))
    static let input = Color(light: Color(hex: "E7E1DA"), dark: Color(hex: "27272A"))
    static let ring = Color(hex: "C4850A")

    // Status
    static let destructive = Color(light: Color(hex: "DC2626"), dark: Color(hex: "EF4444"))
    static let success = Color(light: Color(hex: "16A34A"), dark: Color(hex: "34D399"))
    static let warning = Color(light: Color(hex: "D97706"), dark: Color(hex: "FBBF24"))

    // Navigation
    static let navBackground = Color(light: Color(hex: "FBF9F6"), dark: Color(hex: "0E0E11"))
    static let navForeground = Color(light: Color(hex: "78716C"), dark: Color(hex: "A1A1AA"))
    static let navActive = Color(hex: "C4850A")

    // Category colors (adaptive).
    //
    // Two non-overlapping palettes so the Photos tab and Videos tab feel
    // distinct even on the same scroll. The PHOTO palette is the warm/cool
    // mix the design started with (sky/violet/teal/amber/rose). The VIDEO
    // palette intentionally picks hues that DON'T appear in photos —
    // crimson is deeper and more saturated than rose; cocoa is brown
    // not orange; mint is green not cyan-green-blue; indigo is deep
    // blue-purple not cyan-blue. Plus `categorySlate` for "Other Photos"
    // so it stops overlapping with Duplicates' sky.
    static let categoryHoney = Color(light: Color(hex: "D4940A"), dark: Color(hex: "EDAE1A"))
    static let categoryTeal = Color(light: Color(hex: "4A9E8E"), dark: Color(hex: "4DC4AD"))
    static let categoryAmber = Color(light: Color(hex: "B45309"), dark: Color(hex: "F59E0B"))
    static let categoryRose = Color(light: Color(hex: "BE123C"), dark: Color(hex: "FB7185"))
    static let categoryViolet = Color(light: Color(hex: "7C3AED"), dark: Color(hex: "A78BFA"))
    static let categorySky = Color(light: Color(hex: "0284C7"), dark: Color(hex: "38BDF8"))

    // Other Photos — neutral slate, distinct from Duplicates' sky.
    static let categorySlate = Color(light: Color(hex: "475569"), dark: Color(hex: "94A3B8"))

    // Video-only palette — picked to NOT collide with any photo color.
    static let categoryCrimson = Color(light: Color(hex: "9F1239"), dark: Color(hex: "F43F5E")) // deep red, distinct from rose's pink
    static let categoryCocoa   = Color(light: Color(hex: "7C2D12"), dark: Color(hex: "C2410C")) // warm brown, distinct from amber's orange
    static let categoryMint    = Color(light: Color(hex: "047857"), dark: Color(hex: "10B981")) // fresh green, distinct from teal's cyan-green
    static let categoryIndigo  = Color(light: Color(hex: "4338CA"), dark: Color(hex: "818CF8")) // deep blue-purple, distinct from sky/violet

    // Legacy aliases (keep old call-sites compiling)
    static let primaryForeground = Color(hex: "FFFFFF")
    static let secondaryForeground = Color.foreground
    static let destructiveForeground = Color(hex: "FFFFFF")
    static let accentColor = Color(hex: "C4850A")
    static let accentForeground = Color(hex: "FFFFFF")
    static let cardForeground = Color.foreground

    // Legacy category aliases
    static let categoryRed = Color.categoryRose
    static let categoryBlue = Color.categorySky
    static let categoryGreen = Color.categoryTeal
    static let categoryYellow = Color.categoryHoney
    static let categoryPurple = Color.categoryViolet
    static let categoryCyan = Color.categoryTeal
    static let categoryPink = Color.categoryRose
    static let categoryOrange = Color.categoryAmber
}

// MARK: - Hex Color Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Gradient Definitions
extension LinearGradient {
    /// Honey gold gradient — primary CTA, progress rings, accents
    static let honeyGradient = LinearGradient(
        colors: [Color(hex: "A87408"), Color(hex: "D4A01C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Softer honey gradient — buttons, less saturated
    static let honeySoft = LinearGradient(
        colors: [Color(hex: "B07D09"), Color(hex: "C89212")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Warm glow — ambient backgrounds
    static let warmGlow = LinearGradient(
        colors: [Color(hex: "A87408"), Color(hex: "2D9B8A")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card gradient (adaptive via opacity)
    static let cardGradient = LinearGradient(
        colors: [Color.card, Color.card.opacity(0.85)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Glass highlight overlay
    static let glassGradient = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Deep honey — hero ring, special moments (3-stop)
    static let honeyDeep = LinearGradient(
        colors: [Color(hex: "8B6508"), Color(hex: "C4850A"), Color(hex: "D4A01C")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card sheen — lit-from-above highlight
    static let cardSheen = LinearGradient(
        colors: [Color.white.opacity(0.06), Color.clear, Color.white.opacity(0.02)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Legacy alias
    static let primaryGradient = honeyGradient
    static let premiumGlow = warmGlow
}
