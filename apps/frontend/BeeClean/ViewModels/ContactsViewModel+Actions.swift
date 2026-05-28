import Foundation
import UIKit
import Contacts

extension ContactsViewModel {
    // MARK: - Delete

    func deleteContacts(ids: Set<String>) async -> Bool {
        let toDelete = allContacts.filter { ids.contains($0.id) }
        guard !toDelete.isEmpty else { return false }

        do {
            try await service.remove(toDelete)
            await loadContacts()
            StatsService.shared.logContactAction(action: "delete", contactCount: toDelete.count)
            return true
        } catch {
            setError("Delete failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Export

    func exportContacts(ids: Set<String>) async -> URL? {
        let toExport = allContacts.filter { ids.contains($0.id) }
        guard !toExport.isEmpty else { return nil }
        do {
            let url = try service.export(toExport)
            StatsService.shared.logContactAction(action: "export", contactCount: toExport.count)
            return url
        } catch {
            setError("Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    func backupAll() async -> URL? {
        guard !allContacts.isEmpty else { return nil }
        do {
            let url = try service.backup(allContacts)
            StatsService.shared.logContactAction(action: "backup", contactCount: allContacts.count)
            return url
        } catch {
            setError("Backup failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Search

    func search(query: String, in contacts: [AppContact]? = nil) -> [AppContact] {
        let source = contacts ?? allContacts
        guard !query.isEmpty else { return source }
        // Fold diacritics for consistent matching (é→e, ñ→n) — matches duplicate detection
        let q = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return source.filter { c in
            c.fullName.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(q)
            || c.phoneNumbers.contains { $0.contains(q) }
            || c.emails.contains { $0.lowercased().contains(q) }
            || c.organizationName.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(q)
        }
    }

    // MARK: - Find by Phone

    func findContactByPhone(_ phone: String) -> AppContact? {
        let normalized = normalizePhone(phone)
        guard !normalized.isEmpty else { return nil }
        return allContacts.first { $0.normalizedPhones.contains(normalized) }
    }

    // MARK: - Auto-Detect Owner Contact

    func detectMyContact() -> AppContact? {
        let deviceName = UIDevice.current.name

        let ownerName: String? = {
            for possessive in ["'s ", "\u{2019}s "] {
                if let range = deviceName.range(of: possessive, options: .caseInsensitive) {
                    let name = String(deviceName[deviceName.startIndex..<range.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if name.count >= 2 { return name }
                }
            }
            return nil
        }()

        guard let name = ownerName else { return nil }
        let lowerName = name.lowercased()

        let candidates = allContacts.filter {
            $0.givenName.lowercased() == lowerName && $0.hasPhone
        }

        if candidates.count == 1 { return candidates.first }

        return candidates.max { a, b in
            func score(_ c: AppContact) -> Int {
                c.phoneNumbers.count + c.emails.count
                + (c.birthday != nil ? 1 : 0)
                + (c.hasThumbnail ? 1 : 0)
            }
            return score(a) < score(b)
        }
    }

    // MARK: - Bulk Op Lifecycle
    //
    // Wraps a long-running merge / delete in a stored Task so the
    // contacts sheet can dismiss without orphaning the work — and so
    // re-entering the flow doesn't pile a second bulk pass on top of
    // an already-running one. Replaces the previous `Task { await
    // performMergeAll() }` / `Task { await performDelete() }` pattern
    // that was anchored to a SwiftUI View struct, where a sheet
    // dismiss mid-merge left the Task running unowned and writing back
    // through @Published bindings into the next surface the user
    // navigated to.
    //
    // `runBulk` is fire-and-forget — callers don't wait for the
    // returned Task. Cancelling the previous Task before assignment
    // keeps the in-flight ref always pointing at the LATEST bulk
    // operation, so a `cancelInFlight()` on dismissal cancels exactly
    // that.
    func runBulk(_ work: @MainActor @escaping () async -> Void) {
        inFlightBulkTask?.cancel()
        inFlightBulkTask = Task { [weak self] in
            await work()
            // Clear the ref once finished so the property accurately
            // reflects "is something running."
            await MainActor.run { self?.inFlightBulkTask = nil }
        }
    }

    /// Cancels whatever bulk merge / delete was in flight. Safe to
    /// call from `.onDisappear` — Tasks have at-most-once cancellation
    /// semantics, and if the work has already completed the cancel is
    /// a no-op. Does NOT abort an already-issued CNSaveRequest (Apple's
    /// API doesn't expose cancellation), but stops any subsequent
    /// re-load / re-derivation passes from running into a dismissed
    /// view.
    func cancelInFlight() {
        inFlightBulkTask?.cancel()
        inFlightBulkTask = nil
    }

    // MARK: - Error Auto-Clear

    func setError(_ message: String) {
        self.error = message
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.error == message { self.error = nil }
        }
    }

    // (deinit moved back to main class — extensions cannot define deinit.)

    // MARK: - Real-time Reload (Step 6)

    func observeContactChanges() {
        changeObserver = NotificationCenter.default
            .publisher(for: .CNContactStoreDidChange)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.hasAccess, !self.isLoading else { return }
                Task { await self.loadContacts() }
            }
    }

}
