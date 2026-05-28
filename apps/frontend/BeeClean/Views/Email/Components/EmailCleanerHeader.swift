import SwiftUI

// MARK: - Email Cleaner Header
struct EmailCleanerHeader: View {
    let showsBackButton: Bool
    let onFilterTapped: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            Text("Email")
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(Color(hex: "1C1917"))

            Spacer()

            Button(action: onFilterTapped) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}
