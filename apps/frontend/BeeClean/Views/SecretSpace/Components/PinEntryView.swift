import SwiftUI

// MARK: - PIN Entry View
struct PinEntryView: View {
    @Binding var enteredPIN: String
    @Binding var showError: Bool
    let onPinComplete: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(maxHeight: 20)

                // Lock icon
                Circle()
                    .fill(Color(hex: "F5F5F4"))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: showError ? "lock.trianglebadge.exclamationmark" : "lock.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(showError ? .destructive : Color(hex: "A1A1AA"))
                            .contentTransition(.symbolEffect(.replace))
                    )
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: appeared)

                Text("Enter Passcode")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .padding(.top, 14)

                Text(showError ? "Try again" : " ")
                    .font(.system(size: 13))
                    .foregroundColor(Color.destructive.opacity(0.8))
                    .frame(height: 16)
                    .padding(.top, 2)

                // PIN dots
                HStack(spacing: 16) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < enteredPIN.count ? Color(hex: "1C1917") : Color(hex: "E5E5E5"))
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 20)
                .offset(x: showError ? -6 : 0)
                .animation(
                    .easeInOut(duration: 0.08).repeatCount(3, autoreverses: true),
                    value: showError
                )

                Spacer().frame(height: 28)

                PINKeypad(enteredPIN: $enteredPIN, onComplete: onPinComplete)
                    .padding(.bottom, 6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: appeared)

                Spacer().frame(maxHeight: 10)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }
}

#Preview {
    PinEntryView(enteredPIN: .constant("12"), showError: .constant(false), onPinComplete: {})
}
