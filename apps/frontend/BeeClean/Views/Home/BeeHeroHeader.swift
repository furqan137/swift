import SwiftUI

// MARK: - Hero Mascot
/// Premium hero section with landscape background image, bee mascot
/// standing on the ground line, greeting text + settings gear.
struct HeroMascot: View {

    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let safeAreaTop: CGFloat

    @State private var floatOffset: CGFloat = 0

    // ── Layout constants ────────────────────────────────
    private let heroHeight: CGFloat = 340
    private let horizonFraction: CGFloat = 0.35
    private let beeFeetFraction: CGFloat = 1.0
    private var beeSize: CGFloat { screenWidth * 0.72 }
    private var totalHeight: CGFloat { heroHeight + safeAreaTop }

    // ── Bee positioning math ────────────────────────────
    private var horizonY: CGFloat { safeAreaTop + (heroHeight * horizonFraction) }
    private var beeTopY: CGFloat { horizonY - (beeSize * beeFeetFraction) }
    private var beeCenterY: CGFloat { beeTopY + beeSize / 2 }
    private var beeOffsetY: CGFloat { beeCenterY - totalHeight / 2 }

    var body: some View {
        ZStack {
            // Background landscape
            Image("hero_background")
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenWidth, height: totalHeight)
                .clipped()

            // Bee mascot – feet on the horizon line
            Image("BeeHero")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: beeSize, height: beeSize)
                .offset(y: beeOffsetY + floatOffset)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: floatOffset
                )
                .onAppear { floatOffset = -6 }
        }
        .frame(width: screenWidth, height: totalHeight)
    }

    // MARK: - Greeting Text

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Still up?"
        }
    }

    private var greetingSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Your hive is looking great."
        case 12..<17: return "Ready to tidy up?"
        case 17..<21: return "Let's get organized."
        default: return "I'm here whenever you need."
        }
    }
}

#Preview {
    NavigationStack {
        GeometryReader { geo in
            ZStack {
                Color.honeyCanvas.ignoresSafeArea()
                ScrollView {
                    HeroMascot(
                        screenWidth: geo.size.width,
                        screenHeight: geo.size.height,
                        safeAreaTop: geo.safeAreaInsets.top
                    )
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}
