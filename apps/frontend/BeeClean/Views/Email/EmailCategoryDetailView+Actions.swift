import SwiftUI

extension EmailCategoryDetailView {
    // MARK: - Actions
    func loadMessages() async {
        errorMessage = nil
        needsSignIn = false
        selectedMessages.removeAll()
        searchText = ""
        scrollProgress = 0

        // Show the skeleton IMMEDIATELY so the auth + cache check window
        // doesn't render as the empty state ("No emails found"). On a
        // cold start `ensureValidSession` can take 1-2s on slow networks
        // and during that window `messages.isEmpty == true` made the body
        // route to `emptyState` instead of `loadingSkeleton`. Setting
        // `isLoading = true` here closes that gap; the cache-hit branch
        // below clears it back to `false` synchronously after assigning
        // `messages`, so a hot cache still paints in one frame.
        if messages.isEmpty {
            isLoading = true
        }

        // Make sure we have a valid backend session before hitting Gmail.
        // Recovers transparently if the JWT was missing but Google session is still alive.
        let session = await AuthService.shared.ensureValidSession()
        if case .notSignedIn = session {
            needsSignIn = true
            errorMessage = "Please sign in with Google to access your emails."
            isLoading = false
            return
        }

        // ── Cache path: ALWAYS show cached data instantly, refresh in background if stale ──
        if !hasActiveFilters, let cached = emailService.cachedMessages(for: category.id), !cached.messages.isEmpty {
            messages = cached.messages
            nextPageToken = cached.nextPageToken
            filteredCount = cached.filteredCount
            isLoading = false
            if messages.count > 0 && nextPageToken == nil && messages.count > totalEstimate {
                totalEstimate = messages.count
            }
            // Background refresh if stale (> 2 min) — user sees cached data instantly
            if Date().timeIntervalSince(cached.fetchedAt) > 120 {
                emailService.refreshCategorySilently(categoryID: category.id, scope: scope)
            }
            return
        }

        // ── Fresh fetch — tiny first batch (10) for near-instant display ──
        isLoading = true
        let firstBatch = await emailService.fetchMessages(
            category: category.id, scope: scope, filters: filters, maxResults: 10
        )

        if firstBatch.messages.isEmpty && emailService.error != nil {
            errorMessage = emailService.error
            isLoading = false
            return
        }

        // Show first emails immediately — no waiting
        messages = firstBatch.messages
        nextPageToken = firstBatch.nextPageToken
        filteredCount = firstBatch.filteredCount
        isLoading = false

        if let fc = firstBatch.filteredCount, hasActiveFilters {
            totalEstimate = fc
        }

        if !hasActiveFilters {
            emailService.messageCache[category.id] = EmailService.CachedMessages(
                messages: firstBatch.messages,
                nextPageToken: firstBatch.nextPageToken,
                filteredCount: firstBatch.filteredCount,
                fetchedAt: Date()
            )
        }

        // Drain every remaining page in the background so the user sees the
        // ENTIRE category — not just the first page or two. Without this the
        // list capped at whatever the user happened to scroll through, which
        // is what made filtered views look like they stopped at ~200 emails.
        if nextPageToken != nil {
            Task { await loadAllPages() }
        }
    }

    /// Continuously paginates until `nextPageToken` is nil. Mirrors
    /// QuickCleanViewModel's background loader so the category detail view
    /// always reflects every matching email, regardless of whether the user
    /// scrolls. Without this the list capped at the first auto-fetched page
    /// (~110 messages), and filtered views looked stuck at ~200.
    ///
    /// Two prior bugs the current implementation fixes:
    /// 1. **Scroll race** — `ForEach.onAppear` also fires `loadMore()`. When
    ///    it won the `isLoadingMore` guard, the drainer's own `loadMore()`
    ///    no-op'd, leaving `nextPageToken` unchanged. The old "same-token"
    ///    bail then misread that no-op as a Gmail retry and broke the loop
    ///    after 5 false stalls — which is exactly what was capping filtered
    ///    queries at 201. `loadMore()` now returns an `outcome` so the
    ///    drainer can tell "I no-op'd" apart from "Gmail handed me back the
    ///    same token". No-ops trigger a short wait, not a stall.
    /// 2. **Transient Gmail 429** — actual same-token returns (loadMore did
    ///    run + result.didFail) still tolerate up to 5 retries with
    ///    exponential backoff before bailing.
    func loadAllPages() async {
        isDrainingAllPages = true
        defer { isDrainingAllPages = false }

        var sameTokenStreak = 0
        // 2000-page hard cap belt-and-braces against a runaway loop on
        // pathologically large filtered queries.
        var safetyCounter = 0
        while nextPageToken != nil, safetyCounter < 2000 {
            let outcome = await loadMore()

            switch outcome {
            case .noOp:
                // Another loadMore (likely scroll-triggered) was in flight.
                // Yield briefly, then retry — DO NOT count this as a stall.
                try? await Task.sleep(nanoseconds: 120_000_000)
                continue

            case .ranFresh:
                // loadMore advanced the token (or nil'd it). Reset the
                // stall counter and breathe between pages.
                sameTokenStreak = 0

            case .ranSameToken:
                // loadMore actually fetched but Gmail returned the same
                // token — real retry case. Bail after 5 attempts.
                sameTokenStreak += 1
                if sameTokenStreak > 5 {
                    print("[EmailPagination] STALLED after 5 same-token retries; bailing")
                    break
                }
                let backoffMs = 250 * (1 << min(sameTokenStreak - 1, 4))
                try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            }

            // Tiny breather between pages so a 50-page category doesn't queue
            // 50 simultaneous Gmail calls back-to-back.
            try? await Task.sleep(nanoseconds: 80_000_000)
            safetyCounter += 1
        }
    }

    /// Outcome of a `loadMore` attempt. Lets `loadAllPages` distinguish a
    /// real Gmail same-token retry from a benign concurrency no-op.
    enum LoadMoreOutcome { case noOp, ranFresh, ranSameToken }

    @discardableResult
    func loadMore() async -> LoadMoreOutcome {
        guard let token = nextPageToken else { return .ranFresh }
        guard !isLoadingMore else { return .noOp }
        isLoadingMore = true
        print("[EmailPagination] Loading more for \(category.id) | current: \(messages.count) | token: \(token.prefix(20))...")

        // 500 is the backend cap. Larger pages mean far fewer round-trips when
        // draining a big category — a 10k filtered category goes from 100
        // sequential fetches at 100/page down to 20 at 500/page.
        let result = await emailService.fetchMoreMessages(
            category: category.id, scope: scope, pageToken: token, filters: filters, maxResults: 500
        )

        if result.didFail {
            print("[EmailPagination] FAILED — keeping token for retry")
            nextPageToken = result.nextPageToken
            isLoadingMore = false
            // Brief backoff before the auto-loader retries, so we don't burn
            // through the safety cap on a network hiccup.
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Same token preserved on failure → drainer treats this as a
            // real same-token retry (counts toward the 5-strike bail).
            return .ranSameToken
        }

        let existingIds = Set(messages.map { $0.id })
        let newMessages = result.messages.filter { !existingIds.contains($0.id) }
        messages.append(contentsOf: newMessages)
        nextPageToken = result.nextPageToken
        print("[EmailPagination] Loaded \(newMessages.count) new | total: \(messages.count) | hasMore: \(nextPageToken != nil)")
        // Pagination tells us the truth — once we've drained every page, the
        // loaded count is the actual total. Bump the estimate up if Gmail's
        // resultSizeEstimate underreported (it caps low for filtered queries,
        // which is exactly the "201 emails" cap users were seeing).
        if nextPageToken == nil && messages.count > totalEstimate {
            totalEstimate = messages.count
        }
        // While pagination is in flight, also keep the estimate honest if
        // we've already loaded more than the last reported estimate. Without
        // this, the header sits at "201 FILTERED EMAILS" even though the
        // list has visibly grown past 1k.
        if hasActiveFilters && messages.count > totalEstimate {
            totalEstimate = messages.count
        }

        // Update cache with the expanded message list
        if !hasActiveFilters {
            emailService.messageCache[category.id] = EmailService.CachedMessages(
                messages: messages,
                nextPageToken: nextPageToken,
                filteredCount: nil,
                fetchedAt: Date()
            )
        }
        isLoadingMore = false

        // Real Gmail same-token return (rare but possible) → tell the
        // drainer this is a genuine retry signal, not a no-op.
        if result.nextPageToken != nil && result.nextPageToken == token {
            return .ranSameToken
        }
        return .ranFresh
    }

    func deleteSelectedMessages() async {
        isDeleting = true
        let idsToTrash = Array(selectedMessages)
        let removedMessages = messages.filter { selectedMessages.contains($0.id) }

        // One batched call — provider handles chunking + per-message fallback.
        // Result carries succeeded ids, failed ids (with reasons), and a full
        // per-message audit trail we can surface in UI state.
        let result = await emailService.trashMessagesDetailed(
            messageIds: idsToTrash,
            emailCategory: EmailCategory.fromGmailId(category.id)
        )
        isDeleting = false

        let succeededSet = Set(result.succeededIds)
        guard !succeededSet.isEmpty else {
            // All failed — surface, don't pretend. UI stays as-is so the user
            // can retry; the toast's "couldn't be moved" line is shown even
            // with zero successes.
            undoMgr.showUndo(result: result, provider: .gmail)
            return
        }

        // Only remove what actually moved, so a partial failure leaves the
        // failed rows visible in the list (no fake-success disappearance).
        let succeededMessages = removedMessages.filter { succeededSet.contains($0.id) }
        lastDeletedMessages = succeededMessages
        messages.removeAll { succeededSet.contains($0.id) }
        totalEstimate = max(0, totalEstimate - succeededSet.count)
        selectedMessages = selectedMessages.filter { !succeededSet.contains($0) }

        // Keep cache in sync so a reopen of this category doesn't resurrect
        // the just-trashed messages.
        if var cached = emailService.cachedMessages(for: category.id) {
            cached.messages.removeAll { succeededSet.contains($0.id) }
            cached.fetchedAt = Date()
            emailService.messageCache[category.id] = cached
        }

        undoMgr.showUndo(result: result, provider: .gmail) { [self] recovered in
            if recovered {
                messages.insert(contentsOf: lastDeletedMessages, at: 0)
                messages.sort { ($0.date ?? "") > ($1.date ?? "") }
                totalEstimate += lastDeletedMessages.count
                lastDeletedMessages = []
            }
        }
    }

    func numFmt(_ num: Int) -> String {
        EmailFormatters.numFmt(num)
    }
}


