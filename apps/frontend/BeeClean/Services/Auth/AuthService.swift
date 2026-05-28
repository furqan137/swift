import Foundation
import GoogleSignIn
import GoogleSignInSwift

// MARK: - API Models
struct AuthResponse: Codable {
    let token: String
    let isNewUser: Bool?
    let user: UserData
}

struct UserData: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Auth Service
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: UserData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True while the cold-launch token validation is still in flight.
    /// Views that gate their UI on `isAuthenticated` (login wall vs.
    /// app) should treat `isHydrating == true` as "show a splash,
    /// don't decide yet" — otherwise a stored token that turns out
    /// invalid causes a brief flash of logged-in UI before the
    /// validation completes and signs the user out. False once
    /// `validateToken()` resolves either way, or immediately if no
    /// stored token existed at launch.
    @Published private(set) var isHydrating: Bool = false
    
    private let baseURL = BackendConfig.baseURL
    private let tokenKey = "auth_token"
    private let userKey = "current_user"

    /// Single-flight gate for `ensureValidSession()`. Concurrent
    /// authenticated requests that all hit an expired JWT each used to
    /// kick off their own refresh — and a slow loser could
    /// `clearToken()` after a fast winner already restored auth,
    /// silently signing the user out. Now every caller awaits the same
    /// in-flight refresh and observes the same outcome.
    ///
    /// Stored alongside a UUID token because `Task` is a value type
    /// (no `===` identity) — the token lets the completion handler
    /// clear the gate only if no fresher refresh has replaced it.
    private var inFlightSessionCheck: (token: UUID, task: Task<SessionStatus, Never>)?
    
    init() {
        // Check for existing token on launch
        loadStoredUser()
        
        // Check if user is already signed in with Google
        restorePreviousSignIn()
    }
    
    // MARK: - Token Management
    private func getStoredToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
    
    private func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
    
    private func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }
    
    private func storeUser(_ user: UserData) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userKey)
        }
    }
    
    private func loadStoredUser() {
        guard let token = getStoredToken(),
              let userData = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(UserData.self, from: userData)
        else { return }

        // Hydrate the user object immediately so anything that needs
        // the email/avatar pre-validation has it, but keep
        // `isAuthenticated` FALSE until the backend confirms the
        // stored token is still valid. Without this, a stored token
        // that the backend has since revoked produced a one-frame
        // flash of the logged-in UI before validation flipped it
        // back to false. `isHydrating` lets the view layer show a
        // splash for that ~200ms instead of guessing.
        self.currentUser = user
        self.isHydrating = true

        Task { [weak self] in
            await self?.validateToken(token)
            // Either branch of validateToken clears isAuthenticated
            // appropriately — only thing left is to flip the hydrate
            // flag off so the view layer can resolve its conditional.
            await MainActor.run { [weak self] in
                self?.isHydrating = false
            }
        }
    }
    
    func getAuthToken() -> String? {
        getStoredToken()
    }
    
    // MARK: - Google Sign In
    private func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor in
                if let user = user {
                    await self?.handleGoogleUser(user)
                }
            }
        }
    }
    
    // Gmail scopes needed for email cleaning features
    private let gmailScopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.labels",
        "https://www.googleapis.com/auth/gmail.settings.basic"
    ]
    
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        // Pick the foregrounded, active scene — not just "any scene". On
        // iPad or Stage Manager the app can have multiple connected scenes,
        // and `connectedScenes.first` may return a background one. Presenting
        // the Google Sign-In sheet on a background window's root does nothing
        // visible and, in some iOS releases, trips an assertion. We now look
        // for `.foregroundActive` first and fall back to `.foregroundInactive`
        // (user just resumed the app) before giving up.
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first { $0.activationState == .foregroundInactive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        // Key window is more reliable than `windows.first` — the latter can
        // be a hidden helper window (e.g. iPad's volume HUD) on some devices.
        let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
            ?? windowScene?.windows.first
        guard let rootViewController = keyWindow?.rootViewController else {
            errorMessage = "Unable to get root view controller"
            isLoading = false
            return
        }

        // Walk past any already-presented modal so the sheet lands on the
        // top-most controller; otherwise Google's SDK raises "attempt to
        // present X on Y whose view is not in the window hierarchy."
        var presenter: UIViewController = rootViewController
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        
        do {
            // Request Gmail scopes so the access token can access Gmail API
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: gmailScopes
            )
            await handleGoogleUser(result.user)
        } catch {
            errorMessage = error.localizedDescription
            print("Google sign-in error: \(error)")
        }
        
        isLoading = false
    }
    
    private func handleGoogleUser(_ user: GIDGoogleUser) async {
        // Always refresh tokens first to guarantee a fresh access token
        do {
            let refreshedUser = try await user.refreshTokensIfNeeded()
            guard let idToken = refreshedUser.idToken?.tokenString else {
                errorMessage = "Failed to get ID token"
                return
            }
            let accessToken = refreshedUser.accessToken.tokenString
            print("[Auth] Sending fresh access token to backend")
            await signInWithGoogleToken(idToken: idToken, accessToken: accessToken)
        } catch {
            // Fallback to existing tokens
            guard let idToken = user.idToken?.tokenString else {
                errorMessage = "Failed to get ID token"
                return
            }
            let accessToken = user.accessToken.tokenString
            print("[Auth] Token refresh failed, using existing token")
            await signInWithGoogleToken(idToken: idToken, accessToken: accessToken)
        }
    }
    
    // MARK: - Sign In with ID Token (from GoogleSignIn SDK)
    func signInWithGoogleToken(idToken: String, accessToken: String?) async {
        isLoading = true
        errorMessage = nil

        do {
            guard let url = URL(string: "\(baseURL)/auth/google/ios") else {
                throw AuthError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = ["idToken": idToken]
            if let accessToken = accessToken {
                body["accessToken"] = accessToken
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                storeToken(authResponse.token)
                storeUser(authResponse.user)
                currentUser = authResponse.user
                isAuthenticated = true
            } else {
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                throw AuthError.serverError(errorResponse?.error ?? "Authentication failed")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Google sign-in error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Validate Token
    private func validateToken(_ token: String) async {
        do {
            guard let url = URL(string: "\(baseURL)/auth/me") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Token invalid, clear it
                clearToken()
                isAuthenticated = false
                currentUser = nil
                return
            }
            
            struct MeResponse: Codable {
                let user: UserData
            }
            
            let meResponse = try JSONDecoder().decode(MeResponse.self, from: data)
            currentUser = meResponse.user
            storeUser(meResponse.user)
            isAuthenticated = true
        } catch {
            // Server unreachable — trust the local token so an offline
            // launch doesn't sign the user out. Previously `loadStoredUser`
            // set `isAuthenticated = true` eagerly and this catch was a
            // no-op; now that the eager set is gone (so views don't
            // flash logged-in for a revoked token), we re-instate the
            // offline-trust here explicitly.
            print("[Auth] Token validation failed (likely network) — trusting local state")
            isAuthenticated = true
        }
    }
    
    // MARK: - Refresh Google Token

    /// Single-flight gate for `refreshGoogleToken()`. Concurrent email
    /// API calls used to each catch their own 401 and each fire their
    /// own `refreshTokensIfNeeded()`. The slow refresh would land
    /// after the fast one and overwrite the backend-stored access
    /// token with a stale value, then in-flight callers retrying
    /// with that stale token would hard-fail. Now every caller
    /// awaits the same in-flight refresh and observes the same
    /// outcome — only one refresh hits Google + the backend per
    /// token-expiry event.
    ///
    /// UUID-paired with the Task so the completion handler only
    /// clears the gate when no fresher refresh has replaced it —
    /// same pattern `inFlightSessionCheck` already uses.
    private var inFlightGoogleRefresh: (token: UUID, task: Task<String?, Never>)?

    /// Refreshes the Google access token and updates the backend.
    /// Returns the new access token, or nil if refresh failed.
    func refreshGoogleToken() async -> String? {
        if let existing = inFlightGoogleRefresh {
            return await existing.task.value
        }

        let myToken = UUID()
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
                print("[Auth] No Google user available for token refresh")
                return nil
            }

            do {
                let user = try await currentUser.refreshTokensIfNeeded()
                let newAccessToken = user.accessToken.tokenString
                await self.updateBackendToken(newAccessToken)
                return newAccessToken
            } catch {
                print("[Auth] Token refresh failed")
                return nil
            }
        }
        inFlightGoogleRefresh = (token: myToken, task: task)
        let result = await task.value
        // Clear the gate only if we still own the slot — a much
        // later replacement refresh shouldn't be wiped by this one.
        if inFlightGoogleRefresh?.token == myToken {
            inFlightGoogleRefresh = nil
        }
        return result
    }
    
    /// Public wrapper so views can trigger a backend token update after refreshing.
    func updateBackendTokenPublic(_ accessToken: String) async {
        await updateBackendToken(accessToken)
    }
    
    /// Sends the fresh Google access token to the backend to update the stored copy.
    private func updateBackendToken(_ accessToken: String) async {
        guard let token = getStoredToken() else { return }
        
        do {
            guard let url = URL(string: "\(baseURL)/auth/update-token") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["accessToken": accessToken]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[Auth] Backend token updated")
            }
        } catch {
            print("[Auth] Backend token update failed")
        }
    }
    
    // MARK: - Ensure Valid Session
    /// Checks if the stored JWT is valid. If not, automatically refreshes Google tokens
    /// and re-authenticates with the backend. Returns true if session is valid after the check.
    ///
    /// Call this before any feature that needs authenticated API access (e.g. email).
    enum SessionStatus {
        case valid
        case reAuthenticated
        case backendOffline
        case notSignedIn
    }
    
    func ensureValidSession() async -> SessionStatus {
        // Single-flight: if a session check is already running, every
        // concurrent caller awaits the SAME task and gets the SAME
        // verdict. Without this, two parallel API failures each
        // triggered their own re-auth, and the slow loser could
        // clobber the fast winner's restored token.
        if let inFlight = inFlightSessionCheck {
            return await inFlight.task.value
        }
        let token = UUID()
        let task = Task<SessionStatus, Never> { [weak self] in
            guard let self else { return .notSignedIn }
            return await self.performSessionCheck()
        }
        inFlightSessionCheck = (token, task)
        let result = await task.value
        // Clear the gate so the next genuine refresh starts fresh — but
        // only if the in-flight task wasn't already replaced by a newer
        // one (which could happen under heavy reentrancy). Compare by
        // token because `Task` itself is a value type without `===`.
        if inFlightSessionCheck?.token == token {
            inFlightSessionCheck = nil
        }
        return result
    }

    private func performSessionCheck() async -> SessionStatus {
        // Step 1: Do we even have a stored JWT?
        guard let storedToken = getStoredToken() else {
            // No JWT at all — try to re-auth if Google session exists
            if let googleUser = GIDSignIn.sharedInstance.currentUser {
                print("[ensureValidSession] No JWT stored, but Google user exists — re-authenticating")
                await handleGoogleUser(googleUser)
                return getStoredToken() != nil ? .reAuthenticated : .notSignedIn
            }
            print("[ensureValidSession] No JWT and no Google user — not signed in")
            return .notSignedIn
        }
        
        // Step 2: Validate the JWT against the backend
        do {
            guard let url = URL(string: "\(baseURL)/auth/me") else { return .backendOffline }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(storedToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8 // Don't hang forever if backend is down
            
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .backendOffline
            }

            if httpResponse.statusCode == 200 {
                // JWT is valid — also refresh the Google access token on the backend
                // so Gmail API calls use a fresh token
                if let googleUser = GIDSignIn.sharedInstance.currentUser {
                    do {
                        let refreshed = try await googleUser.refreshTokensIfNeeded()
                        let freshAccessToken = refreshed.accessToken.tokenString
                        await updateBackendToken(freshAccessToken)
                        print("[ensureValidSession] JWT valid, Google token refreshed")
                    } catch {
                        // Google token refresh failed — the backend token is stale.
                        // Force a full re-auth so the backend gets a fresh access token.
                        print("[ensureValidSession] Google token refresh failed, re-authenticating")
                        await handleGoogleUser(googleUser)
                        return getStoredToken() != nil ? .reAuthenticated : .notSignedIn
                    }
                } else {
                    // No Google user session — JWT is valid but we can't refresh the
                    // Google access token, which means email API calls will fail.
                    // Try to restore the Google session first.
                    print("[ensureValidSession] No Google user session, attempting restore...")
                    await withCheckedContinuation { continuation in
                        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                            Task { @MainActor in
                                if let user = user {
                                    await self?.handleGoogleUser(user)
                                }
                                continuation.resume()
                            }
                        }
                    }
                    // If we still don't have a Google session, user needs to sign in again
                    if GIDSignIn.sharedInstance.currentUser == nil {
                        print("[ensureValidSession] Could not restore Google session — needs sign-in")
                        return .notSignedIn
                    }
                }
                return .valid
            }
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // JWT expired or invalid — re-authenticate
                print("[ensureValidSession] JWT expired (status \(httpResponse.statusCode)), re-authenticating...")
                clearToken()
                
                if let googleUser = GIDSignIn.sharedInstance.currentUser {
                    await handleGoogleUser(googleUser)
                    if getStoredToken() != nil {
                        print("[ensureValidSession] Re-authenticated successfully")
                        return .reAuthenticated
                    }
                }
                
                isAuthenticated = false
                currentUser = nil
                return .notSignedIn
            }
            
            // Other error — treat as backend issue
            return .backendOffline
            
        } catch {
            // Network error — backend is probably not running
            print("[ensureValidSession] Backend unreachable: \(error.localizedDescription)")
            return .backendOffline
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        // Sign out from Google
        GIDSignIn.sharedInstance.signOut()

        // Reset RevenueCat to anonymous user
        SubscriptionService.shared.resetIdentity()

        // Clear local storage
        clearToken()
        currentUser = nil
        isAuthenticated = false
    }
    
    // MARK: - API Helpers
    func authenticatedRequest(to endpoint: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token = getStoredToken() else {
            throw AuthError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Token expired
            signOut()
            throw AuthError.tokenExpired
        }
        
        if httpResponse.statusCode >= 400 {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse?.error ?? "Request failed")
        }
        
        return data
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case notAuthenticated
    case tokenExpired
    case invalidResponse
    case backendOffline
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .invalidResponse:
            return "Invalid server response"
        case .backendOffline:
            return "Cannot reach server. Make sure the backend is running."
        case .serverError(let message):
            return message
        }
    }
}
