import SwiftUI

// MARK: - Premium Ambient Background
/// Soft luminous background that feels like light + air + depth.
/// Use as the base layer for every screen.
struct BackgroundView: View {
    var body: some View {
        ZStack {
            // 1. Base vertical gradient — cool tones top to bottom
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "F8F9FF"), location: 0.0),
                    .init(color: Color(hex: "EEF1FF"), location: 0.45),
                    .init(color: Color(hex: "E6ECFF"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 2. Warm honey glow near top center — subtle warmth
            RadialGradient(
                colors: [
                    Color(hex: "FFF4CC").opacity(0.07),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 20,
                endRadius: 280
            )

            // 3. Cool glow near bottom — adds depth
            RadialGradient(
                colors: [
                    Color(hex: "DDE7FF").opacity(0.12),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.92),
                startRadius: 30,
                endRadius: 300
            )

            // 4. Very faint noise-like texture via extra radial offset
            RadialGradient(
                colors: [
                    Color(hex: "F0E8FF").opacity(0.04),
                    Color.clear
                ],
                center: .init(x: 0.2, y: 0.35),
                startRadius: 10,
                endRadius: 200
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    BackgroundView()
}

// MARK: - Bitepal Canvas
/// Cool-gray vertical gradient shared across the Contacts / Email /
/// Settings / Compress tabs. Use this as the root background of any
/// screen reachable from those tabs so the canvas stays continuous.
struct BitepalCanvas: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
