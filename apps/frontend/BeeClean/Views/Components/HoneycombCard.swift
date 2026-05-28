import SwiftUI

// MARK: - Honeycomb Card
/// Category card for the dashboard grid — elevated, rich, with glow
struct HoneycombCard: View {
    let destination: CleanupDestination
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let subtitleColor: Color

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon in circle with ring
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 46, height: 46)

                    Circle()
                        .stroke(iconColor.opacity(0.15), lineWidth: 1)
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .padding(.bottom, DesignTokens.Spacing.md)

                Spacer(minLength: 0)

                // Title
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.foreground)
                    .lineLimit(1)
                    .tracking(-0.1)

                // Subtitle
                Text(subtitle)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 144)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(Color.card)

                    // Diagonal sheen
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.04), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .stroke(Color.border.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: iconColor.opacity(0.06), radius: 8, x: 0, y: 3)
            .shadowMd()
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        HoneycombCard(
            destination: .duplicatePhotos,
            icon: "doc.on.doc",
            iconColor: .categorySky,
            title: "Duplicates",
            subtitle: "Tap to view",
            subtitleColor: .mutedForeground
        )
        HoneycombCard(
            destination: .similarPhotos,
            icon: "photo.stack",
            iconColor: .categoryViolet,
            title: "Similar Photos",
            subtitle: "12 groups",
            subtitleColor: .mutedForeground
        )
    }
    .padding()
    .background(Color.background)
}
