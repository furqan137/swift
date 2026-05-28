import SwiftUI

// MARK: - PIN Keypad
struct PINKeypad: View {
    @Binding var enteredPIN: String
    let onComplete: () -> Void

    private let keys: [(String, String)] = [
        ("1", ""), ("2", "A B C"), ("3", "D E F"),
        ("4", "G H I"), ("5", "J K L"), ("6", "M N O"),
        ("7", "P Q R S"), ("8", "T U V"), ("9", "W X Y Z"),
        ("", ""), ("0", ""), ("⌫", "")
    ]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20)
        ], spacing: 14) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                if key.0.isEmpty {
                    Color.clear.frame(height: 76)
                } else {
                    KeypadButton(digit: key.0, letters: key.1) {
                        HapticManager.shared.impact(.light)
                        handleKey(key.0)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !enteredPIN.isEmpty {
                enteredPIN.removeLast()
            }
        } else if enteredPIN.count < 4 {
            enteredPIN += key
            if enteredPIN.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Keypad Button
private struct KeypadButton: View {
    let digit: String
    let letters: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if digit == "⌫" {
                Image(systemName: "delete.left")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(Color(hex: "78716C"))
                    .frame(height: 76)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 2) {
                    Text(digit)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "1C1917"))

                    if !letters.isEmpty {
                        Text(letters)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "78716C"))
                            .kerning(1.6)
                    } else {
                        Text(" ")
                            .font(.system(size: 10))
                    }
                }
                .frame(width: 76, height: 76)
                .background(
                    Circle()
                        .fill(Color.white)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "1C1917").opacity(0.06), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GlassKeypadPressStyle())
    }
}

// MARK: - Glass Press Style
struct GlassKeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

typealias KeypadPressStyle = GlassKeypadPressStyle
typealias KeypadScaleButtonStyle = GlassKeypadPressStyle

#Preview {
    PINKeypad(enteredPIN: .constant("12"), onComplete: {})
        .background(Color.white)
}
