import Foundation

extension EmailService {
    // MARK: - Unsubscribe
    func unsubscribe(from email: String, deleteExisting: Bool = true) async -> Bool {
        do {
            let body: [String: Any] = ["senderEmail": email, "deleteExisting": deleteExisting]
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let _: UnsubscribeResponse = try await authenticatedRequest(
                endpoint: "/email/unsubscribe", method: "POST", body: jsonData
            )
            if let idx = senders.firstIndex(where: { $0.email == email }) {
                senders.remove(at: idx)
            }
            return true
        } catch {
            print("Unsubscribe error: \(error)")
            return false
        }
    }
}
