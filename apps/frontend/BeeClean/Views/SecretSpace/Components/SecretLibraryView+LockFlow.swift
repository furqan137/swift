import SwiftUI

@MainActor
extension SecretLibraryView {

    // MARK: - Lock Flow View
    // lockStep: 0 = create PIN, 1 = confirm PIN, 2 = "locked" result
    //           10 = enter PIN to unlock, 11 = "PIN removed" result
    var lockFlowView: some View {
        let isResult = lockStep == 2 || lockStep == 11
        let titleText: String = {
            switch lockStep {
            case 0: return "Create New PIN"
            case 1: return "Confirm PIN"
            case 2: return "Your Space is Locked"
            case 10: return "Enter PIN to Turn It Off"
            case 11: return "PIN Removed"
            default: return ""
            }
        }()

        return ZStack {
            BitepalCanvas()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button {
                        showLockFlow = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "78716C"))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(Color(hex: "EDEAE7"))
                            )
                    }

                    Spacer()

                    Text("Secret Library")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))

                    Spacer()

                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                if isResult {
                    // Result card — checkmark uses the same ink color as
                    // the rest of the lock flow so the screen reads as
                    // one neutral, high-end surface (no blue mirror of
                    // the Cleanup palette).
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))

                        Text(titleText)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))
                    }
                    .frame(width: 240)
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 20, y: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    // PIN entry — bigger, neutral ink instead of the
                    // bright blue. Fill is full ink, idle ring is a
                    // soft neutral so the dots read as filled/empty
                    // without competing with Cleanup's blue palette.
                    VStack(spacing: 28) {
                        Text(titleText)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .tracking(-0.2)

                        HStack(spacing: 18) {
                            ForEach(0..<4, id: \.self) { i in
                                let filled = i < lockPIN.count
                                Circle()
                                    .fill(filled ? Color(hex: "1C1917") : Color.clear)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                filled ? Color(hex: "1C1917") : Color(hex: "C4C0BA"),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .scaleEffect(filled ? 1.08 : 1.0)
                                    .animation(.spring(response: 0.22, dampingFraction: 0.62), value: filled)
                            }
                        }
                        .offset(x: lockShake)
                    }
                }

                Spacer()

                if !isResult {
                    PINKeypad(enteredPIN: $lockPIN) {
                        handleLockPINComplete()
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: lockStep)
    }

    func handleLockPINComplete() {
        if lockStep == 0 {
            // Create: save candidate, go to confirm
            lockPINCandidate = lockPIN
            lockPIN = ""
            withAnimation { lockStep = 1 }
        } else if lockStep == 1 {
            // Confirm: check match
            if lockPIN == lockPINCandidate {
                savedPIN = lockPINCandidate
                hasCreatedPIN = true
                HapticManager.shared.notify(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lockStep = 2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    showLockFlow = false
                }
            } else {
                triggerPINShake()
            }
        } else if lockStep == 10 {
            // Unlock: verify existing PIN
            if lockPIN == savedPIN {
                savedPIN = ""
                hasCreatedPIN = false
                HapticManager.shared.notify(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lockStep = 11 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    showLockFlow = false
                }
            } else {
                triggerPINShake()
            }
        }
    }

    func triggerPINShake() {
        HapticManager.shared.notify(.error)
        withAnimation(.default) { lockShake = 12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.3)) { lockShake = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lockPIN = "" }
    }

}
