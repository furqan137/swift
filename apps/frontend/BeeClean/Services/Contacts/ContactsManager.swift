import Foundation
import Contacts
import ContactsUI

// MARK: - Contacts Errors
enum ContactsError: LocalizedError {
    case contactNotFound
    case noContactsToExport
    case exportFailed(String)
    case permissionDenied
    case unmodifiableContact

    var errorDescription: String? {
        switch self {
        case .contactNotFound: return "Contact no longer exists on this device."
        case .noContactsToExport: return "No contacts to export."
        case .exportFailed(let reason): return "Export failed: \(reason)"
        case .permissionDenied: return "Contacts permission is required."
        case .unmodifiableContact: return "One or more contacts can't be modified (read-only or removed)."
        }
    }
}

// MARK: - Authorization Helpers
/// Centralized auth-status helpers. Treats iOS 18+ `.limited` as access-granted
/// while remaining safe to compile under the iOS 17 deployment target.
extension CNAuthorizationStatus {
    /// True when the app may read contacts — `.authorized` always, plus `.limited` on iOS 18+.
    /// `.limited` is iOS-only (rawValue 4); we match by rawValue to stay portable
    /// across the Swift Concurrency `Sendable` checks and macOS-incompatible enum cases.
    var grantsContactAccess: Bool {
        if self == .authorized { return true }
        if #available(iOS 18.0, *), self.rawValue == 4 { return true }
        return false
    }
}

// MARK: - Contacts Manager (Pure Service Layer — No UI State)
/// All CNContactStore operations live here. No @Published, no ObservableObject.
/// The ViewModel layer observes and drives UI.
final class ContactsManager {
    static let shared = ContactsManager()

    private let store = CNContactStore()

    static let fetchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNamePrefixKey as CNKeyDescriptor,
        CNContactNameSuffixKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactDepartmentNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactSocialProfilesKey as CNKeyDescriptor,
        CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactDatesKey as CNKeyDescriptor,
        // Note: CNContactNoteKey requires com.apple.developer.contacts.notes entitlement
        CNContactRelationsKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactTypeKey as CNKeyDescriptor,
        CNContactVCardSerialization.descriptorForRequiredKeys(),
        // CNContactViewController has its own private set of required
        // keys (separate from the vCard descriptor). Without it,
        // `CNContactViewController(forUnknownContact:)` calls
        // `[CNContact assertKeysAreAvailable:]` and aborts with
        // `objc_exception_throw → SIGABRT` the moment the user taps
        // the merge-preview row. Verified via crash report
        // `BeeClean-2026-05-05-025818.ips` (lastExceptionBacktrace
        // points at `+[CNContactViewController viewControllerForUnknownContact:]`).
        CNContactViewController.descriptorForRequiredKeys(),
    ]

    // MARK: - Permissions

    func permissionStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    var hasAccess: Bool {
        permissionStatus().grantsContactAccess
    }

    func requestAccess() async throws -> Bool {
        // Apple's API contract: returns `false` if the user denies, throws on system errors.
        // On iOS 18+ a "limited" grant returns `true` here, but we re-check status anyway
        // because callers rely on `permissionStatus()` after the prompt resolves.
        let granted = try await store.requestAccess(for: .contacts)
        return granted || hasAccess
    }

    // MARK: - Fetch All Contacts (background thread)

    func fetchAllContacts() async throws -> [CNContact] {
        // Re-check permission at the call site — iOS will throw an opaque error if we
        // try to enumerate without access (common cause of silent failures on TestFlight
        // when status flipped between view appear and fetch).
        guard hasAccess else { throw ContactsError.permissionDenied }

        let keys = Self.fetchKeys
        let contactStore = self.store

        return try await Task.detached {
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var contacts: [CNContact] = []
            try contactStore.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
            return contacts
        }.value
    }

    // MARK: - Merge Contacts

    func mergeContacts(primary: CNContact, duplicates: [CNContact]) throws {
        guard !duplicates.isEmpty else { return }
        guard let mutable = primary.mutableCopy() as? CNMutableContact else {
            throw ContactsError.contactNotFound
        }

        for dup in duplicates {
            // Phones — deduplicate by normalized digits (recompute per-phone to handle intra-dup dupes)
            for phone in dup.phoneNumbers {
                let existingPhones = Set(mutable.phoneNumbers.map { normalizePhone($0.value.stringValue) })
                let normalized = normalizePhone(phone.value.stringValue)
                if !existingPhones.contains(normalized) && !normalized.isEmpty {
                    mutable.phoneNumbers.append(phone)
                }
            }
            // Emails — deduplicate by lowercased
            let existingEmails = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })
            for email in dup.emailAddresses where !existingEmails.contains((email.value as String).lowercased()) {
                mutable.emailAddresses.append(email)
            }
            // Postal addresses — full key including state, zip, country
            let existingAddrs = Set(mutable.postalAddresses.map { postalKey($0.value) })
            for addr in dup.postalAddresses {
                if !existingAddrs.contains(postalKey(addr.value)) {
                    mutable.postalAddresses.append(addr)
                }
            }
            // URLs — deduplicate by lowercased
            let existingURLs = Set(mutable.urlAddresses.map { ($0.value as String).lowercased() })
            for url in dup.urlAddresses where !existingURLs.contains((url.value as String).lowercased()) {
                mutable.urlAddresses.append(url)
            }
            // Social profiles — deduplicate by service+username
            let existingSocials = Set(mutable.socialProfiles.map { socialKey($0.value) })
            for profile in dup.socialProfiles where !existingSocials.contains(socialKey(profile.value)) {
                mutable.socialProfiles.append(profile)
            }
            // Instant messages — deduplicate by service+username
            let existingIMs = Set(mutable.instantMessageAddresses.map { imKey($0.value) })
            for im in dup.instantMessageAddresses where !existingIMs.contains(imKey(im.value)) {
                mutable.instantMessageAddresses.append(im)
            }
            // Relations — deduplicate by name+label
            let existingRelations = Set(mutable.contactRelations.map { "\($0.label ?? "")-\($0.value.name)".lowercased() })
            for rel in dup.contactRelations where !existingRelations.contains("\(rel.label ?? "")-\(rel.value.name)".lowercased()) {
                mutable.contactRelations.append(rel)
            }
            // Dates — deduplicate by label+value
            let existingDateKeys = Set(mutable.dates.map { "\($0.label ?? "nil")-\($0.value)" })
            for date in dup.dates {
                let key = "\(date.label ?? "nil")-\(date.value)"
                if !existingDateKeys.contains(key) {
                    mutable.dates.append(date)
                }
            }
            // Scalar fields — fill from duplicate if primary is empty
            if mutable.givenName.isEmpty && !dup.givenName.isEmpty {
                mutable.givenName = dup.givenName
            }
            if mutable.familyName.isEmpty && !dup.familyName.isEmpty {
                mutable.familyName = dup.familyName
            }
            if mutable.organizationName.isEmpty && !dup.organizationName.isEmpty {
                mutable.organizationName = dup.organizationName
            }
            if mutable.departmentName.isEmpty && !dup.departmentName.isEmpty {
                mutable.departmentName = dup.departmentName
            }
            if mutable.jobTitle.isEmpty && !dup.jobTitle.isEmpty {
                mutable.jobTitle = dup.jobTitle
            }
            if mutable.middleName.isEmpty && !dup.middleName.isEmpty {
                mutable.middleName = dup.middleName
            }
            if mutable.namePrefix.isEmpty && !dup.namePrefix.isEmpty {
                mutable.namePrefix = dup.namePrefix
            }
            if mutable.nameSuffix.isEmpty && !dup.nameSuffix.isEmpty {
                mutable.nameSuffix = dup.nameSuffix
            }
            if mutable.nickname.isEmpty && !dup.nickname.isEmpty {
                mutable.nickname = dup.nickname
            }

            if mutable.imageData == nil && dup.imageData != nil {
                mutable.imageData = dup.imageData
            }
            if mutable.birthday == nil && dup.birthday != nil {
                mutable.birthday = dup.birthday
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        for dup in duplicates {
            guard let dupMutable = dup.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(dupMutable)
        }
        try store.execute(saveRequest)
    }

    private func postalKey(_ addr: CNPostalAddress) -> String {
        "\(addr.street)\(addr.city)\(addr.state)\(addr.postalCode)\(addr.country)".lowercased()
    }

    private func socialKey(_ profile: CNSocialProfile) -> String {
        "\(profile.service)-\(profile.username)".lowercased()
    }

    private func imKey(_ im: CNInstantMessageAddress) -> String {
        "\(im.service)-\(im.username)".lowercased()
    }

    #if DEBUG
    // MARK: - Mock Data (DEBUG only)
    //
    // Seeds a small set of contacts that share phones / emails so the
    // union-find duplicate detector groups them together. Every mock
    // contact carries the same `note` sentinel so `removeMockDuplicates()`
    // can find and delete just the seeded data without touching the
    // user's real address book. Production builds never see this.

    /// Sentinel URL written into every mock contact's `urlAddresses` so
    /// the cleanup helper can find them again. We use a URL (not a note)
    /// because `CNContactNoteKey` requires the
    /// `com.apple.developer.contacts.notes` entitlement, which this
    /// build does not request. Bumping the path component invalidates
    /// older seeded data — useful if the mock schema below changes.
    static let mockSentinelURL = "beeclean-mock://v1"

    /// Seeds 5 duplicate-prone groups + 1 control contact (12 contacts
    /// total). Each group's members share at least one phone OR email
    /// so the duplicate detector links them. Returns the number of
    /// contacts actually written.
    @discardableResult
    func seedMockDuplicates() throws -> Int {
        // Build 12 mutable contacts grouped into the scenarios the
        // duplicate detector should catch:
        //   • Same phone, slight name variation     (Aashman ×2)
        //   • Same email, different phones          (Adam Chen ×2)
        //   • Same phone, casing/spacing variations (Adi Singh ×3)
        //   • Same email, near-duplicate name       (Sarah Martinez ×2)
        //   • Same phone, different formatting      (Aidan Guo ×2)
        //   • Control: no duplicates                (Maya Rivera ×1)
        let mocks: [(given: String, family: String, phones: [String], emails: [String])] = [
            // Group 1 — phone match
            ("Aashman", "Patel",     ["+1 (469) 988-2029"], []),
            ("aashman", "patel",     ["4699882029"],        []),

            // Group 2 — email match
            ("Adam",    "Chen",      ["+1 (505) 273-3189"], ["adam.chen@example.com"]),
            ("Adam",    "Chen",      ["+1 (469) 667-8369"], ["adam.chen@example.com"]),

            // Group 3 — phone match × 3
            ("Adi",     "Singh",     ["+1 (248) 982-3183"], []),
            ("ADI",     "Singh",     ["2489823183"],        []),
            ("Adi  ",   "Singh",     ["+12489823183"],      []),

            // Group 4 — email match (near-duplicate name)
            ("Sarah",   "Martinez",  ["+1 (415) 555-7821"], ["sarah.m@example.com"]),
            ("Sara",    "Martinez",  ["+1 (415) 555-9904"], ["sarah.m@example.com"]),

            // Group 5 — phone match (Aidan Guo flow from the user's
            // reference screenshot)
            ("Aidan",   "Guo",       ["+1 (778) 886-8113"], []),
            ("Aidan",   "Guo",       ["+1 (646) 853-3818", "+17788868113"], []),

            // Control — should NOT appear in duplicates
            ("Maya",    "Rivera",    ["+1 (303) 555-2206"], ["maya.rivera@example.com"]),
        ]

        let saveRequest = CNSaveRequest()
        for mock in mocks {
            let c = CNMutableContact()
            c.givenName = mock.given
            c.familyName = mock.family
            c.phoneNumbers = mock.phones.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile,
                               value: CNPhoneNumber(stringValue: $0))
            }
            c.emailAddresses = mock.emails.map {
                CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
            }
            // Sentinel URL — invisible in the basic Contacts UI but
            // queryable when we go to remove these. Avoids needing the
            // `note` entitlement.
            c.urlAddresses = [
                CNLabeledValue(label: CNLabelOther, value: Self.mockSentinelURL as NSString)
            ]
            saveRequest.add(c, toContainerWithIdentifier: nil)
        }
        try store.execute(saveRequest)
        return mocks.count
    }

    /// Removes EVERY contact whose URL list contains the mock sentinel.
    /// Returns the count actually deleted. Safe to run when nothing has
    /// been seeded — returns 0.
    @discardableResult
    func removeMockDuplicates() throws -> Int {
        // CNContact has no predicate that filters on URL value, so we
        // enumerate the address book and match in Swift. Debug-only,
        // a few thousand contacts at worst on a dev simulator.
        let keys: [CNKeyDescriptor] = [
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor
        ]
        let fetch = CNContactFetchRequest(keysToFetch: keys)
        var matches: [CNContact] = []
        try store.enumerateContacts(with: fetch) { contact, _ in
            let hasSentinel = contact.urlAddresses.contains { entry in
                (entry.value as String) == Self.mockSentinelURL
            }
            if hasSentinel { matches.append(contact) }
        }
        guard !matches.isEmpty else { return 0 }

        let saveRequest = CNSaveRequest()
        for contact in matches {
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(mutable)
        }
        try store.execute(saveRequest)
        return matches.count
    }
    #endif

    // MARK: - Delete Contacts

    func deleteContacts(_ contacts: [CNContact]) throws {
        guard !contacts.isEmpty else { return }
        let saveRequest = CNSaveRequest()
        var queued = 0
        for contact in contacts {
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(mutable)
            queued += 1
        }
        // If every contact failed to copy (read-only iCloud, deleted under us),
        // surface that instead of pretending the delete succeeded with 0 ops.
        guard queued > 0 else { throw ContactsError.unmodifiableContact }
        try store.execute(saveRequest)
    }

    // MARK: - Export as vCard

    func exportAsVCard(_ contacts: [CNContact]) throws -> URL {
        guard !contacts.isEmpty else { throw ContactsError.noContactsToExport }
        let data = try CNContactVCardSerialization.data(with: contacts)
        let name: String
        if contacts.count == 1, let c = contacts.first {
            let n = "\(c.givenName)_\(c.familyName)".trimmingCharacters(in: .whitespaces)
            name = n.isEmpty ? "Contact" : Self.sanitizeFilename(n)
        } else {
            name = "Contacts_\(contacts.count)"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).vcf")
        try data.write(to: url)
        return url
    }

    func backupAll(_ contacts: [CNContact]) throws -> URL {
        guard !contacts.isEmpty else { throw ContactsError.noContactsToExport }
        let data = try CNContactVCardSerialization.data(with: contacts)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeeClean_Backup_\(fmt.string(from: Date())).vcf")
        try data.write(to: url)
        return url
    }

    /// Sanitize a string for safe use in file names.
    private static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: illegal).joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespaces)
    }

}

// MARK: - ContactsServiceProtocol Conformance
extension ContactsManager: ContactsServiceProtocol {
    func loadContacts() async throws -> [AppContact] {
        try await fetchAllContacts().map { AppContact(from: $0) }
    }

    func merge(primary: AppContact, duplicates: [AppContact]) async throws {
        guard let primaryCN = primary.cnContact else { return }
        let dupeCNs = duplicates.compactMap { $0.cnContact }
        guard !dupeCNs.isEmpty else { return }
        try mergeContacts(primary: primaryCN, duplicates: dupeCNs)
    }

    func remove(_ contacts: [AppContact]) async throws {
        let cnContacts = contacts.compactMap { $0.cnContact }
        guard !cnContacts.isEmpty else { return }
        try deleteContacts(cnContacts)
    }

    func export(_ contacts: [AppContact]) throws -> URL {
        let cnContacts = contacts.compactMap { $0.cnContact }
        return try exportAsVCard(cnContacts)
    }

    func backup(_ contacts: [AppContact]) throws -> URL {
        let cnContacts = contacts.compactMap { $0.cnContact }
        return try backupAll(cnContacts)
    }
}

