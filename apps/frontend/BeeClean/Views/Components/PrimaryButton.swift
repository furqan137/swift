import SwiftUI

// MARK: - Primary Button
struct PrimaryButton: View {
    let title: String
    let iconName: String?
    let isLoading: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        _ title: String,
        iconName: String? = nil,
        isLoading: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.isLoading = isLoading
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(-0.2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Deep 3-stop gold gradient
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .fill(isDestructive
                            ? LinearGradient(colors: [Color.destructive, Color.destructive.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hex: "9A7208"), Color(hex: "C4850A"), Color(hex: "B07D09")], startPoint: .top, endPoint: .bottom))

                    // Top highlight
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Bottom darkening
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.12)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.75)
            )
            .shadow(color: Color.primaryColor.opacity(0.35), radius: 20, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
    }
}

// MARK: - Secondary Button
struct SecondaryButton: View {
    let title: String
    let iconName: String?
    let action: () -> Void

    init(
        _ title: String,
        iconName: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .medium))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.surfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(Color.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadowSm()
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Icon Button
struct IconButton: View {
    let iconName: String
    let size: CGFloat
    let color: Color
    let action: () -> Void

    init(
        iconName: String,
        size: CGFloat = 40,
        color: Color = .foreground,
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.size = size
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.surfaceLight)
                        .overlay(
                            Circle()
                                .stroke(Color.border.opacity(0.6), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        PrimaryButton("Scan My Hive", iconName: "magnifyingglass") {}
        PrimaryButton("Delete All", iconName: "trash.fill", isDestructive: true) {}
        SecondaryButton("Cancel", iconName: "xmark") {}

        HStack(spacing: 16) {
            IconButton(iconName: "xmark") {}
            IconButton(iconName: "checkmark", color: .primaryColor) {}
            IconButton(iconName: "gear") {}
        }
    }
    .padding()
    .background(Color.background)
}
