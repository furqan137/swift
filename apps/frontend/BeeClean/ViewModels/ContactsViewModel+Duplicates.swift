import Foundation
import Contacts
import CryptoKit

extension ContactsViewModel {
    // MARK: - Duplicate Detection (Step 3) — Confidence-Scored

    func findDuplicates() async {
        // Heavy work moved off @MainActor. With 10k+ contacts the
        // union-find + pairwise-name + edit-distance passes used to
        // stall the main thread for 2–5 seconds every reload. We
        // snapshot inputs (allContacts, the kept-group hash set) on
        // main, hand the pure computation to a detached
        // utility-priority task, and reassign the @Published result
        // when it lands back. UI stays interactive for the entire
        // duration of the scan.
        let allContacts = self.allContacts
        let keptGroupHashes = LocalKeptStore.shared.ids(in: .contactDuplicateGroups)
        let computed: [DuplicateGroup] = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
        // Union-Find for transitive grouping
        var parent: [String: String] = [:]

        func find(_ x: String) -> String {
            var root = x
            while let p = parent[root], p != root { root = p }
            var curr = x
            // Path compression — guard against any rogue id that wasn't seeded
            // into `parent` (defensive: a missing key would force-crash here).
            while curr != root {
                guard let next = parent[curr] else { return root }
                parent[curr] = root
                curr = next
            }
            return root
        }

        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for contact in allContacts {
            parent[contact.id] = contact.id
        }

        // Track WHY pairs match (for confidence scoring)
        // Key: sorted pair of contact IDs → set of match reasons
        var pairReasons: [String: Set<MatchReason>] = [:]

        func addReason(_ a: String, _ b: String, _ reason: MatchReason) {
            let key = [a, b].sorted().joined(separator: "|")
            pairReasons[key, default: []].insert(reason)
            union(a, b)
        }

        // 1. Phone matching — PRIMARY linkage.
        //
        // Index every phone under BOTH the last-10-digit key AND the
        // last-7-digit key. Last-10 is the strongest signal (matches
        // formats like "+1 616 508 8224", "616-508-8224", "(616) 508-8224"
        // → all normalize to 6165088224). Last-7 is a weaker fallback
        // that catches mixed-country-code duplicates the user has in
        // practice (e.g. a US contact saved with "1" prefix vs the same
        // person saved with "+91" by mistake — last 7 still align).
        // We dedupe via the union-find so a contact unioned by last-10
        // doesn't get unioned again under last-7 with stale weighting.
        var phoneGroups10: [String: [String]] = [:]
        var phoneGroups7: [String: [String]] = [:]
        for contact in allContacts {
            for phone in contact.normalizedPhones {
                guard phone.count >= 7 else { continue }
                let key10 = String(phone.suffix(min(phone.count, 10)))
                phoneGroups10[key10, default: []].append(contact.id)
                if phone.count >= 7 {
                    let key7 = String(phone.suffix(7))
                    phoneGroups7[key7, default: []].append(contact.id)
                }
            }
        }
        for (phone, ids) in phoneGroups10 where ids.count > 1 {
            for i in 1..<ids.count {
                addReason(ids[0], ids[i], MatchReason(kind: .phone, detail: phone))
            }
        }
        for (phone, ids) in phoneGroups7 where ids.count > 1 {
            for i in 1..<ids.count {
                addReason(ids[0], ids[i], MatchReason(kind: .phone, detail: phone))
            }
        }

        // 2. Email matching — secondary linkage. Same rationale as phone:
        // if two contacts share an email address, they're the same person.
        // Canonicalized via `canonicalizeEmail`: Gmail strips dots and
        // ignores `+suffix` aliases, so `john.doe@gmail.com`,
        // `johndoe@gmail.com`, and `john.doe+work@gmail.com` all collapse
        // to the same key. Lowercased + whitespace-trimmed for every
        // domain. This catches a real-world dup case the previous exact
        // string match was missing.
        var emailGroups: [String: [String]] = [:]
        for contact in allContacts {
            for email in contact.emails {
                guard let key = Self.canonicalizeEmail(email) else { continue }
                emailGroups[key, default: []].append(contact.id)
            }
        }
        for (email, ids) in emailGroups where ids.count > 1 {
            for i in 1..<ids.count {
                addReason(ids[0], ids[i], MatchReason(kind: .email, detail: email))
            }
        }

        // 2b. Photo-hash matching — STRONGEST single signal. If two
        // contacts have byte-identical thumbnail data, they're literally
        // the same person photographed at the same moment (the user
        // copied the contact, or a sync pulled the same image into two
        // entries). SHA256 of the raw bytes is collision-safe; we hash
        // only contacts that actually have a thumbnail.
        var photoGroups: [String: [String]] = [:]
        for contact in allContacts {
            guard let data = contact.thumbnailData, !data.isEmpty else { continue }
            let digest = SHA256.hash(data: data)
            let key = digest.compactMap { String(format: "%02x", $0) }.joined()
            photoGroups[key, default: []].append(contact.id)
        }
        for (hash, ids) in photoGroups where ids.count > 1 {
            for i in 1..<ids.count {
                addReason(ids[0], ids[i], MatchReason(kind: .photo, detail: String(hash.prefix(8))))
            }
        }

        // 3. Name matching.
        //
        // Two-pass to avoid the "common name" false-positive trap:
        //
        //   3a. Two-token+ exact name match (e.g. "John Smith") DOES union.
        //       The user's complaint was that one person stored under
        //       multiple numbers wasn't being grouped — the only signal
        //       linking them is their full name. Requiring 2+ tokens
        //       ("John Smith", not just "John") and at least one
        //       contact method per side keeps "Aaron" / "John" from
        //       collapsing every contact with that first name.
        //
        //   3b. Single-token name match (e.g. just "Aaron") stays
        //       reason-only — never a union edge.
        //
        // KEY: token-set (sorted) so "John Smith" and "Smith John"
        // (or "Smith, John" → "smith john" after period strip) hash to
        // the same bucket. Contact apps inconsistently parse Last-First
        // formats from CSV imports / iCloud sync, and the previous
        // string-equality match was missing those.
        var nameGroups: [String: [String]] = [:]
        for contact in allContacts {
            let normalized = Self.normalizeNameForMatching(contact.fullName)
            guard normalized.count >= 2, normalized != "no name" else { continue }
            let key = Self.tokenSetKey(normalized)
            nameGroups[key, default: []].append(contact.id)
        }
        let contactById = Dictionary(uniqueKeysWithValues: allContacts.map { ($0.id, $0) })
        for (name, ids) in nameGroups where ids.count > 1 {
            let tokenCount = name.split(separator: " ").count
            for i in 0..<ids.count {
                for j in (i+1)..<ids.count {
                    let a = ids[i], b = ids[j]
                    let alreadyLinked = find(a) == find(b)
                    if tokenCount >= 2 && !alreadyLinked {
                        // Only union when BOTH contacts have at least one
                        // contact method — otherwise we're grouping two
                        // bare-name placeholders together which the
                        // "incomplete contacts" pass already handles.
                        if let ca = contactById[a], let cb = contactById[b],
                           (ca.hasPhone || ca.hasEmail),
                           (cb.hasPhone || cb.hasEmail) {
                            addReason(a, b, MatchReason(kind: .exactName, detail: name))
                            continue
                        }
                    }
                    if alreadyLinked {
                        let key = [a, b].sorted().joined(separator: "|")
                        pairReasons[key, default: []].insert(
                            MatchReason(kind: .exactName, detail: name)
                        )
                    }
                }
            }
        }

        // 3c. Birthday match within already-linked groups. Same birthday
        // (month + day, year ignored — Apple Contacts often omits year)
        // is a strong second signal that turns a phone-only or email-only
        // link from MEDIUM into HIGH confidence in the scoring step
        // below. Birthday alone never unions — too easy to coincide on a
        // 1-in-365 chance — so this stays reason-only.
        for i in 0..<allContacts.count {
            guard let bdayA = allContacts[i].birthday,
                  let monthA = bdayA.month, let dayA = bdayA.day else { continue }
            for j in (i+1)..<allContacts.count {
                guard let bdayB = allContacts[j].birthday,
                      monthA == bdayB.month, dayA == bdayB.day else { continue }
                let a = allContacts[i].id, b = allContacts[j].id
                guard find(a) == find(b) else { continue }
                let key = [a, b].sorted().joined(separator: "|")
                pairReasons[key, default: []].insert(
                    MatchReason(kind: .birthday, detail: String(format: "%02d/%02d", monthA, dayA))
                )
            }
        }

        // 4. Organization matching (only if name also matches something in group)
        var orgGroups: [String: [String]] = [:]
        for contact in allContacts {
            let org = contact.organizationName.lowercased().trimmingCharacters(in: .whitespaces)
            guard org.count >= 3 else { continue }
            orgGroups[org, default: []].append(contact.id)
        }
        // Don't union on org alone — too many false positives.
        // Only add as a reason if contacts are already linked.

        // 5. Fuzzy name match WITHIN already-linked groups — bumps a
        // group's confidence when the names differ only by a typo or
        // diacritic ("Aditi"/"Aditi ", "Sarah"/"Sara"). Edit-distance ≤ 2
        // and length ≥ 4 keeps this from firing on tiny initials. Like
        // step 3, this is REASON ONLY — never unions.
        let normalizedNames: [(id: String, name: String)] = allContacts.compactMap { c in
            let n = Self.normalizeNameForMatching(c.fullName)
            guard n.count >= 4, n != "no name" else { return nil }
            return (c.id, n)
        }
        for i in 0..<normalizedNames.count {
            for j in (i+1)..<normalizedNames.count {
                let a = normalizedNames[i], b = normalizedNames[j]
                guard find(a.id) == find(b.id) else { continue }
                if a.name == b.name { continue } // exactName already covered
                if Self.editDistance(a.name, b.name, max: 2) <= 2 {
                    let key = [a.id, b.id].sorted().joined(separator: "|")
                    pairReasons[key, default: []].insert(
                        MatchReason(kind: .similarName, detail: "\(a.name) ≈ \(b.name)")
                    )
                }
            }
        }

        // 5. Collect groups with confidence scoring
        let contactMap = Dictionary(uniqueKeysWithValues: allContacts.map { ($0.id, $0) })
        var rootToIDs: [String: [String]] = [:]
        for contact in allContacts {
            let root = find(contact.id)
            rootToIDs[root, default: []].append(contact.id)
        }

        // `keptGroupHashes` was captured from @MainActor up at the
        // top of `findDuplicates()` — re-reading it here would call
        // @MainActor code from this detached task and would not
        // compile. Use the captured set directly.

        var groups: [DuplicateGroup] = []
        for (_, ids) in rootToIDs where ids.count > 1 {
            let contacts = ids.compactMap { contactMap[$0] }
            guard let first = contacts.first else { continue }

            let groupHash = LocalKeptStore.contactGroupHash(contactIds: contacts.map { $0.id })
            if keptGroupHashes.contains(groupHash) { continue }

            // Aggregate all match reasons for this group
            var groupReasons = Set<MatchReason>()
            for i in 0..<ids.count {
                for j in (i+1)..<ids.count {
                    let key = [ids[i], ids[j]].sorted().joined(separator: "|")
                    if let reasons = pairReasons[key] {
                        groupReasons.formUnion(reasons)
                    }
                }
            }

            // Check if contacts share organization
            let orgs = Set(contacts.map { $0.organizationName.lowercased().trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 })
            if orgs.count == 1, let org = orgs.first {
                groupReasons.insert(MatchReason(kind: .organization, detail: org))
            }

            // Score confidence based on match signals.
            //
            // Photo-hash is the strongest single signal — byte-identical
            // thumbnails are the same person. Birthday is a strong
            // booster (1-in-365 random collision). Multi-signal still
            // wins; e.g. phone + email + name reads as HIGH regardless.
            let hasNameMatch = groupReasons.contains { $0.kind == .exactName || $0.kind == .similarName }
            let hasPhoneMatch = groupReasons.contains { $0.kind == .phone }
            let hasEmailMatch = groupReasons.contains { $0.kind == .email }
            let hasPhotoMatch = groupReasons.contains { $0.kind == .photo }
            let hasBirthdayMatch = groupReasons.contains { $0.kind == .birthday }

            let signalCount = (hasNameMatch ? 1 : 0)
                + (hasPhoneMatch ? 1 : 0)
                + (hasEmailMatch ? 1 : 0)
                + (hasPhotoMatch ? 1 : 0)
                + (hasBirthdayMatch ? 1 : 0)

            let confidence: DuplicateConfidence
            if hasPhotoMatch {
                // Same thumbnail bytes = same person, no ambiguity.
                confidence = .high
            } else if signalCount >= 2 {
                // Two or more signals (name+phone, phone+email, etc.) = high.
                confidence = .high
            } else if hasPhoneMatch || hasEmailMatch {
                // Phone or email alone = medium (could be shared device/account).
                confidence = .medium
            } else if hasNameMatch {
                // Name alone = medium (common names like "John Smith").
                confidence = .medium
            } else {
                confidence = .low
            }

            groups.append(DuplicateGroup(
                name: first.fullName,
                contacts: contacts,
                confidence: confidence,
                matchReasons: groupReasons
            ))
        }

        // Sort: high confidence first, then by name
        return groups.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.name.lowercased() < $1.name.lowercased()
        }
        }.value
        duplicateGroups = computed
    }

    /// Normalize a name for duplicate matching:
    /// - Fold diacritics (é→e, ñ→n)
    /// - Lowercase
    /// - Strip common prefixes/suffixes (Dr., Jr., III, etc.)
    /// - Collapse whitespace
    // `nonisolated` so the nonisolated `normalizeNameForMatching` helper
    // (called from inside the detached duplicate-detection task) can read
    // these without tripping Swift 6's "main-actor-isolated property
    // accessed from nonisolated context" warning. Both sets are
    // immutable string collections — Sendable by construction.
    nonisolated private static let namePrefixes: Set<String> = ["dr", "mr", "mrs", "ms", "prof", "sir", "rev"]
    nonisolated private static let nameSuffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "phd", "md", "esq", "dds", "dvm"]

    /// Bounded Levenshtein distance — early-aborts the moment the running
    /// distance exceeds `max`, so it stays cheap inside the duplicate
    /// detection inner loop. Used to flag near-duplicate names like
    /// "Aditi" vs "Aditi " (trailing space) within already-linked groups.
    nonisolated static func editDistance(_ a: String, _ b: String, max: Int) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if abs(m - n) > max { return max + 1 }
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            var rowMin = i
            for j in 1...n {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                curr[j] = Swift.min(
                    Swift.min(curr[j-1] + 1, prev[j] + 1),
                    prev[j-1] + cost
                )
                rowMin = Swift.min(rowMin, curr[j])
            }
            if rowMin > max { return max + 1 }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    /// Canonicalize an email so the duplicate scan catches Gmail-style
    /// aliases. Gmail (and Google Workspace) treats `john.doe@gmail.com`,
    /// `johndoe@gmail.com`, and `john.doe+work@gmail.com` as the same
    /// inbox — meaning a contact stored with each spelling is the same
    /// person. For non-Gmail domains we still lowercase + trim and strip
    /// the `+suffix` (used by many privacy-conscious users) but preserve
    /// dots since most providers treat them as distinct.
    /// Returns nil for empty / malformed addresses (no `@`).
    nonisolated static func canonicalizeEmail(_ raw: String) -> String? {
        let trimmed = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
        let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        var local = parts[0]
        let domain = parts[1]
        // Strip plus-aliasing on every domain — universally an alias of the base.
        if let plus = local.firstIndex(of: "+") {
            local = String(local[..<plus])
        }
        // Gmail-only: strip dots in the local part.
        if domain == "gmail.com" || domain == "googlemail.com" {
            local = local.replacingOccurrences(of: ".", with: "")
        }
        guard !local.isEmpty else { return nil }
        return "\(local)@\(domain)"
    }

    /// Sorted-token key for a normalized name. "John Smith" and
    /// "Smith John" both produce "john smith", so a CSV import that
    /// stored a contact as `Last First` collides correctly with the
    /// iCloud version stored `First Last`. Inputs are expected to have
    /// already been through `normalizeNameForMatching` (lowercased,
    /// diacritic-folded, prefix/suffix-stripped).
    nonisolated static func tokenSetKey(_ normalized: String) -> String {
        normalized
            .split(separator: " ")
            .map(String.init)
            .sorted()
            .joined(separator: " ")
    }

    nonisolated static func normalizeNameForMatching(_ name: String) -> String {
        // Fold diacritics and lowercase
        var result = name
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        // Remove periods
        result = result.replacingOccurrences(of: ".", with: "")
        // Split into words, strip prefixes/suffixes
        var words = result.split(separator: " ").map(String.init)
        if let first = words.first, namePrefixes.contains(first) {
            words.removeFirst()
        }
        if let last = words.last, nameSuffixes.contains(last) {
            words.removeLast()
        }
        // Rejoin with single space
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Incomplete Detection (Step 4)
    /// A contact is "incomplete" when it's either:
    ///   • Unidentifiable — no given, family, OR organization name (truly
    ///     no identity attached). An org-only contact like "Apple Inc."
    ///     IS a valid identity, so it does not count as incomplete here.
    ///   • Unreachable — has a name but no phone and no email, so the user
    ///     can't actually contact them.
    /// Uses `AppContact.hasName` (given || family || org) as the canonical
    ///   identity check so org-only entries aren't false-flagged.
    func findIncomplete() {
        incompleteContacts = allContacts.filter { contact in
            let unidentifiable = !contact.hasName
            let unreachable    = !contact.hasPhone && !contact.hasEmail
            return unidentifiable || unreachable
        }
    }

}
