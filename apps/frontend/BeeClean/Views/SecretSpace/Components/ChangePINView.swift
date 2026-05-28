import SwiftUI

// MARK: - Change PIN View
struct ChangePINView: View {
    let currentPIN: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var enteredPIN = ""
    @State private var newPIN = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft cool-gray surface — matches the BitePal nav-bar
                // family used by the rest of the review screens, so the
                // Change Passcode flow feels like part of the same chrome
                // family instead of a stark white modal.
                Color(hex: "F4F5FA").ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Step progress
                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i <= step ? Color(hex: "3B82F6") : Color(hex: "E5E7EB"))
                                .frame(width: i == step ? 24 : 8, height: 4)
                                .animation(.easeOut(duration: 0.3), value: step)
                        }
                    }
                    .padding(.bottom, 28)

                    // Title + subtitle
                    VStack(spacing: 8) {
                        Text(stepTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .contentTransition(.opacity)

                        if showError {
                            Text(step == 0 ? "Wrong passcode" : "Doesn't match")
                                .font(.system(size: 14))
                                .foregroundColor(.destructive)
                        } else {
                            Text("Step \(step + 1) of 3")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "A1A1AA"))
                        }
                    }

                    Spacer()
                        .frame(height: 32)

                    // PIN dots with glow
                    HStack(spacing: 22) {
                        ForEach(0..<4) { index in
                            ZStack {
                                if index < enteredPIN.count {
                                    Circle()
                                        .fill(Color(hex: "3B82F6").opacity(0.18))
                                        .frame(width: 22, height: 22)
                                        .blur(radius: 5)
                                }

                                Circle()
                                    .fill(
                                        index < enteredPIN.count
                                            ? Color(hex: "3B82F6")
                                            : (showError ? Color.destructive.opacity(0.3) : Color.white)
                                    )
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                index < enteredPIN.count
                                                    ? Color.clear
                                                    : (showError ? Color.destructive.opacity(0.5) : Color.black.opacity(0.08)),
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .scaleEffect(index < enteredPIN.count ? 1.0 : 0.85)
                            .animation(.easeOut(duration: 0.1), value: enteredPIN.count)
                        }
                    }
                    .offset(x: showError ? -6 : 0)
                    .animation(
                        .easeInOut(duration: 0.08).repeatCount(3, autoreverses: true),
                        value: showError
                    )

                    // Push the keypad up — previously the flexible Spacer
                    // sandwiched it against the bottom edge with only 20pt
                    // of breathing room, which made the digits feel buried.
                    // A fixed 36pt gap above + 56pt below lifts the keypad
                    // into the visual middle of the screen.
                    Spacer().frame(height: 36)

                    PINKeypad(enteredPIN: $enteredPIN, onComplete: handlePINComplete)
                        .padding(.bottom, 56)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
                ToolbarItem(placement: .principal) {
                    Text("Change Passcode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Enter current passcode"
        case 1: return "Enter new passcode"
        default: return "Confirm new passcode"
        }
    }

    private func handlePINComplete() {
        switch step {
        case 0:
            if enteredPIN == currentPIN {
                withAnimation(.easeOut(duration: 0.25)) { step = 1 }
                enteredPIN = ""
            } else {
                triggerError()
            }
        case 1:
            newPIN = enteredPIN
            withAnimation(.easeOut(duration: 0.25)) { step = 2 }
            enteredPIN = ""
        default:
            if enteredPIN == newPIN {
                HapticManager.shared.notify(.success)
                onSave(newPIN)
                dismiss()
            } else {
                triggerError()
            }
        }
    }

    private func triggerError() {
        HapticManager.shared.notify(.error)
        showError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            enteredPIN = ""
            showError = false
        }
    }
}

#Preview {
    ChangePINView(currentPIN: "1234", onSave: { _ in })
}
