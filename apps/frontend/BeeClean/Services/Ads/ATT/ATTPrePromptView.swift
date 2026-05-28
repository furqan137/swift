import SwiftUI

// MARK: - ATT Pre-Prompt View
//
// Custom explanation screen shown once before iOS's ATT system dialog.
// Explains why tracking helps keep the app free, then triggers the
// real system prompt on "Continue". Dismisses itself after the system
// prompt completes regardless of the user's choice.

struct ATTPrePromptView: View {
    @ObservedObject private var attManager = ATTManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Shield icon
            ZStack {
                Circle()
                    .fill(Color.categoryAmber.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundColor(.categoryAmber)
            }

            VStack(spacing: 12) {
                Text("Help Keep BeeClean Free")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.center)

                Text("We use ads to keep BeeClean free for everyone. Allowing tracking helps us show you more relevant ads.\n\nYou can still use the app if you decline.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "71717A"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await attManager.requestAuthorization()
                        dismiss()
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.categoryAmber)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Button {
                    // Mark as shown so it doesn't re-appear, but skip the
                    // system prompt. The user can enable tracking later in
                    // Settings → Privacy.
                    UserDefaults.standard.set(true, forKey: "att_prompt_shown")
                    dismiss()
                } label: {
                    Text(BCLoc.notNow.tr)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(hex: "F4F5FA").ignoresSafeArea())
    }
}
