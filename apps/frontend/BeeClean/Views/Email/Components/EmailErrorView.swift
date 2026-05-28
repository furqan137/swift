import SwiftUI

struct EmailErrorView: View {
    let error: String
    let isBackendOffline: Bool
    let needsSignIn: Bool
    let isAuthenticated: Bool
    let onRetry: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(isBackendOffline ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: isBackendOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isBackendOffline ? .red : .orange)
            }

            VStack(spacing: 8) {
                Text(isBackendOffline ? BCLoc.backendOffline.tr : error)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.foreground)

                Text(isBackendOffline ? BCLoc.backendOfflineSubtitle.tr : error)
                    .font(.system(size: 14))
                    .foregroundColor(.foregroundSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text(BCLoc.tryAgain.tr)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.foreground)
                        .cornerRadius(14)
                }

                if needsSignIn || !isAuthenticated {
                    Button(action: onSignIn) {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 16))
                            Text(BCLoc.signInWithGoogle.tr)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [Color(hex: "4285F4"), Color(hex: "3B73DB")], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                        .shadow(color: Color(hex: "4285F4").opacity(0.25), radius: 10)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
