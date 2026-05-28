import SwiftUI

// MARK: - Animation Card
struct AnimationCard: View {
    let animation: ChargingAnimation
    let action: () -> Void
    @AppStorage("selectedChargingAnimation") private var selectedId = ""

    private var isActive: Bool { selectedId == animation.id }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    // Live mini-preview clipped to circle
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 70, height: 70)
                        .overlay(
                            ChargingEffectView(animationId: animation.id, isCompact: true)
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    isActive
                                        ? LinearGradient(colors: [Color(hex: "00D4AA"), Color(hex: "00B4D8")],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                                         startPoint: .top, endPoint: .bottom),
                                    lineWidth: isActive ? 2 : 0.5
                                )
                        )
                        .shadow(color: animation.accentColor.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 10 : 6)

                    // Active checkmark badge
                    if isActive {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color(hex: "00D4AA"), Color(hex: "00B4D8")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: Color(hex: "00D4AA").opacity(0.4), radius: 4)
                            .offset(x: 26, y: -26)
                    }
                }

                VStack(spacing: 2) {
                    Text(animation.name)
                        .font(.labelMedium)
                        .foregroundColor(.foreground)

                    if isActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "00D4AA"))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .cardSurface(.elevated)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
