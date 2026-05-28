import SwiftUI

// MARK: - Email Category
// Mirrors src/data/emailData.ts
enum EmailCategory: String, CaseIterable, Identifiable {
    case primary = "Primary"
    case social = "Social"
    case promotions = "Promotions"
    case updates = "Updates"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .primary: return "tray.full.fill"
        case .social: return "person.2.fill"
        case .promotions: return "tag.fill"
        case .updates: return "bell.fill"
        }
    }

    var color: Color {
        switch self {
        case .primary: return .categoryBlue
        case .social: return .categoryBlue
        case .promotions: return .categoryPurple
        case .updates: return .categoryGreen
        }
    }

    /// Map a `GmailCategory.id` (lowercase identifier like "primary",
    /// "promotions") to the matching enum case. Used by the Progress
    /// BreakdownCard email segmentation: every email trash sites
    /// passes its `GmailCategory.id` via this helper so the activity
    /// log entry can be tagged with the correct sub-category.
    /// Returns nil for ids we don't have a leaf for (e.g., "forums",
    /// "spam"); those fall into the unsegmented Email bucket.
    static func fromGmailId(_ id: String) -> EmailCategory? {
        switch id.lowercased() {
        case "primary":    return .primary
        case "social":     return .social
        case "promotions": return .promotions
        case "updates":    return .updates
        default:           return nil
        }
    }
}

// MARK: - Email Item Model
struct EmailItem: Identifiable, Hashable {
    let id: String
    let sender: String
    let senderEmail: String
    let subject: String
    let preview: String
    let date: Date
    let category: EmailCategory
    let avatarHue: Double
    let unread: Bool
    
    var initials: String {
        let components = sender.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

