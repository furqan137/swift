import Foundation
import Contacts

// MARK: - App Contact Model
/// Lightweight, value-type wrapper around CNContact for use in ViewModels and Views.
/// The underlying CNContact is retained for operations requiring it (merge, delete, export, detail display).
struct AppContact: Identifiable, Hashable {
    let id: String
    let givenName: String
    let familyName: String
    let fullName: String
    let organizationName: String
    let jobTitle: String
    let phoneNumbers: [String]
    let emails: [String]
    let thumbnailData: Data?
    let hasThumbnail: Bool
    let birthday: DateComponents?

    /// The underlying CNContact for rich operations (merge, delete, labeled values, etc.)
    let cnContact: CNContact?

    var hasPhone: Bool { !phoneNumbers.isEmpty }
    var hasEmail: Bool { !emails.isEmpty }
    var hasName: Bool { !givenName.isEmpty || !familyName.isEmpty || !organizationName.isEmpty }

    var initials: String {
        let first = givenName.prefix(1)
        let last = familyName.prefix(1)
        let result = "\(first)\(last)".uppercased()
        return result.isEmpty ? "?" : result
    }

    /// Digits-only phone numbers for duplicate matching
    var normalizedPhones: [String] {
        phoneNumbers.map { normalizePhone($0) }
    }

    // MARK: - Init from CNContact
    init(from contact: CNContact) {
        self.id = contact.identifier
        self.givenName = contact.givenName.trimmingCharacters(in: .whitespaces)
        self.familyName = contact.familyName.trimmingCharacters(in: .whitespaces)
        self.organizationName = contact.organizationName
        self.jobTitle = contact.jobTitle

        let name = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
        self.fullName = name.isEmpty
            ? (contact.organizationName.isEmpty ? "No Name" : contact.organizationName)
            : name

        self.phoneNumbers = contact.phoneNumbers.map { $0.value.stringValue }
        self.emails = contact.emailAddresses.map { $0.value as String }
        self.thumbnailData = contact.thumbnailImageData
        self.hasThumbnail = contact.imageDataAvailable
        self.birthday = contact.birthday
        self.cnContact = contact
    }

    // MARK: - Hashable / Equatable (by identifier only)
    static func == (lhs: AppContact, rhs: AppContact) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Phone Normalization (free function for reuse)
func normalizePhone(_ phone: String) -> String {
    phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
}
