import Foundation

extension EmailService {
    // MARK: - Delete Emails
    func deleteEmails(categories: [String], scope: String = "inbox", filters: EmailFilters) async -> Int {
        do {
            var body: [String: Any] = ["categories": categories, "scope": scope]
            if let days = filters.olderThan { body["olderThan"] = days }
            if filters.readOnly { body["readOnly"] = true }
            if filters.unreadOnly { body["unreadOnly"] = true }
            if filters.excludeStarred { body["excludeStarred"] = true }
            if !filters.senderContains.isEmpty { body["senderContains"] = filters.senderContains }
            if !filters.subjectContains.isEmpty { body["subjectContains"] = filters.subjectContains }
            if let hasAttachments = filters.hasAttachments { body["hasAttachments"] = hasAttachments }
            if let sizeQuery = filters.sizeFilter.queryParam { body["sizeFilter"] = sizeQuery }
            if !filters.excludeKeywords.isEmpty { body["excludeKeywords"] = filters.excludeKeywords }
            if !filters.targetKeywords.isEmpty { body["targetKeywords"] = filters.targetKeywords }
            
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let response: DeleteResponse = try await authenticatedRequest(
                endpoint: "/email/delete", method: "POST", body: jsonData
            )
            invalidateCache()
            await fetchCategories()
            return response.deletedCount
        } catch {
            print("Delete emails error: \(error)")
            return 0
        }
    }
    
    // MARK: - Soft Delete (Trash)
    //
    // All trash/untrash requests funnel through `_performTrashBatch` and
    // `_performUntrashBatch` so one implementation owns auth, retry, result
    // shaping, and cache invalidation. The public `trashSingleMessage` /
    // `trashMessages` / `untrashMessages` entry points are thin wrappers for
    // legacy call sites; new code should call `trashMessagesDetailed` and
    // consume the per-message `BulkMailActionResult`.
    //
    // Delete policy: `performChanges` with Gmail's trash endpoint — messages
    // land in the provider's Trash folder and are recoverable for the
    // standard retention window (Gmail: 30 days). We never call
    // `messages.delete` here. Permanent deletion is intentionally out of
    // scope for this surface.

    /// Legacy single-message entry point. Kept so existing call sites don't
    /// change; internally routes through the batched implementation.
    func trashSingleMessage(messageId: String) async -> Bool {
        let result = await trashMessagesDetailed(messageIds: [messageId])
        return result.allSucceeded
    }

    /// Legacy bulk entry point. Returns just the success count for backward
    /// compatibility; callers wanting partial-failure visibility should use
    /// `trashMessagesDetailed`.
    func trashMessages(messageIds: [String]) async -> Int {
        guard !messageIds.isEmpty else { return 0 }
        let result = await trashMessagesDetailed(messageIds: messageIds)
        return result.succeededIds.count
    }

    /// Preferred bulk trash entry point. Returns a structured result with
    /// per-message success / failure so UIs can show partial-failure states
    /// and keep inbox lists in sync with what actually moved.
    ///
    /// Side-effect: every successful trash funnels through HiveStatsManager
    /// with action="email_cleanup". This is the SINGLE wiring point so any
    /// caller (QuickClean swipe deck, category detail bulk-trash, single
    /// detail-view trash) feeds the streak + activity ledger automatically.
    /// Callers should NOT call recordCleanup themselves — that would
    /// double-count.
    func trashMessagesDetailed(
        messageIds: [String],
        sourceMailbox: MailboxRef = .inbox,
        provider: MailProviderKind = .gmail,
        emailCategory: EmailCategory? = nil
    ) async -> BulkMailActionResult {
        guard !messageIds.isEmpty else { return .empty }
        let mailProvider = MailProviderRegistry.provider(for: provider)
        let result = await mailProvider.trash(
            messageIds: messageIds,
            sourceMailbox: sourceMailbox
        )
        let succeeded = result.succeededIds.count
        if succeeded > 0 {
            // Tag the activity log with the email category when known
            // (single-email or category-detail callers always know;
            // QuickClean bulk-trash can span categories so it passes
            // nil and falls into the unsegmented Email bucket).
            // Encoded as "email_cleanup:promotions" / "...social" /
            // etc — `ActivityEntry.emailCategory` parses it back so
            // the Progress BreakdownCard can segment.
            let action = emailCategory.map { "email_cleanup:\($0.rawValue)" } ?? "email_cleanup"
            await MainActor.run {
                HiveStatsManager.shared.recordCleanup(
                    action: action,
                    itemCount: succeeded,
                    bytesSaved: 0
                )
                BeeViewModel.shared.registerCleanup(count: succeeded, source: .emailCleanup)
            }
        }
        return result
    }

    /// Legacy recover entry point — returns just the success count.
    func untrashMessages(messageIds: [String]) async -> Int {
        let result = await untrashMessagesDetailed(messageIds: messageIds)
        return result.succeededIds.count
    }

    /// Preferred recover entry point. Returns per-message results so Undo
    /// can reflect partial recovery (rare, but possible if a message was
    /// manually emptied from trash between the delete and the undo).
    func untrashMessagesDetailed(
        messageIds: [String],
        originalMailbox: MailboxRef = .inbox,
        provider: MailProviderKind = .gmail
    ) async -> BulkMailActionResult {
        guard !messageIds.isEmpty else { return .empty }
        let mailProvider = MailProviderRegistry.provider(for: provider)
        return await mailProvider.untrash(
            messageIds: messageIds,
            sourceMailbox: originalMailbox
        )
    }

    // MARK: - Provider-internal: actual network trash/untrash
    //
    // These are implementation details for `MailProvider` conformances and
    // are not meant for direct UI use. The underscore prefix keeps them out
    // of autocomplete for feature code.

    func _performTrashBatch(
        provider: MailProviderKind,
        messageIds: [String],
        sourceMailbox: MailboxRef,
        targetMailbox: MailboxRef
    ) async -> BulkMailActionResult {
        let timestamp = Date()
        do {
            let body: [String: Any] = ["messageIds": messageIds]
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let response: DeleteResponse = try await authenticatedRequest(
                endpoint: "/email/trash", method: "POST", body: jsonData
            )
            return shapeResult(
                attemptedIds: messageIds,
                deletedCount: response.deletedCount,
                failed: response.failed ?? [],
                provider: provider,
                source: sourceMailbox,
                target: targetMailbox,
                successStatus: .success,
                timestamp: timestamp
            )
        } catch {
            let reason = String(describing: error)
            return BulkMailActionResult(
                succeededIds: [],
                failed: messageIds.map { .init(messageId: $0, reason: reason) },
                records: messageIds.map {
                    MailActionRecord(
                        localMessageId: $0,
                        providerMessageId: $0,
                        provider: provider,
                        sourceMailbox: sourceMailbox,
                        targetMailbox: targetMailbox,
                        timestamp: timestamp,
                        status: .failed,
                        errorReason: reason
                    )
                }
            )
        }
    }

    func _performUntrashBatch(
        provider: MailProviderKind,
        messageIds: [String],
        originalMailbox: MailboxRef
    ) async -> BulkMailActionResult {
        let timestamp = Date()
        let trashMailbox = MailboxRef.trash(for: provider)
        do {
            let body: [String: Any] = ["messageIds": messageIds]
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let response: UntrashResponse = try await authenticatedRequest(
                endpoint: "/email/untrash", method: "POST", body: jsonData
            )
            return shapeResult(
                attemptedIds: messageIds,
                deletedCount: response.recoveredCount,
                failed: response.failed ?? [],
                provider: provider,
                source: trashMailbox,
                target: originalMailbox,
                successStatus: .undone,
                timestamp: timestamp
            )
        } catch {
            let reason = String(describing: error)
            return BulkMailActionResult(
                succeededIds: [],
                failed: messageIds.map { .init(messageId: $0, reason: reason) },
                records: messageIds.map {
                    MailActionRecord(
                        localMessageId: $0,
                        providerMessageId: $0,
                        provider: provider,
                        sourceMailbox: trashMailbox,
                        targetMailbox: originalMailbox,
                        timestamp: timestamp,
                        status: .failed,
                        errorReason: reason
                    )
                }
            )
        }
    }

    // Maps the backend response into a `BulkMailActionResult`. Handles the
    // older-style response where only a count comes back (assume all
    // attempted ids succeeded, up to `deletedCount`).
    func shapeResult(
        attemptedIds: [String],
        deletedCount: Int,
        failed: [FailedMessageResult],
        provider: MailProviderKind,
        source: MailboxRef,
        target: MailboxRef,
        successStatus: MailActionStatus,
        timestamp: Date
    ) -> BulkMailActionResult {
        let failedSet = Set(failed.map(\.messageId))
        let failedLookup = Dictionary(
            uniqueKeysWithValues: failed.map { ($0.messageId, $0.reason) }
        )

        var succeeded: [String] = []
        var records: [MailActionRecord] = []
        for id in attemptedIds {
            if failedSet.contains(id) {
                records.append(
                    MailActionRecord(
                        localMessageId: id,
                        providerMessageId: id,
                        provider: provider,
                        sourceMailbox: source,
                        targetMailbox: target,
                        timestamp: timestamp,
                        status: .failed,
                        errorReason: failedLookup[id]
                    )
                )
            } else {
                succeeded.append(id)
                records.append(
                    MailActionRecord(
                        localMessageId: id,
                        providerMessageId: id,
                        provider: provider,
                        sourceMailbox: source,
                        targetMailbox: target,
                        timestamp: timestamp,
                        status: successStatus
                    )
                )
            }
        }

        // If backend only reported a count (no `failed` list) and the count
        // disagrees with attempted ids, synthesize a partial-failure record
        // rather than lying about success.
        if failed.isEmpty && deletedCount < attemptedIds.count {
            let missing = attemptedIds.count - deletedCount
            let extras = Array(succeeded.suffix(missing))
            succeeded.removeLast(missing)
            for id in extras {
                if let idx = records.firstIndex(where: { $0.providerMessageId == id }) {
                    records[idx].status = .failed
                    records[idx].errorReason = "Server did not confirm deletion"
                }
            }
            let syntheticFailed = extras.map {
                BulkMailActionResult.FailedAction(
                    messageId: $0,
                    reason: "Server did not confirm deletion"
                )
            }
            return BulkMailActionResult(
                succeededIds: succeeded,
                failed: syntheticFailed,
                records: records
            )
        }

        let failedActions = failed.map {
            BulkMailActionResult.FailedAction(messageId: $0.messageId, reason: $0.reason)
        }
        return BulkMailActionResult(
            succeededIds: succeeded,
            failed: failedActions,
            records: records
        )
    }
    
}
