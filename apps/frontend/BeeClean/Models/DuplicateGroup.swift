import Foundation

// MARK: - Confidence Level
enum DuplicateConfidence: String, Comparable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var score: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    static func < (lhs: DuplicateConfidence, rhs: DuplicateConfidence) -> Bool {
        lhs.score < rhs.score
    }

    /// Derive confidence from a numeric match score (0-100)
    static func from(score: Int) -> DuplicateConfidence {
        if score >= 70 { return .high }
        if score >= 40 { return .medium }
        return .low
    }
}

// MARK: - Match Reason (what caused the match)
struct MatchReason: Hashable {
    enum Kind: String, Hashable {
        case exactName = "Same name"
        case similarName = "Similar name"
        case phone = "Same phone"
        case email = "Same email"
        case organization = "Same company"
        case birthday = "Same birthday"
        case photo = "Same photo"
    }

    let kind: Kind
    let detail: String // e.g. the shared phone number or name
}

// MARK: - Merge Preview (what the merge will produce)
struct MergePreview {
    let primaryContact: AppContact
    let keptPhones: [String]           // all unique phones after merge
    let removedPhones: [String]        // duplicate phones that will be deduped
    let keptEmails: [String]
    let removedEmails: [String]
    let bestName: String
    let bestOrganization: String
    let bestJobTitle: String
    let hasPhoto: Bool
    let totalFieldsKept: Int
    let totalFieldsRemoved: Int
}

// MARK: - Duplicate Group Model
struct DuplicateGroup: Identifiable {
    let id: String
    let name: String
    let contacts: [AppContact]
    let confidence: DuplicateConfidence
    let matchReasons: Set<MatchReason>

    var count: Int { contacts.count }

    /// The contact with the most data — best candidate for primary
    var bestPrimary: AppContact {
        contacts.max { contactCompleteness($0) < contactCompleteness($1) } ?? contacts[0]
    }

    init(name: String, contacts: [AppContact], confidence: DuplicateConfidence = .high, matchReasons: Set<MatchReason> = []) {
        // Invariant: a duplicate group with no contacts is meaningless and
        // would crash in `bestPrimary` (which falls back to `contacts[0]`).
        // Fail fast at construction so the bug surfaces where it's caused
        // rather than at the call site that depends on it.
        precondition(!contacts.isEmpty, "DuplicateGroup must contain at least one contact")
        self.name = name
        self.contacts = contacts
        self.confidence = confidence
        self.matchReasons = matchReasons
        self.id = contacts.map(\.id).sorted().joined(separator: "-")
    }

    /// Generate a preview of what the merged contact will look like
    func buildMergePreview() -> MergePreview {
        let primary = bestPrimary

        // Collect all unique phones
        var allPhones: [String] = []
        var seenNormalized = Set<String>()
        var removedPhones: [String] = []

        for contact in contacts {
            for phone in contact.phoneNumbers {
                let norm = normalizePhone(phone)
                guard norm.count >= 7 else { continue }
                let key = String(norm.suffix(min(norm.count, 10)))
                if seenNormalized.contains(key) {
                    removedPhones.append(phone)
                } else {
                    seenNormalized.insert(key)
                    allPhones.append(phone)
                }
            }
        }

        // Collect all unique emails
        var allEmails: [String] = []
        var seenEmails = Set<String>()
        var removedEmails: [String] = []

        for contact in contacts {
            for email in contact.emails {
                let key = email.lowercased().trimmingCharacters(in: .whitespaces)
                if seenEmails.contains(key) {
                    removedEmails.append(email)
                } else {
                    seenEmails.insert(key)
                    allEmails.append(email)
                }
            }
        }

        // Best scalar values
        let bestName = contacts.map(\.fullName).max { $0.count < $1.count } ?? primary.fullName
        let bestOrg = contacts.map(\.organizationName).filter { !$0.isEmpty }.first ?? ""
        let bestJob = contacts.map(\.jobTitle).filter { !$0.isEmpty }.first ?? ""
        let hasPhoto = contacts.contains { $0.hasThumbnail }

        return MergePreview(
            primaryContact: primary,
            keptPhones: allPhones,
            removedPhones: removedPhones,
            keptEmails: allEmails,
            removedEmails: removedEmails,
            bestName: bestName,
            bestOrganization: bestOrg,
            bestJobTitle: bestJob,
            hasPhoto: hasPhoto,
            totalFieldsKept: allPhones.count + allEmails.count + (bestOrg.isEmpty ? 0 : 1) + (bestJob.isEmpty ? 0 : 1),
            totalFieldsRemoved: removedPhones.count + removedEmails.count
        )
    }
}

// MARK: - Contact Completeness Score
/// Higher = more complete contact, better primary candidate
func contactCompleteness(_ contact: AppContact) -> Int {
    var score = 0
    if !contact.givenName.isEmpty { score += 2 }
    if !contact.familyName.isEmpty { score += 2 }
    score += contact.phoneNumbers.count * 3
    score += contact.emails.count * 3
    if !contact.organizationName.isEmpty { score += 2 }
    if !contact.jobTitle.isEmpty { score += 1 }
    if contact.hasThumbnail { score += 4 }
    if contact.birthday != nil { score += 2 }
    return score
}
