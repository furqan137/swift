import Foundation
import Contacts

extension ContactsViewModel {
    // MARK: - Keep (mark "not a duplicate")

    /// Persist that this duplicate group should no longer be suggested.
    /// Works entirely on-device via `LocalKeptStore`.
    func keepDuplicateGroup(_ group: DuplicateGroup) {
        let hash = LocalKeptStore.contactGroupHash(contactIds: group.contacts.map { $0.id })
        LocalKeptStore.shared.add(hash, to: .contactDuplicateGroups)
        duplicateGroups.removeAll { $0.id == group.id }
    }

    /// Reverse a previous keep so the group reappears on the next scan.
    func unkeepDuplicateGroup(_ group: DuplicateGroup) {
        let hash = LocalKeptStore.contactGroupHash(contactIds: group.contacts.map { $0.id })
        LocalKeptStore.shared.remove(hash, from: .contactDuplicateGroups)
        // `findDuplicates` is async (detached). Fire-and-forget here
        // is OK — the published `duplicateGroups` will refresh when
        // the detached task lands back on main.
        Task { await findDuplicates() }
    }

    // MARK: - Merge (Step 7)

    func merge(group: DuplicateGroup, primaryIndex: Int = 0) async -> Bool {
        guard group.contacts.count > 1, primaryIndex < group.contacts.count else { return false }
        let primary = group.contacts[primaryIndex]
        let dupes = group.contacts.enumerated()
            .filter { $0.offset != primaryIndex }
            .map { $0.element }

        do {
            try await service.merge(primary: primary, duplicates: dupes)
            await loadContacts()
            StatsService.shared.logContactAction(action: "merge", contactCount: dupes.count, duplicateGroupsMerged: 1)
            // Lifetime stats + activity-log entry. Action tag is
            // "contact_cleanup" so the receipt shows up in the right
            // bucket on the Progress tab.
            BeeViewModel.shared.registerCleanup(count: dupes.count, source: .photoDelete)
            HiveStatsManager.shared.recordCleanup(
                action: "contact_cleanup",
                itemCount: dupes.count,
                bytesSaved: 0
            )
            return true
        } catch {
            setError("Merge failed: \(error.localizedDescription)")
            print("[ContactsVM] Merge error: \(error)")
            return false
        }
    }

    func mergeAll() async -> (merged: Int, deleted: Int) {
        await mergeGroups(duplicateGroups)
    }

    func mergeGroups(_ groups: [DuplicateGroup]) async -> (merged: Int, deleted: Int) {
        var totalMerged = 0
        var totalDeleted = 0

        for group in groups where group.contacts.count > 1 {
            guard let primary = group.contacts.first else { continue }
            let dupes = Array(group.contacts.dropFirst())

            do {
                try await service.merge(primary: primary, duplicates: dupes)
                totalMerged += 1
                totalDeleted += dupes.count
            } catch {
                print("[ContactsVM] Merge group '\(group.name)' failed: \(error)")
            }
        }

        await loadContacts()
        if totalMerged > 0 {
            StatsService.shared.logContactAction(action: "merge", contactCount: totalDeleted, duplicateGroupsMerged: totalMerged)
            BeeViewModel.shared.registerCleanup(count: totalDeleted, source: .photoDelete)
            HiveStatsManager.shared.recordCleanup(
                action: "contact_cleanup",
                itemCount: totalDeleted,
                bytesSaved: 0
            )
        }
        return (totalMerged, totalDeleted)
    }

    /// Per-group partial merge for the selection-driven preview flow.
    ///
    /// `selectionByGroup` maps a group id → the subset of contact ids the user
    /// checkmarked inside that group. Within each group we merge ONLY that
    /// subset; unselected contacts in the same group are left alone. This is
    /// the difference from `mergeGroups`, which always merges every contact
    /// in each group it's handed.
    ///
    /// Primary selection within the subset: the contact with the most
    /// non-empty fields wins (we want to keep the richest record). Ties go
    /// to the first selected id by insertion order.
    ///
    /// Everything routes through the existing on-device `service.merge` →
    /// `ContactsManager.mergeContacts` → `CNSaveRequest`. No mock data, no
    /// network. After all merges complete, we reload from `CNContactStore`
    /// so the UI reflects the live system state.
    func mergeSelectedContactsByGroup(
        _ selectionByGroup: [String: Set<String>]
    ) async -> (merged: Int, deleted: Int) {
        var totalMerged = 0
        var totalDeleted = 0

        for group in duplicateGroups {
            guard let selectedIds = selectionByGroup[group.id], selectedIds.count >= 2 else {
                continue
            }
            let selectedContacts = group.contacts.filter { selectedIds.contains($0.id) }
            guard selectedContacts.count >= 2 else { continue }

            // Pick the richest selected contact as primary so we lose the
            // least amount of data. Score = phone count + email count +
            // (has full name ? 1 : 0) + (has organization ? 1 : 0). Ties
            // fall through to the group's existing display order (which is
            // already the source order from CNContactStore).
            func completeness(_ c: AppContact) -> Int {
                var score = c.phoneNumbers.count + c.emails.count
                if c.hasName { score += 1 }
                if !c.organizationName.isEmpty { score += 1 }
                if c.hasThumbnail { score += 1 }
                return score
            }
            let primary = selectedContacts.max(by: {
                completeness($0) < completeness($1)
            }) ?? selectedContacts[0]
            let dupes = selectedContacts.filter { $0.id != primary.id }
            guard !dupes.isEmpty else { continue }

            do {
                try await service.merge(primary: primary, duplicates: dupes)
                totalMerged += 1
                totalDeleted += dupes.count
            } catch {
                print("[ContactsVM] mergeSelected '\(group.name)' failed: \(error)")
            }
        }

        await loadContacts()
        if totalMerged > 0 {
            StatsService.shared.logContactAction(
                action: "merge",
                contactCount: totalDeleted,
                duplicateGroupsMerged: totalMerged
            )
        }
        return (totalMerged, totalDeleted)
    }

}
