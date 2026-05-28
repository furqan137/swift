import SwiftUI

// MARK: - Delete Button
struct DeleteButton: View {
    let count: Int
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .medium))
                }

                Text(isLoading ? "Deleting..." : "Delete \(EmailFormatters.numFmt(count)) Emails")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "DC2626"), Color(hex: "B91C1C")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top highlight
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: Color(hex: "DC2626").opacity(0.3), radius: 16, y: 6)
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        DeleteButton(count: 1500, isLoading: false, action: {})
        DeleteButton(count: 0, isLoading: true, action: {})
    }
    .padding()
    .background(Color.white)
    .preferredColorScheme(.light)
}
