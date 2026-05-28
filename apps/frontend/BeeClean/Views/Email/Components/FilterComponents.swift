import SwiftUI

// MARK: - Filter Section Header
struct FilterSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "78716C"))

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "78716C"))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Chip Button
struct ChipButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? Color(hex: "1C1917") : Color(hex: "78716C"))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color(hex: "1C1917").opacity(0.08) : Color.white)
                    .shadow(color: isSelected ? Color.clear : Color.black.opacity(0.03), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(hex: "1C1917").opacity(0.2) : Color.black.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

