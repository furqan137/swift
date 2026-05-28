import SwiftUI

struct UnsubscribeBar: View {
    let action: () -> Void
    @StateObject private var emailService = EmailService.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 18))
                    .foregroundColor(.foreground)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unsubscribe")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.foreground)

                    if emailService.isSendersLoading && emailService.senders.isEmpty {
                        Text("Scanning senders...")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.mutedForeground)
                    } else {
                        Text("\(emailService.senders.count) senders found")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.mutedForeground)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.border)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(Color.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

#Preview {
    UnsubscribeBar(action: {})
        .background(Color.background)
}
