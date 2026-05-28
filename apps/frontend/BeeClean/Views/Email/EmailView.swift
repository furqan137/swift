import SwiftUI
import GoogleSignIn

// MARK: - Email View (Entry Point)
struct EmailView: View {
    let showsBackButton: Bool

    @StateObject private var authService = AuthService.shared
    @State private var hasRefreshedToken = false

    init(showsBackButton: Bool = true) {
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                EmailCleanerView(showsBackButton: showsBackButton)
                    .task {
                        // Refresh token once in the background — don't block the UI
                        if !hasRefreshedToken {
                            await refreshTokenQuietly()
                            hasRefreshedToken = true
                        }
                    }
            } else {
                EmailSignInPrompt(onSuccess: {
                    IndexingService.shared.startIfNeeded()
                })
            }
        }
    }

    private func refreshTokenQuietly() async {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else { return }
        do {
            let refreshedUser = try await currentUser.refreshTokensIfNeeded()
            let freshToken = refreshedUser.accessToken.tokenString
            await authService.updateBackendTokenPublic(freshToken)
        } catch {
            print("[EmailView] Token refresh failed: \(error)")
        }
    }
}

#Preview {
    EmailView()
        .preferredColorScheme(.light)
}
