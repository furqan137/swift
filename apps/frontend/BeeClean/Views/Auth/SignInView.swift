import SwiftUI

struct SignInView: View {
    @StateObject private var authService = AuthService.shared
    @AppStorage("userName") private var beeName: String = "Bee"
    @State private var isSigningIn = false
    @State private var appeared = false
    @State private var beeFloat = false

    // MARK: - Palette
    private let honeyGold      = Color(hex: "C4850A")
    private let honeyLight     = Color(hex: "F0D58A")
    private let honeyWarm      = Color(hex: "E6C77A")
    private let warmCream      = Color(hex: "FBF6EC")
    private let darkText       = Color(hex: "1A140A")
    private let mutedText      = Color(hex: "78716C")

    // MARK: - Body
    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // Hero bee
                    beeHero
                        .padding(.bottom, 28)

                    // Greeting headline
                    greetingSection
                        .padding(.horizontal, 28)
                        .padding(.bottom, 32)

                    // Feature grid (2x2)
                    featureGrid
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }

            // Pinned bottom CTA
            VStack(spacing: 0) {
                Spacer()
                signInSection
                    .background(
                        // Soft fade so the CTA floats above the scroll content
                        LinearGradient(
                            colors: [warmCream.opacity(0), warmCream, warmCream],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                beeFloat = true
            }
        }
    }

    // MARK: - Background — layered warm gradients
    private var background: some View {
        ZStack {
            // Base warm cream
            warmCream.ignoresSafeArea()

            // Top vertical wash — lighter at the top
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.7), location: 0),
                    .init(color: Color.white.opacity(0.0), location: 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Honey radial pool centered behind the hero
            RadialGradient(
                colors: [
                    honeyLight.opacity(0.32),
                    honeyLight.opacity(0.10),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.22),
                startRadius: 30,
                endRadius: 320
            )
            .ignoresSafeArea()

            // Lower-right warm accent for depth
            RadialGradient(
                colors: [honeyWarm.opacity(0.10), Color.clear],
                center: .init(x: 0.85, y: 0.85),
                startRadius: 30,
                endRadius: 280
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Hero Bee
    private var beeHero: some View {
        ZStack {
            // Outer glow halo — multiple layers for depth
            Circle()
                .fill(honeyLight.opacity(0.15))
                .frame(width: 240, height: 240)
                .blur(radius: 20)

            Circle()
                .fill(honeyLight.opacity(0.20))
                .frame(width: 180, height: 180)
                .blur(radius: 12)

            // Soft white disc backdrop
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 168, height: 168)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [honeyLight.opacity(0.45), honeyLight.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: honeyGold.opacity(0.20), radius: 32, y: 14)
                .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)

            // Bee illustration
            Image("bee_gold_circle")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 138)
                .offset(y: beeFloat ? -5 : 5)
                .shadow(color: honeyGold.opacity(0.18), radius: 12, y: 6)
        }
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        VStack(spacing: 8) {
            Text("Hey \(beeName.isEmpty ? "there" : beeName),")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(darkText)

            Text("let's get you set up")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(darkText.opacity(0.42))

            Text("Sign in to connect your accounts\nand let your bee start cleaning.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    // MARK: - Feature Grid (2x2 — the BitePal-style cards)
    private var featureGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            featureCard(
                icon: "envelope.fill",
                title: "Email",
                subtitle: "Inbox cleanup",
                accent: Color(hex: "3B82F6"),
                delay: 0.05
            )
            featureCard(
                icon: "photo.fill.on.rectangle.fill",
                title: "Photos",
                subtitle: "Free up space",
                accent: Color(hex: "F59E0B"),
                delay: 0.10
            )
            featureCard(
                icon: "person.2.fill",
                title: "Contacts",
                subtitle: "Find duplicates",
                accent: Color(hex: "10B981"),
                delay: 0.15
            )
            featureCard(
                icon: "lock.shield.fill",
                title: "Private",
                subtitle: "Secret vault",
                accent: Color(hex: "8B5CF6"),
                delay: 0.20
            )
        }
    }

    private func featureCard(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        delay: Double
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.13))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(darkText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)

                // Top sheen
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)
            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay), value: appeared)
    }

    // MARK: - Sign In Section (pinned bottom)
    private var signInSection: some View {
        VStack(spacing: 14) {
            // Google CTA
            Button {
                Task {
                    isSigningIn = true
                    // `primaryCommit()` for the press itself — auth is
                    // the headline action of this screen, and the
                    // semantic wrapper matches every other "submit"
                    // surface in the app.
                    HapticManager.shared.primaryCommit()
                    await authService.signInWithGoogle()
                    isSigningIn = false
                    if authService.isAuthenticated && authService.errorMessage == nil {
                        UserDefaults.standard.set(true, forKey: "gmail_connected")
                        // `actionSuccess()` (notify.success) on the
                        // landing — celebratory cue that auth went
                        // through, distinct from the press itself.
                        HapticManager.shared.actionSuccess()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                            Text("G")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(Color(hex: "4285F4"))
                        }
                    }

                    Text(isSigningIn ? "Connecting..." : "Continue with Google")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(darkText)

                        // Inner top gloss for premium hardware feel
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.plusLighter)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: darkText.opacity(0.30), radius: 22, y: 10)
                .shadow(color: darkText.opacity(0.18), radius: 6, y: 3)
            }
            .disabled(isSigningIn)
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 24)

            // Error
            if let error = authService.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "DC2626"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Legal
            Text("By continuing, you agree to our [Terms](terms) and [Privacy Policy](privacy).")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(mutedText.opacity(0.7))
                .multilineTextAlignment(.center)
                .tint(mutedText)
                .padding(.top, 4)

        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
    }
}

#Preview {
    SignInView()
        .preferredColorScheme(.light)
}
