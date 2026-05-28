import SwiftUI

struct ChargingAnimationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAnimation: ChargingAnimation? = nil
    @AppStorage("selectedChargingAnimation") private var activeAnimationId = ""

    private static let animations: [ChargingAnimation] = [
        ChargingAnimation(id: "neon-pulse", name: "Neon Pulse", iconName: "bolt.fill",
                          gradientColors: [Color(red: 0.0, green: 0.4, blue: 1.0), .cyan],
                          accentColor: .cyan, description: "Electric neon charging effect"),
        ChargingAnimation(id: "aurora", name: "Aurora", iconName: "sparkles",
                          gradientColors: [.purple, Color(red: 0.0, green: 0.8, blue: 0.6)],
                          accentColor: .green, description: "Northern lights inspired animation"),
        ChargingAnimation(id: "solar-flare", name: "Solar Flare", iconName: "sun.max.fill",
                          gradientColors: [.orange, .red],
                          accentColor: .orange, description: "Warm solar energy waves"),
        ChargingAnimation(id: "crystal", name: "Crystal", iconName: "diamond.fill",
                          gradientColors: [Color(red: 0.6, green: 0.2, blue: 1.0), Color(red: 0.9, green: 0.3, blue: 0.8)],
                          accentColor: .purple, description: "Crystalline energy flow"),
        ChargingAnimation(id: "ocean", name: "Ocean Wave", iconName: "water.waves",
                          gradientColors: [Color(red: 0.0, green: 0.3, blue: 0.8), .cyan],
                          accentColor: .blue, description: "Calming ocean wave animation"),
        ChargingAnimation(id: "midnight", name: "Midnight", iconName: "moon.stars.fill",
                          gradientColors: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.3, green: 0.1, blue: 0.5)],
                          accentColor: Color(red: 0.6, green: 0.4, blue: 1.0), description: "Elegant midnight glow"),
    ]

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ChargingAnimationsHeader(
                    activeName: Self.animations.first { $0.id == activeAnimationId }?.name,
                    onBack: { dismiss() }
                )

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(Self.animations) { animation in
                            AnimationCard(animation: animation) {
                                selectedAnimation = animation
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedAnimation) { animation in
            AnimationPreviewView(animation: animation) {
                selectedAnimation = nil
            }
        }
    }
}

// MARK: - Header
private struct ChargingAnimationsHeader: View {
    let activeName: String?
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                HapticManager.shared.arrowNudge(.backward)
                onBack()
            }) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text("Charging Animations")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                if let name = activeName {
                    Text("Active: \(name)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "00D4AA").opacity(0.8))
                } else {
                    Text("Customize your charging screen")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.leading, 8)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

#Preview {
    NavigationStack {
        ChargingAnimationsView()
    }
    .preferredColorScheme(.dark)
}
