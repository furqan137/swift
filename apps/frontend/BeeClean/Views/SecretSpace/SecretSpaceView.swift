import SwiftUI
import Photos

// MARK: - Secret Space View
struct SecretSpaceView: View {
    @State private var isUnlocked = false
    @State private var enteredPIN = ""
    @State private var showError = false
    @State private var showChangePIN = false

    // PIN setup state
    @State private var isCreatingPIN = false
    @State private var createStep = 0          // 0 = enter new, 1 = confirm
    @State private var newPINCandidate = ""

    @AppStorage("secretPIN") private var savedPIN = ""
    @AppStorage("hasCreatedPIN") private var hasCreatedPIN = false

    @StateObject private var vault = SecretVaultManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var needsPINSetup: Bool {
        !hasCreatedPIN || savedPIN.isEmpty
    }

    /// Skip PIN if vault is empty — nothing to protect
    private var vaultIsEmpty: Bool {
        vault.items.isEmpty
    }

    var body: some View {
        ZStack {
            Color(hex: "F2F2F7").ignoresSafeArea()

            if isUnlocked || vaultIsEmpty || needsPINSetup {
                // Show library — PIN creation happens via the red lock button inside
                SecretLibraryView(showChangePIN: $showChangePIN, onLock: {
                    isUnlocked = false
                    enteredPIN = ""
                    dismiss()
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
            } else {
                // Returning user: enter PIN
                ZStack(alignment: .topLeading) {
                    PinEntryView(
                        enteredPIN: $enteredPIN,
                        showError: $showError,
                        onPinComplete: checkPIN
                    )

                    backButton
                }
                .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .animation(.easeOut(duration: 0.3), value: isUnlocked)
        .sheet(isPresented: $showChangePIN) {
            ChangePINView(currentPIN: savedPIN) { newPIN in
                savedPIN = newPIN
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, newPhase in
            // Auto-lock when app goes to background (only if vault has items)
            if newPhase != .active && !vaultIsEmpty && hasCreatedPIN {
                withAnimation(.easeOut(duration: 0.2)) {
                    isUnlocked = false
                    enteredPIN = ""
                }
            }
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            HapticManager.shared.arrowNudge(.backward)
            isUnlocked = false
            enteredPIN = ""
            dismiss()
        } label: {
            // Same back-chevron spec as EmailCleanerHeader / Photos /
            // Videos / Compress — one shared button across every
            // Quick Access destination.
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
                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.leading, 20)
        .padding(.top, 12)
    }

    // MARK: - PIN Check

    private func checkPIN() {
        if enteredPIN == savedPIN {
            HapticManager.shared.impact(.medium)
            withAnimation {
                isUnlocked = true
            }
        } else {
            HapticManager.shared.notify(.error)
            withAnimation(.easeOut(duration: 0.2)) {
                showError = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                enteredPIN = ""
                showError = false
            }
        }
    }

    // MARK: - PIN Setup

    private func handlePINSetupComplete() {
        if createStep == 0 {
            // User entered new PIN, now confirm it
            newPINCandidate = enteredPIN
            enteredPIN = ""
            withAnimation(.easeOut(duration: 0.25)) {
                createStep = 1
            }
        } else {
            // Confirm step
            if enteredPIN == newPINCandidate {
                // Match — save and unlock
                savedPIN = newPINCandidate
                hasCreatedPIN = true
                HapticManager.shared.impact(.medium)
                withAnimation {
                    isUnlocked = true
                }
            } else {
                // Mismatch — shake and retry confirm
                HapticManager.shared.notify(.error)
                withAnimation(.easeOut(duration: 0.2)) {
                    showError = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    enteredPIN = ""
                    showError = false
                }
            }
        }
    }
}

// MARK: - PIN Setup View (First-Time)

struct PINSetupView: View {
    @Binding var step: Int
    @Binding var enteredPIN: String
    @Binding var showError: Bool
    let onComplete: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(maxHeight: 20)

                // Shield icon
                Circle()
                    .fill(Color(hex: "F5F5F4"))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: step == 0 ? "lock.shield" : "lock.rotation")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(showError ? .destructive : Color(hex: "A1A1AA"))
                            .contentTransition(.symbolEffect(.replace))
                    )
                    .opacity(appeared ? 1 : 0)

                Text(step == 0 ? "Create a Passcode" : "Confirm Passcode")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .padding(.top, 14)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: step)

                Text(showError ? "Doesn't match — try again" : (step == 0 ? "You'll need this to access your vault" : "Enter it one more time"))
                    .font(.system(size: 13))
                    .foregroundColor(showError ? Color.destructive.opacity(0.8) : Color(hex: "A1A1AA"))
                    .frame(height: 16)
                    .padding(.top, 4)
                    .animation(.easeOut(duration: 0.2), value: step)

                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color(hex: "1C1917") : Color(hex: "E5E5E5"))
                            .frame(width: i == step ? 20 : 6, height: 4)
                    }
                }
                .padding(.top, 16)
                .animation(.easeOut(duration: 0.3), value: step)

                // PIN dots
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPIN.count ? Color(hex: "1C1917") : Color(hex: "E5E5E5"))
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 24)
                .offset(x: showError ? -6 : 0)
                .animation(
                    .easeInOut(duration: 0.08).repeatCount(3, autoreverses: true),
                    value: showError
                )

                Spacer().frame(height: 28)

                PINKeypad(enteredPIN: $enteredPIN, onComplete: onComplete)
                    .padding(.bottom, 6)
                    .opacity(appeared ? 1 : 0)

                Spacer().frame(maxHeight: 10)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }
}

#Preview {
    SecretSpaceView()
        .preferredColorScheme(.light)
}
