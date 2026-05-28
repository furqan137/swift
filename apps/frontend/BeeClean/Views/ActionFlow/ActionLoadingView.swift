import SwiftUI

// MARK: - Action Loading View
//
// Full-screen centered loading state shown while a cleanup action executes.
// Reuses WarmGoldBackdrop and existing design tokens.

struct ActionLoadingView: View {
    let progress: ActionFlowCoordinator.ActionProgress

    @State private var pulseScale: CGFloat = 0.95

    var body: some View {
        ZStack {
            WarmGoldBackdrop()

            VStack(spacing: 24) {
                Spacer()

                // Animated pulse indicator
                ZStack {
                    Circle()
                        .fill(Color.primaryColor.opacity(0.08))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)

                    Image(systemName: "circle.dotted")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundColor(Color(hex: "1C1917").opacity(0.7))
                        .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                }

                // Loading label
                Text(progress.label)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "1C1917"))

                // Progress text (only for deterministic progress)
                if progress.total > 0 && progress.current > 0 {
                    Text("\(progress.current) of \(progress.total) processed")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .contentTransition(.numericText(countsDown: false))
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.label)
    }
}
