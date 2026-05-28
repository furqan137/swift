import Foundation
import UIKit

/// Lightweight service for reporting feature usage stats to the backend.
/// Fire-and-forget — failures are logged but never block the UI.
class StatsService {
    static let shared = StatsService()
    private let baseURL = BackendConfig.baseURL

    private init() {}

    // MARK: - Compression Stats

    func logCompression(
        assetId: String,
        originalBytes: Int64,
        compressedBytes: Int64,
        compressionLevel: String,
        codec: String,
        durationSeconds: Double?,
        compressionTimeSeconds: Double?,
        resolution: String?,
        success: Bool,
        errorMessage: String? = nil
    ) {
        var body: [String: Any] = [
            "assetId": assetId,
            "originalBytes": originalBytes,
            "compressedBytes": compressedBytes,
            "compressionLevel": compressionLevel.lowercased(),
            "codec": codec,
            "success": success,
            "deviceModel": deviceModel(),
            "osVersion": UIDevice.current.systemVersion,
        ]
        if let d = durationSeconds { body["durationSeconds"] = d }
        if let t = compressionTimeSeconds { body["compressionTimeSeconds"] = t }
        if let r = resolution { body["resolution"] = r }
        if let e = errorMessage { body["errorMessage"] = e }

        fire(endpoint: "/compress/stats", body: body)
    }

    // Blurry photos + long videos no longer report to the backend — kept
    // state lives on-device in LocalKeptStore, and deletion happens via
    // PhotoKit. The previous /cleanup/* endpoints and their supporting
    // tables were removed.

    // MARK: - Contacts Stats

    func logContactAction(
        action: String,
        contactCount: Int,
        duplicateGroupsMerged: Int? = nil
    ) {
        var body: [String: Any] = [
            "action": action,
            "contactCount": contactCount,
        ]
        if let g = duplicateGroupsMerged { body["duplicateGroupsMerged"] = g }

        fire(endpoint: "/contacts/stats", body: body)
    }

    // MARK: - Private

    private func fire(endpoint: String, body: [String: Any]) {
        Task { @MainActor in
            guard let token = AuthService.shared.getAuthToken() else { return }
            self.sendRequest(endpoint: endpoint, body: body, token: token)
        }
    }

    private func sendRequest(endpoint: String, body: [String: Any], token: String) {
        Task.detached(priority: .utility) {
            do {
                guard let url = URL(string: "\(self.baseURL)\(endpoint)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    print("[Stats] \(endpoint) failed: HTTP \(http.statusCode)")
                }
            } catch {
                print("[Stats] \(endpoint) error: \(error.localizedDescription)")
            }
        }
    }

    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }
}
