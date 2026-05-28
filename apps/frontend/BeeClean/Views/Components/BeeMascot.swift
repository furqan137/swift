import SwiftUI

// MARK: - Bee Mascot
struct BeeMascot: View {
    let size: BeeSize
    let expression: BeeExpression

    init(_ size: BeeSize = .medium, _ expression: BeeExpression = .neutral) {
        self.size = size
        self.expression = expression
    }

    enum BeeSize {
        case small, medium, large, hero

        var points: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 48
            case .large: return 80
            case .hero: return 120
            }
        }

        var glowRadius: CGFloat {
            switch self {
            case .small: return 24
            case .medium: return 36
            case .large: return 60
            case .hero: return 90
            }
        }
    }

    enum BeeExpression: String {
        case neutral, happy, thinking, proud, sleeping, waving

        var iconName: String {
            switch self {
            case .neutral: return "ladybug.fill"
            case .happy: return "ladybug.fill"
            case .thinking: return "ladybug.fill"
            case .proud: return "ladybug.fill"
            case .sleeping: return "ladybug.fill"
            case .waving: return "ladybug.fill"
            }
        }
    }

    @State private var animate = false

    var body: some View {
        ZStack {
            // Honey glow aura — renders beyond frame, doesn't affect layout
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.primaryColor.opacity(0.12),
                            Color.primaryColor.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size.points * 0.2,
                        endRadius: size.glowRadius
                    )
                )
                .frame(width: size.glowRadius * 2, height: size.glowRadius * 2)
                .scaleEffect(animate ? 1.05 : 0.95)

            // Main bee icon
            Image(systemName: expression.iconName)
                .font(.system(size: size.points * 0.65, weight: .medium))
                .foregroundStyle(LinearGradient.honeyGradient)
                .modifier(BeeAnimationModifier(expression: expression, animate: animate))
        }
        // Constrain layout frame to icon size — glow overflows visually but doesn't push siblings
        .frame(width: size.points, height: size.points)
        .onAppear {
            withAnimation(animationForExpression.repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private var animationForExpression: Animation {
        switch expression {
        case .neutral:
            return .easeInOut(duration: 3.0)
        case .happy:
            return .spring(response: 0.4, dampingFraction: 0.5)
        case .thinking:
            return .easeInOut(duration: 2.0)
        case .proud:
            return .easeInOut(duration: 2.5)
        case .sleeping:
            return .easeInOut(duration: 4.0)
        case .waving:
            return .easeInOut(duration: 1.2)
        }
    }
}

// MARK: - Bee Animation Modifier
struct BeeAnimationModifier: ViewModifier {
    let expression: BeeMascot.BeeExpression
    let animate: Bool

    func body(content: Content) -> some View {
        switch expression {
        case .neutral:
            content
                .offset(y: animate ? -2 : 2)
        case .happy:
            content
                .scaleEffect(animate ? 1.08 : 1.0)
                .offset(y: animate ? -4 : 0)
        case .thinking:
            content
                .rotationEffect(.degrees(animate ? 5 : -5))
        case .proud:
            content
                .scaleEffect(animate ? 1.05 : 1.0)
        case .sleeping:
            content
                .opacity(animate ? 0.7 : 1.0)
                .offset(y: animate ? 1 : -1)
        case .waving:
            content
                .rotationEffect(.degrees(animate ? 10 : -10))
                .offset(y: animate ? -3 : 0)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        BeeMascot(.hero, .waving)
        BeeMascot(.large, .happy)

        HStack(spacing: 30) {
            BeeMascot(.medium, .neutral)
            BeeMascot(.medium, .thinking)
            BeeMascot(.small, .sleeping)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.background)
}
