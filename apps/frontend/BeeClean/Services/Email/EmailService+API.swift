import Foundation

extension EmailService {
    // MARK: - API Helpers
    func authenticatedRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 20,
        isRetry: Bool = false
    ) async throws -> T {
        guard let token = AuthService.shared.getAuthToken() else {
            throw EmailError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw EmailError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmailError.invalidResponse
        }
        
        // If we get a 401 and this isn't already a retry, refresh the Google token and try again
        if httpResponse.statusCode == 401 && !isRetry {
            if let errorBody = try? JSONDecoder().decode(TokenExpiredResponse.self, from: data),
               errorBody.error == "token_expired" || errorBody.error == "Access token required" {
                print("Google token expired, refreshing...")
                if let _ = await AuthService.shared.refreshGoogleToken() {
                    return try await authenticatedRequest(
                        endpoint: endpoint,
                        method: method,
                        body: body,
                        timeout: timeout,
                        isRetry: true
                    )
                }
            }
            throw EmailError.notAuthenticated
        }
        
        if httpResponse.statusCode >= 400 {
            // Try to surface a friendly message based on what the server said
            if let errorBody = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
                if errorBody.error.contains("quota") || errorBody.error.contains("rate") || httpResponse.statusCode == 429 {
                    throw EmailError.serverError("Gmail is rate-limiting us. Try again in a moment.")
                }
                throw EmailError.serverError(errorBody.error)
            }
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                throw EmailError.serverError("Gmail is rate-limiting us. Try again in a moment.")
            }
            throw EmailError.serverError("Couldn't load emails. Try again in a moment.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Decode failed — likely an unexpected response shape from the backend.
            // Show a friendly message instead of "data couldn't be read because it is missing."
            print("[EmailService] Decode error for \(endpoint): \(error)")
            throw EmailError.serverError("Couldn't load emails. Try again in a moment.")
        }
    }

    private struct ServerErrorEnvelope: Decodable {
        let error: String
    }
    
    // MARK: - Incremental Refresh (History API)
    // (`lastHistoryId` @Published moved back to main class declaration —
    // extensions cannot hold stored properties.)

    /// Lightweight refresh: uses Gmail History API to detect new/deleted emails
    /// and update category counts without re-fetching all messages.
    /// Returns true if there were changes.
    @discardableResult
    func refreshEmailState(scope: String = "inbox") async -> Bool {
        do {
            var endpoint = "/email/messages/refresh?scope=\(scope)"
            if let historyId = lastHistoryId {
                endpoint += "&historyId=\(historyId)"
            }
            let response: RefreshResponse = try await authenticatedRequest(endpoint: endpoint)

            // Update historyId for next incremental call
            lastHistoryId = response.historyId

            // Update total email count
            if let total = response.totalEmails {
                totalEmailCount = total
            }

            // Update category counts if provided
            if let updatedCategories = response.categories {
                for updated in updatedCategories {
                    if let idx = categories.firstIndex(where: { $0.id == updated.id }) {
                        categories[idx].count = updated.count
                    }
                }
            }

            // If there are changes, invalidate affected message caches
            if response.hasChanges {
                // New messages mean the first page of every category could be stale
                for key in messageCache.keys {
                    messageCache[key]?.fetchedAt = Date.distantPast // Force re-fetch on next access
                }
                print("[EmailService] Refresh detected changes: +\(response.newMessageIds?.count ?? 0) -\(response.deletedMessageIds?.count ?? 0)")
            }

            return response.hasChanges
        } catch {
            print("[EmailService] Refresh error: \(error)")
            return false
        }
    }

}
