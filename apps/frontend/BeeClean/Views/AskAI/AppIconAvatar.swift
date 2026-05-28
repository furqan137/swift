import SwiftUI

// MARK: - App Icon Avatar Helper
struct AppIconAvatar: View {
    let size: CGFloat

    var body: some View {
        if let iconName = getAppIconName(), let uiImage = UIImage(named: iconName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        } else {
            ZStack {
                Circle()
                    .fill(Color(hex: "FFF8E7"))
                    .frame(width: size, height: size)

                Text("🐝")
                    .font(.system(size: size * 0.5))
            }
        }
    }

    private func getAppIconName() -> String? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else { return nil }
        return lastIcon
    }
}
