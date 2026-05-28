import Foundation

// MARK: - Contact Backup Model

struct ContactBackup: Identifiable, Codable {
    let id: String
    let contactCount: Int
    let createdAt: Date

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd MMM yyyy"
        return fmt.string(from: createdAt)
    }

    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: createdAt)
    }
}

// MARK: - Backup Contact (serializable contact data)
 
struct BackupContact: Codable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let givenName: String
    let familyName: String
    let organizationName: String
    let jobTitle: String
    let phoneNumbers: [LabeledValue]
    let emailAddresses: [LabeledValue]
    let note: String

    var fullName: String {
        let name = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return organizationName.isEmpty ? "No Name" : organizationName
        }
        return name
    }

    var initials: String {
        let first = givenName.prefix(1)
        let last = familyName.prefix(1)
        let result = "\(first)\(last)".uppercased()
        return result.isEmpty ? "?" : result
    }

    var sortLetter: String {
        let name = fullName.uppercased()
        guard let first = name.first, first.isLetter else { return "#" }
        return String(first)
    }

    struct LabeledValue: Codable {
        let label: String
        let value: String
    }
}
