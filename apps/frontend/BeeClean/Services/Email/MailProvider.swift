import Foundation

// MARK: - MailProvider
// Protocol abstracting mailbox actions across Gmail / Outlook / iCloud / IMAP.
// Soft-delete (trash) is the DEFAULT and ONLY delete action exposed here —
// permanent removal is intentionally not part of this surface and must be a
// separate, higher-friction flow if we ever add one.
//
// Each method returns structured per-message results so partial failures
// surface all the way to the UI instead of being collapsed to a Bool.
@MainActor
protocol MailProvider {
    var kind: MailProviderKind { get }

    /// Soft-delete: move messages to the provider's trash equivalent.
    /// The returned `BulkMailActionResult.records` carry the full audit trail
    /// (status, source, target, timestamp, error) per message.
    func trash(
        messageIds: [String],
        sourceMailbox: MailboxRef
    ) async -> BulkMailActionResult

    /// Reverse of trash — move messages back to their original mailbox.
    /// Used by Undo. Must not error-collapse: partial recovery is valid.
    func untrash(
        messageIds: [String],
        sourceMailbox: MailboxRef
    ) async -> BulkMailActionResult
}

// MARK: - Gmail Provider
// Routes through EmailService's backend endpoints (/email/trash, /email/untrash),
// which wrap Gmail's `batchModify` + `addLabelIds: TRASH`. The actual HTTP work
// lives in EmailService so auth / token refresh / retry keep a single
// implementation; this type exists to enforce the provider contract and own
// result shaping.
@MainActor
final class GmailProvider: MailProvider {
    let kind: MailProviderKind = .gmail
    private let service: EmailService

    init(service: EmailService? = nil) {
        self.service = service ?? EmailService.shared
    }

    func trash(
        messageIds: [String],
        sourceMailbox: MailboxRef = .inbox
    ) async -> BulkMailActionResult {
        guard !messageIds.isEmpty else { return .empty }
        let target = MailboxRef.trash(for: .gmail)
        return await service._performTrashBatch(
            provider: .gmail,
            messageIds: messageIds,
            sourceMailbox: sourceMailbox,
            targetMailbox: target
        )
    }

    func untrash(
        messageIds: [String],
        sourceMailbox: MailboxRef = .inbox
    ) async -> BulkMailActionResult {
        guard !messageIds.isEmpty else { return .empty }
        return await service._performUntrashBatch(
            provider: .gmail,
            messageIds: messageIds,
            originalMailbox: sourceMailbox
        )
    }
}

// MARK: - Outlook Provider (scaffold)
// TODO: Wire Microsoft Graph /me/messages/{id}/move with destinationId
// "deleteditems". Auth + token flow is not yet implemented; this stub
// preserves the contract so the UI layer can already branch on provider kind.
@MainActor
final class OutlookProvider: MailProvider {
    let kind: MailProviderKind = .outlook

    func trash(messageIds: [String], sourceMailbox: MailboxRef) async -> BulkMailActionResult {
        return .notImplemented(for: messageIds, provider: .outlook)
    }

    func untrash(messageIds: [String], sourceMailbox: MailboxRef) async -> BulkMailActionResult {
        return .notImplemented(for: messageIds, provider: .outlook)
    }
}

// MARK: - IMAP / iCloud Provider (scaffold)
// TODO: Implement IMAP MOVE (RFC 6851) with fallback to COPY+EXPUNGE on
// servers that don't support MOVE. iCloud uses "Trash" as the mailbox name;
// generic IMAP needs the mailbox name discovered via XLIST / LIST-EXTENDED.
@MainActor
final class ImapProvider: MailProvider {
    let kind: MailProviderKind

    init(kind: MailProviderKind = .imap) {
        self.kind = kind
    }

    func trash(messageIds: [String], sourceMailbox: MailboxRef) async -> BulkMailActionResult {
        return .notImplemented(for: messageIds, provider: kind)
    }

    func untrash(messageIds: [String], sourceMailbox: MailboxRef) async -> BulkMailActionResult {
        return .notImplemented(for: messageIds, provider: kind)
    }
}

// MARK: - Provider Registry
// Single resolution point so call sites don't have to know which concrete
// provider is active. Today it only hands back Gmail; when auth for other
// providers lands we select by account metadata here.
@MainActor
enum MailProviderRegistry {
    static func provider(for kind: MailProviderKind = .gmail) -> MailProvider {
        switch kind {
        case .gmail:   return GmailProvider()
        case .outlook: return OutlookProvider()
        case .icloud:  return ImapProvider(kind: .icloud)
        case .imap:    return ImapProvider(kind: .imap)
        }
    }
}

// MARK: - BulkMailActionResult Helpers
private extension BulkMailActionResult {
    static func notImplemented(
        for messageIds: [String],
        provider: MailProviderKind
    ) -> BulkMailActionResult {
        let reason = "Provider \(provider.rawValue) is not yet supported"
        let failed = messageIds.map { FailedAction(messageId: $0, reason: reason) }
        let records = messageIds.map {
            MailActionRecord(
                localMessageId: $0,
                providerMessageId: $0,
                provider: provider,
                sourceMailbox: .inbox,
                targetMailbox: MailboxRef.trash(for: provider),
                status: .failed,
                errorReason: reason
            )
        }
        return BulkMailActionResult(succeededIds: [], failed: failed, records: records)
    }
}
