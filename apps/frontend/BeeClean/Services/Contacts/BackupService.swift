import Foundation
import Contacts

// MARK: - Backup Service (Local Storage + Backend Stats)

@MainActor
class BackupService: ObservableObject {
    static let shared = BackupService()

    @Published var backups: [ContactBackup] = []
    @Published var isCreating = false
    @Published var isRestoring = false
    @Published var error: String?

    private let fileManager = FileManager.default

    private var backupsDirectory: URL {
        // URLs for .documentDirectory is effectively guaranteed to succeed on
        // iOS, but any nil here would hard-crash the app. Fall back to tmp
        // so restore/create paths still return a valid URL.
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = docs.appendingPathComponent("ContactBackups", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL {
        backupsDirectory.appendingPathComponent("index.json")
    }

    private init() {
        loadIndex()
    }

    // MARK: - Load Index

    func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            backups = recoverFromFilesystem()
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            backups = try decoder.decode([ContactBackup].self, from: data)
            // Sort newest first
            backups.sort { $0.createdAt > $1.createdAt }
        } catch {
            // Index is corrupt — fall back to filesystem scan so the user
            // doesn't lose visibility into backup files that are still on
            // disk. Rebuild and persist so we don't hit this path repeatedly.
            print("[BackupService] Index corrupt, recovering from filesystem")
            backups = recoverFromFilesystem()
            if !backups.isEmpty { saveIndex() }
        }
    }

    /// Enumerates backup JSON files in the directory and reconstructs minimal
    /// `ContactBackup` metadata. Contact count comes from the file's JSON
    /// array; createdAt falls back to the file's creation date.
    private func recoverFromFilesystem() -> [ContactBackup] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var recovered: [ContactBackup] = []
        for url in urls where url.pathExtension == "json" && url.lastPathComponent != "index.json" {
            let id = url.deletingPathExtension().lastPathComponent
            let count: Int
            if let data = try? Data(contentsOf: url),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                count = arr.count
            } else {
                continue // skip unreadable / malformed file
            }
            let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            recovered.append(ContactBackup(id: id, contactCount: count, createdAt: createdAt))
        }
        return recovered.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backups)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[BackupService] Failed to save index: \(error)")
        }
    }

    // MARK: - Create Backup

    func createBackup(contacts: [AppContact]) async -> Bool {
        isCreating = true
        self.error = nil

        let backupID = UUID().uuidString
        let now = Date()

        // Serialize contacts
        let backupContacts = contacts.map { contact -> BackupContact in
            let phones: [BackupContact.LabeledValue]
            let emails: [BackupContact.LabeledValue]

            if let cn = contact.cnContact {
                phones = cn.phoneNumbers.map {
                    BackupContact.LabeledValue(
                        label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? "other"),
                        value: $0.value.stringValue
                    )
                }
                emails = cn.emailAddresses.map {
                    BackupContact.LabeledValue(
                        label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "other"),
                        value: $0.value as String
                    )
                }
            } else {
                phones = contact.phoneNumbers.map {
                    BackupContact.LabeledValue(label: "mobile", value: $0)
                }
                emails = contact.emails.map {
                    BackupContact.LabeledValue(label: "home", value: $0)
                }
            }

            return BackupContact(
                identifier: contact.id,
                givenName: contact.givenName,
                familyName: contact.familyName,
                organizationName: contact.organizationName,
                jobTitle: contact.jobTitle,
                phoneNumbers: phones,
                emailAddresses: emails,
                note: ""
            )
        }

        // Write backup file
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backupContacts)
            let fileURL = backupsDirectory.appendingPathComponent("\(backupID).json")
            try data.write(to: fileURL, options: .atomic)

            // Update index
            let metadata = ContactBackup(
                id: backupID,
                contactCount: contacts.count,
                createdAt: now
            )
            backups.insert(metadata, at: 0)
            saveIndex()

            // Log to backend stats
            StatsService.shared.logContactAction(action: "backup", contactCount: contacts.count)

            isCreating = false
            return true
        } catch {
            self.error = "Failed to create backup: \(error.localizedDescription)"
            print("[BackupService] Create error: \(error)")
            isCreating = false
            return false
        }
    }

    // MARK: - Load Backup Contacts

    func loadBackupContacts(backupID: String) async -> [BackupContact] {
        let fileURL = backupsDirectory.appendingPathComponent("\(backupID).json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[BackupService] Backup file not found: \(backupID)")
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let contacts = try JSONDecoder().decode([BackupContact].self, from: data)
            return contacts.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
        } catch {
            print("[BackupService] Load error: \(error)")
            return []
        }
    }

    // MARK: - Restore Backup

    func restoreBackup(contacts: [BackupContact]) async -> Bool {
        isRestoring = true
        self.error = nil

        // Check permission on main actor before handing off.
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status.grantsContactAccess else {
            self.error = "Contacts permission required to restore"
            isRestoring = false
            return false
        }

        // CNContactStore.execute blocks the caller while iOS merges changes.
        // On large backups (500+) this freezes the UI and triggers ANR reports
        // on TestFlight. Run the batched restore on a utility queue; surface
        // partial-success counts so the user sees what landed even if a later
        // batch fails.
        let result: (restored: Int, error: String?) = await Task.detached(priority: .utility) {
            let store = CNContactStore()
            let batchSize = 50
            var totalRestored = 0

            for batchStart in stride(from: 0, to: contacts.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, contacts.count)
                let batch = Array(contacts[batchStart..<batchEnd])

                let saveRequest = CNSaveRequest()

                for contact in batch {
                    let cnContact = CNMutableContact()
                    cnContact.givenName = contact.givenName
                    cnContact.familyName = contact.familyName
                    cnContact.organizationName = contact.organizationName
                    cnContact.jobTitle = contact.jobTitle

                    cnContact.phoneNumbers = contact.phoneNumbers.map { phone in
                        CNLabeledValue(
                            label: Self.cnLabel(from: phone.label),
                            value: CNPhoneNumber(stringValue: phone.value)
                        )
                    }

                    cnContact.emailAddresses = contact.emailAddresses.map { email in
                        CNLabeledValue(
                            label: Self.cnLabel(from: email.label),
                            value: email.value as NSString
                        )
                    }

                    // Note: writing cnContact.note requires com.apple.developer.contacts.notes entitlement

                    saveRequest.add(cnContact, toContainerWithIdentifier: nil)
                }

                do {
                    try store.execute(saveRequest)
                    totalRestored += batch.count
                } catch {
                    return (totalRestored, error.localizedDescription)
                }
            }

            return (totalRestored, nil)
        }.value

        if let errMsg = result.error {
            self.error = result.restored > 0
                ? "Restored \(result.restored) before failing: \(errMsg)"
                : "Restore failed: \(errMsg)"
            isRestoring = false
            return false
        }

        StatsService.shared.logContactAction(action: "restore", contactCount: result.restored)
        isRestoring = false
        return true
    }

    // MARK: - Delete Backup

    func deleteBackup(id: String) {
        let fileURL = backupsDirectory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: fileURL)
        backups.removeAll { $0.id == id }
        saveIndex()
    }

    // MARK: - Helpers

    nonisolated private static func cnLabel(from label: String) -> String {
        let lower = label.lowercased()
        switch lower {
        case "mobile", "cell": return CNLabelPhoneNumberMobile
        case "home": return CNLabelHome
        case "work": return CNLabelWork
        case "main": return CNLabelPhoneNumberMain
        case "iphone": return CNLabelPhoneNumberiPhone
        case "other": return CNLabelOther
        default: return CNLabelOther
        }
    }
}
