import SwiftUI

// MARK: - Media Cleanup Card
struct MediaCleanupCard: View {
    let category: MediaCategory

    var body: some View {
        HStack(spacing: 14) {
            // Icon in tinted rounded square
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(category.color.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [category.color.opacity(0.06), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )

                Image(systemName: category.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(category.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.foreground)

                Text("\(category.count) items")
                    .font(.system(size: 13))
                    .foregroundColor(.mutedForeground)
                    .contentTransition(.numericText())
            }

            Spacer()

            Text(category.size)
                .font(.custom("Poppins-Bold", size: 14))
                .foregroundColor(.foregroundSecondary)

            ChevronGlyph(tint: Color(hex: "A1A1AA"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Match the IntelligentPreviewCard / Email / SegmentedControl
        // surface so the whole homepage stack reads as one design language:
        // material + white gradient + sheen border + soft shadow.
        .background(GlassPanel(cornerRadius: DesignTokens.Radius.xl, elevation: .card))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }
}
