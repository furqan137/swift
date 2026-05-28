import Foundation

// MARK: - QuotaService
//
// HTTP client for the server-side deletion quota system. Calls three
// endpoints on the Express backend to check, consume, and grant
// deletion quotas. Authenticates using the same JWT token the app
// uses for all other backend calls (stored in UserDefaults).

@MainActor
final class QuotaService: ObservableObject {

    static let shared = QuotaService()

    /// Base URL — uses BackendConfig so it auto-switches between
    /// localhost (simulator), local IP (device), and production.
    private var baseURL: String { BackendConfig.baseURL }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Check Quota

    /// Fetches the current quota state for the authenticated user.
    /// Creates the user's quota row on first call (server-side upsert).
    func checkQuota() async throws -> UserQuota {
        let data = try await request(endpoint: "quota/check", method: "GET")
        return try decoder.decode(UserQuota.self, from: data)
    }

    // MARK: - Consume Free Deletes

    /// Atomically decrements the user's free delete allowance.
    /// - Parameter count: Number of free deletes to consume (must be > 0).
    func consumeFreeDeletes(count: Int) async throws -> ConsumeDeletesResponse {
        let body: [String: Any] = ["count": count]
        let data = try await request(endpoint: "quota/consume", method: "POST", body: body)
        return try decoder.decode(ConsumeDeletesResponse.self, from: data)
    }

    // MARK: - Grant Ad Reward

    /// Grants +25 deletes after a successful rewarded ad view.
    /// Returns 429 if the user has hit the daily ad cap (15).
    func grantAdReward() async throws -> GrantAdRewardResponse {
        let data = try await request(endpoint: "quota/grant-ad-reward", method: "POST")
        return try decoder.decode(GrantAdRewardResponse.self, from: data)
    }

    // MARK: - Section-Aware Consume

    /// Atomically consumes quota for a specific section.
    func consumeSectionQuota(section: String, count: Int) async throws -> ConsumeDeletesResponse {
        let body: [String: Any] = ["section": section, "count": count]
        let data = try await request(endpoint: "quota/consume-section", method: "POST", body: body)
        return try decoder.decode(ConsumeDeletesResponse.self, from: data)
    }

    // MARK: - Section-Aware Ad Reward

    /// Grants an ad reward for a specific section. Returns the reward amount.
    func grantSectionAdReward(section: String) async throws -> SectionAdRewardResponse {
        let body: [String: Any] = ["section": section]
        let data = try await request(endpoint: "quota/grant-ad-reward-section", method: "POST", body: body)
        return try decoder.decode(SectionAdRewardResponse.self, from: data)
    }

    // MARK: - Private

    /// Reads the auth token from UserDefaults (same key as AuthService).
    private var authToken: String? {
        UserDefaults.standard.string(forKey: "auth_token")
    }

    private func request(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw QuotaServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach auth token (same JWT used by all other backend calls)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 429:
            throw QuotaServiceError.adCapReached
        case 401, 403:
            throw QuotaServiceError.unauthorized
        default:
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorBody["error"] as? String {
                throw QuotaServiceError.serverError(message)
            }
            throw QuotaServiceError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Errors

    enum QuotaServiceError: LocalizedError {
        case invalidURL
        case invalidResponse
        case unauthorized
        case adCapReached
        case serverError(String)
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid quota service URL."
            case .invalidResponse: return "Invalid server response."
            case .unauthorized: return "Authentication required."
            case .adCapReached: return "You've reached today's ad limit."
            case .serverError(let msg): return msg
            case .httpError(let code): return "Server error (\(code))."
            }
        }
    }
}
