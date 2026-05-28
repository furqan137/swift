import SwiftUI
import RevenueCatUI

// MARK: - ProNagView
//
// Non-blocking interrupt sheet shown after every 3rd ad in a session.
// Encourages the user to upgrade to Pro to skip ads entirely.
// Has a close button — never blocks the user.

struct ProNagView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Crown icon
            ZStack {
                Circle()
                    .fill(Color.categoryAmber.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .blur(radius: 8)

                Image(systemName: "crown.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.categoryAmber)
            }

            VStack(spacing: 10) {
                Text("Skip the Ads")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("Get Pro for unlimited deletes.\nNo ads, no daily limits.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "71717A"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Go Pro badge
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.categoryAmber)
                Text(BCLoc.goPro.tr)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.categoryAmber)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.categoryAmber.opacity(0.1))
            .clipShape(Capsule())

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Analytics.track("paywall_shown", properties: ["trigger": "pro_nag"])
                    showPaywall = true
                } label: {
                    Text("See Pro Plans")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.categoryAmber)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Button {
                    Analytics.track("paywall_dismissed", properties: ["trigger": "pro_nag"])
                    dismiss()
                } label: {
                    Text(BCLoc.notNow.tr)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(hex: "F4F5FA").ignoresSafeArea())
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in
                    showPaywall = false
                    dismiss()
                }
                .onRestoreCompleted { _ in
                    showPaywall = false
                    dismiss()
                }
        }
        .onAppear {
            Analytics.track("pro_nag_shown")
        }
    }
}
