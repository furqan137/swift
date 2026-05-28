import SwiftUI

// MARK: - Category Card
struct CategoryCard: View {
    let category: MediaCategory
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    // Icon with gradient background
                    Image(systemName: category.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(category.color)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [category.color.opacity(0.18), category.color.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(category.color.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                        .shadow(color: category.color.opacity(0.12), radius: 6)

                    Spacer()

                    Text(category.size)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.mutedForeground)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.foreground)
                        .lineLimit(1)

                    Text("\(category.count) items")
                        .font(.system(size: 13))
                        .foregroundColor(.mutedForeground)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xxl)
                    .fill(Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xxl)
                    .stroke(
                        isPressed ? category.color.opacity(0.20) : Color.border.opacity(0.5),
                        lineWidth: 0.5
                    )
            )
            .shadowMd()
        }
        .buttonStyle(CardPressStyle(isPressed: $isPressed))
    }
}

// MARK: - Card Press Style
struct CardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Card Button Style (kept for backward compat)
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    CategoryCard(
        category: MediaCategory(
            id: "preview",
            label: "Screenshots",
            iconName: "camera.viewfinder",
            count: 100,
            size: "1.2 GB",
            color: .categoryRed
        )
    ) {}
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}
