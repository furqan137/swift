import SwiftUI

// MARK: - Email Sign In Prompt
//
// Gmail-specific Google OAuth entry. Styled to mirror the onboarding paywall
// language — big Anton title, kawaii bee mascot, single primary CTA. Apple
// sign-in is intentionally absent; Gmail access requires Google auth.
struct EmailSignInPrompt: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSigningIn = false
    @State private var appeared = false
    var onSuccess: () -> Void
    /// Show a back chevron in the top-left. Defaults to `true` so the
    /// user can always escape a first-launch / mistaken tap into the
    /// auth screen even when the host hides the nav bar.
    var showsBackButton: Bool = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Flat cream canvas — `Color.background` (#FBF9F6). Same
            // surface as `ContactsView` so the two tabs share one
            // continuous color. No gradient.
            Color.background.ignoresSafeArea()

            // Back chevron — first-launch safety. The host
            // (AskAIView / EmailCleanerView) hides the navigation
            // bar, so without this the user is trapped on the sign-in
            // screen with only "Continue with Google" or a force-kill.
            if showsBackButton {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "0A0A0A"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.top, 14)
                .zIndex(1)
            }

            VStack(spacing: 0) {
                // Title block — refined typography with tighter tracking and
                // a cleaner line break. Copy trimmed: "Connect Gmail" states
                // the action directly; subtitle frames the outcome.
                VStack(spacing: 10) {
                    Text("Connect\nyour inbox")
                        .font(.custom("Anton-Regular", size: 42))
                        .tracking(-0.5)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Sign in with Google to clean up Gmail")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(hex: "78716C"))
                        .multilineTextAlignment(.center)
                        .tracking(-0.1)
                }
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
                .animation(.easeOut(duration: 0.3), value: appeared)

                Spacer(minLength: 0)

                // Hero bee with a soft ambient halo — radial gradient behind
                // the mascot gives it a subtle lift from the flat gradient bg
                // without needing a card/border. `.blendMode(.multiply)`
                // drops the PNG's white bg into the gradient.
                //
                // Each child gets its own `.frame(maxWidth: .infinity,
                // alignment: .center)`. Without that, `.frame(maxWidth: …)`
                // alone doesn't horizontally center inside the parent ZStack
                // — the image's intrinsic-sized frame floats wherever the
                // ZStack alignment puts it, and any asymmetry in the PNG
                // padding visibly pushes the bee off-center.
                ZStack {
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.85), location: 0.0),
                            .init(color: Color.white.opacity(0.0), location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                    .frame(width: 340, height: 340)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .blur(radius: 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.05), value: appeared)

                    Image("BeeHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 280)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .blendMode(.multiply)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.96)
                        .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.05), value: appeared)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)

                // CTA block — single primary action with a legal caption
                // immediately below it (tight coupling, not a footer).
                VStack(spacing: 10) {
                    Button {
                        Task {
                            isSigningIn = true
                            await authService.signInWithGoogle()
                            isSigningIn = false
                            if authService.isAuthenticated && authService.errorMessage == nil {
                                onSuccess()
                            }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            if isSigningIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                // Google G styled to match the real logo:
                                // white pill with a colored "G" inside. Avoids
                                // the harsh SF Symbol `g.circle.fill` look.
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 26, height: 26)
                                    Text("G")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(Color(hex: "4285F4"))
                                }
                            }

                            Text(isSigningIn ? "Connecting…" : "Continue with Google")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.11, green: 0.10, blue: 0.09))
                                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
                        )
                        .contentShape(Capsule())
                    }
                    .disabled(isSigningIn)
                    .buttonStyle(SignInButtonStyle())

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.destructive)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.1), value: appeared)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
    }
}

private struct SignInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

#Preview {
    EmailSignInPrompt(onSuccess: {})
}
