import SwiftUI

// MARK: - Animation Constants
extension Animation {
    // Standard transitions
    static let fadeIn = Animation.easeOut(duration: 0.25)
    static let slideUp = Animation.easeOut(duration: 0.3)
    static let slideDown = Animation.easeOut(duration: 0.3)
    static let scaleIn = Animation.easeOut(duration: 0.2)

    // Interactive animations
    static let buttonPress = Animation.easeOut(duration: 0.15)
    static let cardHover = Animation.easeInOut(duration: 0.2)

    // Progress animations
    static let progressFill = Animation.easeOut(duration: 1.0)
}

// MARK: - Transition Definitions
extension AnyTransition {
    static let slideUpFade = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
    )

    static let slideDownFade = AnyTransition.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    )

    static let scaleFade = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.95).combined(with: .opacity),
        removal: .scale(scale: 0.95).combined(with: .opacity)
    )

    static let fadeScale = AnyTransition.opacity.combined(with: .scale(scale: 0.97))
}

// MARK: - Staggered Animation Helper

// Cap the per-row stagger window so a list with 100+ rows doesn't make
// row 99 wait 4 seconds to fade in. The first 6 rows still feel
// staggered (≤0.24s); everything past that snaps in immediately — most
// importantly, when a user scrolls fast through a LazyVStack and a
// far-down row appears, it doesn't sit invisible while sleeping.
private let staggeredAnimationMaxSteps = 6

struct StaggeredAnimation<Content: View>: View {
    let index: Int
    let delay: Double
    @ViewBuilder let content: () -> Content
    @State private var isVisible = false

    init(index: Int, delay: Double = 0.04, @ViewBuilder content: @escaping () -> Content) {
        self.index = index
        self.delay = delay
        self.content = content
    }

    var body: some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
            .task {
                let cappedIndex = min(index, staggeredAnimationMaxSteps)
                let ns = UInt64(Double(cappedIndex) * delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                withAnimation(.easeOut(duration: 0.2)) {
                    isVisible = true
                }
            }
    }
}
