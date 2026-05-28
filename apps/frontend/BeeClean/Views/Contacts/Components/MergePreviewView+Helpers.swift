import SwiftUI
import Contacts

extension MergePreviewView {

    // MARK: - Helpers

    func completenessScore(_ c: AppContact) -> Int {
        var score = c.phoneNumbers.count + c.emails.count
        if c.hasName { score += 1 }
        if !c.organizationName.isEmpty { score += 1 }
        if c.hasThumbnail { score += 1 }
        return score
    }

    func combinedPhoneStrings(from contacts: [AppContact]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for c in contacts {
            for phone in c.phoneNumbers {
                let key = normalizePhone(phone)
                if key.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                out.append(phone)
            }
        }
        return out.joined(separator: " • ")
    }

    func uniquePhoneCount(from contacts: [AppContact]) -> Int {
        var seen = Set<String>()
        for c in contacts {
            for phone in c.phoneNumbers {
                let key = normalizePhone(phone)
                if !key.isEmpty { seen.insert(key) }
            }
        }
        return seen.count
    }

    func uniqueEmailCount(from contacts: [AppContact]) -> Int {
        var seen = Set<String>()
        for c in contacts {
            for email in c.emails {
                let key = email.lowercased().trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { seen.insert(key) }
            }
        }
        return seen.count
    }
}

