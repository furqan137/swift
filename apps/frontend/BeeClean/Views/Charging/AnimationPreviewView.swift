import SwiftUI

// MARK: - Animation Preview View
struct AnimationPreviewView: View {
    let animation: ChargingAnimation
    let onDismiss: () -> Void

    @AppStorage("selectedChargingAnimation") private var selectedId = ""
    @State private var batteryLevel: Int = 78
    @State private var showTutorial = false
    @State private var timer: Timer?

    private var isActive: Bool { selectedId == animation.id }

    var body: some View {
        ZStack {
            // Dark base
            Color.black.ignoresSafeArea()

            // Full-screen live animation effect
            ChargingEffectView(animationId: animation.id, isCompact: false)
                .ignoresSafeArea()

            // Content overlay
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Battery display
                VStack(spacing: 8) {
                    Text("\(batteryLevel)%")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: animation.accentColor.opacity(0.3), radius: 20)

                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.white.opacity(0.8))
                        Text("Charging")
                            .font(.titleMedium)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Bottom bar
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(animation.name)
                            .font(.titleLarge)
                            .foregroundColor(.white)
                        Text(animation.description)
                            .font(.bodyMedium)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    HStack(spacing: 12) {
                        // Set as Active button
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedId = animation.id
                            }
                            HapticManager.shared.impact(.medium)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "bolt.circle.fill")
                                Text(isActive ? "Active" : "Set as Active")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isActive ? Color(hex: "003D32") : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        isActive
                                            ? LinearGradient(colors: [Color(hex: "00D4AA"), Color(hex: "00B4D8")],
                                                             startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.08)],
                                                             startPoint: .top, endPoint: .bottom)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        isActive ? Color.clear : Color.white.opacity(0.1),
                                        lineWidth: 0.5
                                    )
                            )
                        }

                        // How to Set Up button
                        Button {
                            showTutorial = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gear")
                                Text("Set Up")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Belt-and-suspenders: invalidate any existing timer before
            // creating a new one. SwiftUI usually fires .onAppear once
            // per appearance, but on rapid present/dismiss cycles a
            // second .onAppear could overwrite this @State reference
            // before .onDisappear cleared it, leaving the old Timer
            // alive but unreachable. The pre-invalidate makes the
            // assignment idempotent.
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                withAnimation {
                    if batteryLevel < 100 { batteryLevel += 1 }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .sheet(isPresented: $showTutorial) {
            TutorialSheet(animation: animation)
        }
        .swipeToDismissUsing(onDismiss)
    }
}

// MARK: - Tutorial Sheet
struct TutorialSheet: View {
    let animation: ChargingAnimation
    @Environment(\.dismiss) private var dismiss

    private let tutorialSteps: [TutorialStep] = [
        TutorialStep(id: 1, title: "Open Shortcuts App",
                     description: "Open the Apple Shortcuts app on your iPhone",
                     iconName: "app.fill"),
        TutorialStep(id: 2, title: "Create Automation",
                     description: "Tap Automation tab \u{2192} New Automation \u{2192} Charger \u{2192} Is Connected",
                     iconName: "bolt.fill"),
        TutorialStep(id: 3, title: "Add Action",
                     description: "Search 'Open App' \u{2192} select BeeClean",
                     iconName: "magnifyingglass"),
        TutorialStep(id: 4, title: "Disable Confirmation",
                     description: "Turn off 'Ask Before Running' \u{2192} tap Done",
                     iconName: "checkmark.circle.fill"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Set Up \(animation.name)")
                            .font(.titleLarge)
                            .foregroundColor(.foreground)

                        Text("Follow these steps to enable charging animations")
                            .font(.bodyMedium)
                            .foregroundColor(.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Tutorial steps
                    VStack(spacing: 16) {
                        ForEach(tutorialSteps) { step in
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primaryColor.opacity(0.15))
                                        .frame(width: 48, height: 48)

                                    Image(systemName: step.iconName)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.primaryColor)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Step \(step.id): \(step.title)")
                                        .font(.labelLarge)
                                        .foregroundColor(.foreground)

                                    Text(step.description)
                                        .font(.bodySmall)
                                        .foregroundColor(.mutedForeground)
                                }

                                Spacer()
                            }
                            .padding(16)
                            .cardSurface(.standard)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Done button
                    PrimaryButton("Got It") {
                        dismiss()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.mutedForeground)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    AnimationPreviewView(
        animation: ChargingAnimation(
            id: "neon-pulse",
            name: "Neon Pulse",
            iconName: "bolt.fill",
            gradientColors: [.blue, .cyan],
            accentColor: .cyan,
            description: "Electric neon charging effect"
        )
    ) {}
}
