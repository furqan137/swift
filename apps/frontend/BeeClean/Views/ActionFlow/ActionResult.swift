import Foundation

// MARK: - Action Result

/// Captures the outcome of a major cleanup action (delete, compress, merge,
/// clean) so the summary screen can display action-specific stats.
struct ActionResult {
    let section: GateSection
    let actionType: ActionType
    let itemsProcessed: Int
    let bytesFreed: Int64?
    let bytesSaved: Int64?
    let originalBytes: Int64?
    let compressedBytes: Int64?
    let timestamp: Date
    let breakdown: [String: Int]?
    let topSenders: [String]?

    enum ActionType: String {
        case delete, compress, merge, clean
    }

    // MARK: - Display Helpers

    var heroText: String {
        switch (section, actionType) {
        case (.photos, .delete):
            return "\(itemsProcessed) photo\(itemsProcessed == 1 ? "" : "s") deleted"
        case (.videos, .delete):
            return "\(itemsProcessed) video\(itemsProcessed == 1 ? "" : "s") deleted"
        case (.email, .clean):
            return "\(itemsProcessed) email\(itemsProcessed == 1 ? "" : "s") cleaned"
        case (.contacts, .merge):
            return "\(itemsProcessed) contact\(itemsProcessed == 1 ? "" : "s") merged"
        case (.compress, .compress):
            if let saved = bytesSaved {
                return "\(formatBytes(saved)) saved"
            }
            return "\(itemsProcessed) file\(itemsProcessed == 1 ? "" : "s") compressed"
        default:
            return "\(itemsProcessed) item\(itemsProcessed == 1 ? "" : "s") processed"
        }
    }

    var subtitleText: String {
        switch (section, actionType) {
        case (.photos, .delete), (.videos, .delete):
            if let freed = bytesFreed {
                return "\(formatBytes(freed)) freed up"
            }
            return "Your library is lighter"
        case (.email, .clean):
            return "Your inbox is lighter"
        case (.contacts, .merge):
            return "Your contact list is cleaner"
        case (.compress, .compress):
            if let count = itemsProcessed as Int? {
                let noun = section == .videos ? "video" : "photo"
                return "\(count) \(noun)\(count == 1 ? "" : "s") compressed"
            }
            return "Files compressed"
        default:
            return "All done"
        }
    }

    var savingsPercent: Int? {
        guard let original = originalBytes, let compressed = compressedBytes,
              original > 0, compressed < original else { return nil }
        return Int((1.0 - Double(compressed) / Double(original)) * 100)
    }
}
