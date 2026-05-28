import SwiftUI

// MARK: - Contact Category
enum ContactCategory: String, Identifiable {
    case duplicates
    case incomplete
    case backups
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: return "Duplicates"
        case .incomplete: return "Incomplete Contacts"
        case .backups: return "Backups"
        case .all: return "All Contacts"
        }
    }
}
