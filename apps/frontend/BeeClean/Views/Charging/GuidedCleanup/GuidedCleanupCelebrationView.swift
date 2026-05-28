import SwiftUI

// MARK: - Guided Cleanup Celebration View
//
// Shared checkpoint + completion layout matching the Figma celebration
// screen: yellow progress row, title, mascot, stats card, primary CTA.

struct GuidedCleanupCelebrationView<Footer: View>: View {
    let content: GuidedCleanupCelebrationContent
    let onPrimary: () -> Void
    var isPrimaryDisabled: Bool = false
    let footer: Footer

    private let honeyYellow = Color(hex: "FFC636")
    private let successGreen = Color(hex: "3A6B3A")
    private let inactiveGrey = Color(hex: "D1D1D6")

    init(
        content: GuidedCleanupCelebrationContent,
        onPrimary: @escaping () -> Void,
        isPrimaryDisabled: Bool = false,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.content = content
        self.onPrimary = onPrimary
        self.isPrimaryDisabled = isPrimaryDisabled
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {

            titleBlock
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Spacer(minLength: 16)
            
            GuidedCleanupFrameAnimationView(animation: content.mascotAnimation)
                .padding(.horizontal, 16)
            
            Spacer(minLength: 16)
            statsCard
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            primaryButton
                .padding(.horizontal, 16)

            footer
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .padding(.all, 0)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(content.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Text(content.subtitlePrefix)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(content.subtitleHighlight)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(honeyYellow)
            }
            .multilineTextAlignment(.center)
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(successGreen.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(successGreen)
                }

                Text("Total cleaned in this task")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(content.formattedSessionBytes)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(inactiveGrey.opacity(0.5))
                            .frame(height: 8)
                        Capsule()
                            .fill(successGreen)
                            .frame(
                                width: max(geo.size.width * content.sessionProgressFraction, 0),
                                height: 8
                            )
                            .animation(.easeOut(duration: 0.6), value: content.sessionProgressFraction)
                    }
                }
                .frame(height: 8)

                HStack {
                    Spacer()
                    Text("\(content.formattedSessionGoal) goal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    // MARK: - Primary CTA

    private var primaryButton: some View {
        Button {
            HapticManager.shared.impact(.medium)
            onPrimary()
        } label: {
            Group {
                if isPrimaryDisabled {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(content.primaryButtonTitle)
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(honeyYellow.opacity(isPrimaryDisabled ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            .shadow(color: honeyYellow.opacity(0.35), radius: 10, y: 4)
        }
        .disabled(isPrimaryDisabled)
        .buttonStyle(ScaleButtonStyle())
    }
}
