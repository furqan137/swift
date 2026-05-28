import SwiftUI

// MARK: - Category Row
struct EmailCategoryRowView: View {
    let category: GmailCategory
    let isSelected: Bool
    let onCheckboxTapped: () -> Void
    let onArrowTapped: () -> Void

    // Manual press state so the dim/scale stays visible for ~0.15s
    // before navigation fires — vanilla SwiftUI Button press ends the
    // instant the navigation pushes, which made these rows feel static
    // to the user even though ContactTileButtonStyle was applied.
    @State private var isPressed = false

    private var categoryColor: Color { category.tintColor }

    private var categoryDisplayName: String {
        switch category.id {
        case "social": return "Social Media"
        case "primary": return "Primary"
        default: return category.name
        }
    }

    private var categoryDetail: String {
        return "emails"
    }

    // Apple-Mail-meets-Bitepal: compact navigation row, title is the
    // focal element, count is muted secondary data on the right. Per-
    // category color survives only on the icon glyph + a 6pt dot before
    // the count, so identity is preserved without each card turning
    // into a colored chip. No subtitle — every row is "emails", that's
    // implied by the screen.
    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    isPressed = false
                }
                onArrowTapped()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.20), categoryColor.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(categoryColor.opacity(0.22), lineWidth: 0.6)
                    Image(systemName: category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(categoryColor)
                }
                .frame(width: 44, height: 44)

                Text(categoryDisplayName)
                    .font(.custom("Poppins-Bold", size: 19))
                    .foregroundColor(Color(hex: "1C1917"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                Text(formattedCount(category.count))
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(Color(hex: "1C1917"))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: category.count)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(categoryColor.opacity(0.12))
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 76)
            // Shared with the Contacts category tiles: GlassPanel layers
            // .ultraThinMaterial + a top-down white gradient + sheen border
            // and a soft drop shadow. Swapping the previous flat white fill
            // for this primitive gives the email rows the same glassy look
            // the user called out, and any future polish to the surface is
            // a one-file change in DesignTokens.swift.
            .background(GlassPanel(cornerRadius: 18, elevation: .card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(isPressed ? 0.16 : 0))
                    .allowsHitTesting(false)
            )
            .brightness(isPressed ? -0.08 : 0)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func formattedCount(_ count: Int) -> String {
        EmailFormatters.numFmt(count)
    }
}

// MARK: - Legacy initializer for backward compatibility
extension EmailCategoryRowView {
    init(category: GmailCategory, isSelected: Bool, action: @escaping () -> Void) {
        self.category = category
        self.isSelected = isSelected
        self.onCheckboxTapped = action
        self.onArrowTapped = action
    }
}

#Preview {
    VStack(spacing: 10) {
        EmailCategoryRowView(
            category: GmailCategory(id: "primary", name: "Primary", labelId: "CATEGORY_PERSONAL", count: 84),
            isSelected: false,
            onCheckboxTapped: {},
            onArrowTapped: {}
        )
        EmailCategoryRowView(
            category: GmailCategory(id: "social", name: "Social", labelId: "CATEGORY_SOCIAL", count: 5226),
            isSelected: false,
            onCheckboxTapped: {},
            onArrowTapped: {}
        )
        EmailCategoryRowView(
            category: GmailCategory(id: "promotions", name: "Promotions", labelId: "CATEGORY_PROMOTIONS", count: 20000),
            isSelected: false,
            onCheckboxTapped: {},
            onArrowTapped: {}
        )
    }
    .padding(.horizontal, 20)
    .background(Color.white)
    .preferredColorScheme(.light)
}
