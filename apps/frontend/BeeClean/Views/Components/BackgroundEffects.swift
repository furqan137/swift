import SwiftUI

// MARK: - Grid Pattern View
struct GridPatternView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let gridSize: CGFloat = 40
                let lineWidth: CGFloat = 0.25
                let color = Color.foreground.opacity(colorScheme == .dark ? 0.035 : 0.02)

                for x in stride(from: 0, through: size.width, by: gridSize) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(color), lineWidth: lineWidth)
                }

                for y in stride(from: 0, through: size.height, by: gridSize) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(color), lineWidth: lineWidth)
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - Ambient Glow View
struct AmbientGlowView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Primary honey glow — top center, warm candlelight
            RadialGradient(
                colors: [
                    Color(hex: "C4850A").opacity(colorScheme == .dark ? 0.12 : 0.03),
                    Color(hex: "D4A01C").opacity(colorScheme == .dark ? 0.04 : 0.01),
                    Color.clear
                ],
                center: UnitPoint(x: 0.45, y: 0.0),
                startRadius: 0,
                endRadius: 500
            )

            // Secondary teal accent — bottom right
            RadialGradient(
                colors: [
                    Color(hex: "2D9B8A").opacity(colorScheme == .dark ? 0.06 : 0.012),
                    Color.clear
                ],
                center: UnitPoint(x: 0.85, y: 0.9),
                startRadius: 0,
                endRadius: 300
            )

            // Warm gold — bottom left, triangulated cinema lighting
            RadialGradient(
                colors: [
                    Color(hex: "D4A01C").opacity(colorScheme == .dark ? 0.04 : 0.01),
                    Color.clear
                ],
                center: UnitPoint(x: 0.15, y: 0.85),
                startRadius: 0,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Noise Texture View
struct NoiseTextureView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.white.opacity(colorScheme == .dark ? 0.015 : 0)
            .blendMode(.overlay)
            .ignoresSafeArea()
            .drawingGroup()
            .allowsHitTesting(false)
    }
}

// MARK: - Vignette View
struct VignetteView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
    }

    var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.black.opacity(colorScheme == .dark ? 0.50 : 0.08)
            ]),
            center: .center,
            startRadius: screenWidth * 0.3,
            endRadius: screenWidth * 0.95
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
