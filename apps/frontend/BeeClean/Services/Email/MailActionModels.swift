import Foundation

// MARK: - Action Status
// Lifecycle states for a single mailbox action (trash / untrash / move).
// `pending` is the queued state before the network request fires; `inProgress`
// covers in-flight; `success` / `failed` are terminal for the forward action.
// `undone` is a distinct terminal state set only after a successful recovery
// so callers can tell "never moved" from "moved-then-restored".
enum MailActionStatus: String, Codable, Equatable {
    case pending
    case inProgress = "in_progress"
    case success
    case failed
    case undone
}

// MARK: - Mail Provider
// String-typed so it survives persistence and shows up cleanly in logs / UI.
// Keep the raw values stable — they're part of the network contract with the
// backend once we wire non-Gmail providers.
enum MailProviderKind: String, Codable, Equatable {
    case gmail
    case outlook   // Microsoft 365 / Outlook.com — not yet wired
    case icloud    // Apple iCloud Mail (IMAP) — not yet wired
    case imap      // Generic IMAP fallback — not yet wired

    /// User-facing name of the destination folder for a soft delete.
    var trashFolderLabel: String {
        switch self {
        case .gmail:   return "Trash"
        case .outlook: return "Deleted Items"
        case .icloud:  return "Trash"
        case .imap:    return "Trash"
        }
    }
}

// MARK: - Mailbox
// Logical source / target mailbox for an action. Kept abstract so Gmail
// label-ids, IMAP folder names, and Outlook folder IDs can all land here.
struct MailboxRef: Codable, Equatable, Hashable {
    let id: String          // Provider-native id ("INBOX", folder id, label id)
    let displayName: String // User-facing name

    static let inbox = MailboxRef(id: "INBOX", displayName: "Inbox")
    static func trash(for provider: MailProviderKind) -> MailboxRef {
        switch provider {
        case .gmail:   return MailboxRef(id: "TRASH", displayName: "Trash")
        case .outlook: return MailboxRef(id: "deleteditems", displayName: "Deleted Items")
        case .icloud, .imap: return MailboxRef(id: "Trash", displayName: "Trash")
        }
    }
}

// MARK: - Action Record
// One row per attempted message action. We carry the provider + original
// mailbox so Undo can route back to the right place even if the user switches
// accounts mid-operation. `errorReason` is populated only on `.failed`; left
// nil otherwise so UI can safely destructure.
struct MailActionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let localMessageId: String      // Our internal id (same as provider id today)
    let providerMessageId: String   // Gmail message id, Outlook id, etc.
    let provider: MailProviderKind
    let sourceMailbox: MailboxRef
    let targetMailbox: MailboxRef
    let timestamp: Date
    var status: MailActionStatus
    var errorReason: String?

    init(
        id: UUID = UUID(),
        localMessageId: String,
        providerMessageId: String,
        provider: MailProviderKind,
        sourceMailbox: MailboxRef = .inbox,
        targetMailbox: MailboxRef,
        timestamp: Date = Date(),
        status: MailActionStatus = .pending,
        errorReason: String? = nil
    ) {
        self.id = id
        self.localMessageId = localMessageId
        self.providerMessageId = providerMessageId
        self.provider = provider
        self.sourceMailbox = sourceMailbox
        self.targetMailbox = targetMailbox
        self.timestamp = timestamp
        self.status = status
        self.errorReason = errorReason
    }
}

// MARK: - Bulk Result
// Structured outcome of a bulk trash / untrash. Partial success is the norm
// in real mailbox APIs (rate limits, per-message permissions, transient 5xx)
// so we never collapse to a single Bool. Callers pass `succeededIds` back
// into UI state and surface `failed` in a subtle secondary message.
struct BulkMailActionResult: Equatable {
    var succeededIds: [String]
    var failed: [FailedAction]
    var records: [MailActionRecord]

    struct FailedAction: Equatable, Codable {
        let messageId: String
        let reason: String
    }

    static let empty = BulkMailActionResult(succeededIds: [], failed: [], records: [])

    var totalAttempted: Int { succeededIds.count + failed.count }
    var hasPartialFailure: Bool { !failed.isEmpty && !succeededIds.isEmpty }
    var allFailed: Bool { succeededIds.isEmpty && !failed.isEmpty }
    var allSucceeded: Bool { failed.isEmpty && !succeededIds.isEmpty }
}
