import SwiftUI
import StoreKit

// MARK: - Rate Us View
struct RateUsView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var showThanks = false
    @State private var hasRequestedReview = false
    @State private var appeared = false
    @State private var starsAppeared = false
    @State private var thanksPulse = false

    private let gold = Color(hex: "FCD34D")
    private let goldDark = Color(hex: "F59E0B")

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            AmbientGlowView()

            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Button {
                        HapticManager.shared.arrowNudge(.backward)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                            )
                    }

                    Text("Rate Us")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 8)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)

                Spacer()

                if !showThanks {
                    ratingContent
                } else {
                    thanksContent
                }

                Spacer()
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                starsAppeared = true
            }
        }
    }

    // MARK: - Rating Content
    private var ratingContent: some View {
        VStack(spacing: 28) {
            // Animated icon with glow
            ZStack {
                // Ambient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [gold.opacity(0.15), gold.opacity(0.05), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Icon circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [gold.opacity(0.15), goldDark.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .overlay(
                            Circle()
                                .stroke(gold.opacity(0.20), lineWidth: 0.5)
                        )

                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [gold, goldDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: gold.opacity(0.25), radius: 20)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            VStack(spacing: 8) {
                Text("Enjoying BeeClean?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text("Tap a star to rate your experience")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.4))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            // Star rating with glass card
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            rating = star
                        }
                        HapticManager.shared.impact(.light)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            if star >= 4 && !hasRequestedReview {
                                requestReview()
                                hasRequestedReview = true
                            }
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showThanks = true
                            }
                            HapticManager.shared.notify(.success)
                        }
                    } label: {
                        ZStack {
                            // Star glow when selected
                            if star <= rating {
                                Circle()
                                    .fill(gold.opacity(0.20))
                                    .frame(width: 44, height: 44)
                                    .blur(radius: 8)
                            }

                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(
                                    star <= rating
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [gold, goldDark],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ))
                                        : AnyShapeStyle(Color.white.opacity(0.15))
                                )
                                .scaleEffect(star <= rating ? 1.15 : 1.0)
                                .shadow(color: star <= rating ? gold.opacity(0.40) : .clear, radius: 8)
                        }
                    }
                    .opacity(starsAppeared ? 1 : 0)
                    .offset(y: starsAppeared ? 0 : 16)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(star) * 0.06), value: starsAppeared)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.surfaceMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.06), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        rating > 0
                            ? LinearGradient(colors: [gold.opacity(0.25), goldDark.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: rating > 0 ? gold.opacity(0.10) : .clear, radius: 16, y: 4)
            .padding(.horizontal, 32)
            .opacity(starsAppeared ? 1 : 0)
        }
    }

    // MARK: - Thanks Content
    private var thanksContent: some View {
        VStack(spacing: 24) {
            // Success icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.primaryColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(thanksPulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: thanksPulse)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.primaryColor.opacity(0.15), Color.primaryColor.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                        .overlay(
                            Circle()
                                .stroke(Color.primaryColor.opacity(0.25), lineWidth: 0.5)
                        )

                    Image(systemName: rating >= 4 ? "heart.fill" : "envelope.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.primaryColor, Color(hex: "00B4D8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color.primaryColor.opacity(0.25), radius: 20)
            }

            Text("Thank You!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            if rating >= 4 {
                Text("Thanks for the love! If the App Store review\npopped up, we'd appreciate a quick rating.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            } else {
                VStack(spacing: 16) {
                    Text("We'd love to hear how we can improve.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)

                    Button {
                        if let url = URL(string: "mailto:support@beeclean.app?subject=BeeClean%20Feedback") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14))
                            Text("Send Feedback")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.primaryColor, Color(hex: "00B4D8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        )
                        .shadow(color: Color.primaryColor.opacity(0.30), radius: 12, y: 4)
                    }
                    .padding(.horizontal, 48)
                }
            }
        }
        .onAppear { thanksPulse = true }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
