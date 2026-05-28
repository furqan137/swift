import Foundation

extension EmailService {
    // MARK: - Realtime Polling (per-category messages)
    /// Spawn a background poller that re-hits /email/messages/:category
    /// every 1.5s while the backend reports `scanning: true`, updating
    /// `messageCache[category]` so any open view picks up new waves via
    /// its existing onChange-on-fetchedAt observer. Idempotent: at most
    /// one poll task per category at a time. Caps at 60 polls (~90s) to
    /// avoid runaway loops.
    func startRealtimePoll(category: String, scope: String, maxResults: Int) {
        // Guard against piling up multiple polls for the same category.
        if realtimePollTasks[category] != nil { return }

        scanningCategoryIDs.insert(category)
        let task = Task { [weak self] in
            guard let self else { return }
            let maxPolls = 60
            var pollCount = 0
            var stillScanning = true
            while !Task.isCancelled && pollCount < maxPolls && stillScanning {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { break }

                do {
                    let endpoint = "/email/messages/\(category)?maxResults=\(maxResults)&scope=\(scope)"
                    let response: MessagesResponse = try await self.authenticatedRequest(endpoint: endpoint)

                    // Only widen the cache — never shrink it. A user paging
                    // through with loadMore() may already have more messages
                    // loaded than this poll returns.
                    let existingCount = self.messageCache[category]?.messages.count ?? 0
                    if response.messages.count >= existingCount {
                        self.messageCache[category] = CachedMessages(
                            messages: response.messages,
                            nextPageToken: response.nextPageToken,
                            filteredCount: response.filteredCount,
                            fetchedAt: Date()
                        )
                    }
                    stillScanning = response.scanning ?? false
                } catch {
                    // Bail on first error — the next user-driven fetch will retry.
                    print("[realtimePoll] \(category) error: \(error)")
                    break
                }
                pollCount += 1
            }

            self.realtimePollTasks[category] = nil
            self.scanningCategoryIDs.remove(category)
        }
        realtimePollTasks[category] = task
    }
    
    // MARK: - Fetch More Messages
    /// Returns (messages, nextPageToken, didFail).
    /// On failure, nextPageToken is preserved (passed back as-is) so the caller can retry.
    func fetchMoreMessages(category: String, scope: String = "inbox", pageToken: String, filters: EmailFilters? = nil, maxResults: Int = 500) async -> (messages: [EmailMessage], nextPageToken: String?, didFail: Bool) {
        error = nil
        do {
            var endpoint = "/email/messages/\(category)?maxResults=\(maxResults)&scope=\(scope)&pageToken=\(pageToken)"
            let queryItems = buildFilterQuery(filters)
            if !queryItems.isEmpty {
                endpoint += "&" + queryItems.joined(separator: "&")
            }
            let response: MessagesResponse = try await authenticatedRequest(endpoint: endpoint)
            return (response.messages, response.nextPageToken, false)
        } catch {
            self.error = error.localizedDescription
            print("Fetch more messages error: \(error)")
            // Return the SAME pageToken so the caller can retry — don't kill pagination
            return ([], pageToken, true)
        }
    }
    
    // MARK: - Fetch Email Detail
    func fetchEmailDetail(messageId: String) async -> EmailDetail? {
        do {
            let detail: EmailDetail = try await authenticatedRequest(endpoint: "/email/message/\(messageId)")
            return detail
        } catch {
            self.error = error.localizedDescription
            print("Fetch email detail error: \(error)")
            return nil
        }
    }
    
    // MARK: - Fetch Senders (progressive polling while backend scans)
    // MARK: - Kept Senders (on-device)
    // (`keptSenderEmails` @Published moved back to main class declaration —
    // extensions cannot hold stored properties.)

    /// Mark a sender as "kept" — purely on-device. No network, no backend.
    func keepSender(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else { return }

        LocalKeptStore.shared.add(trimmed, to: .emailSenders)
        keptSenderEmails.insert(trimmed)
        senders.removeAll { $0.email.lowercased() == trimmed }
    }

    /// Reverse a previous keep — sender will reappear in the next /email/senders fetch.
    func unkeepSender(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else { return }

        LocalKeptStore.shared.remove(trimmed, from: .emailSenders)
        keptSenderEmails.remove(trimmed)
    }

    /// Hydrate `keptSenderEmails` from on-device storage. Safe to call repeatedly;
    /// no-op when already in sync. Replaces the old GET /email/senders/kept.
    func loadKeptSenders() async {
        let local = LocalKeptStore.shared.ids(in: .emailSenders)
        if keptSenderEmails != local {
            keptSenderEmails = local
        }
        if !local.isEmpty {
            senders.removeAll { local.contains($0.email.lowercased()) }
        }
    }

    func fetchSenders(scope: String = "inbox", refresh: Bool = false) async {
        // Only show loading if we have no cached senders
        let hadData = !senders.isEmpty
        if !hadData || refresh {
            isSendersLoading = true
        }

        var isScanning = true
        var pollCount = 0
        // 800 polls × 1.5s = 20 minutes. The backend's per-query cap was
        // bumped from 80 → 400 pages so a 200k+ mailbox can now actually
        // finish Phase 1 instead of getting truncated; that scan can run
        // 7–10 minutes end-to-end on Railway, well past the old 5-minute
        // poller budget. Trust the backend's `scanning` flag — the budget
        // here is just a runaway safety net.
        let maxPolls = 800
        // Track the last seen sender count AND total-emails count so we
        // can detect a real plateau without misfiring during waves that
        // add lots of messages but no new senders. A wave that finds 500
        // more emails from already-known senders moves totalSenderEmails
        // but not senders.count — counting that as "stalled" is what was
        // ending scans early when the backend was still actively pulling
        // from a sender-heavy bucket. Plateau = NEITHER count moves.
        var lastSenderCount = -1
        var lastTotalEmails = -1
        var stallStreak = 0

        while isScanning && pollCount < maxPolls {
            do {
                var endpoint = "/email/senders?scope=\(scope)"
                if refresh && pollCount == 0 { endpoint += "&refresh=true" }
                let response: SendersResponse = try await authenticatedRequest(
                    endpoint: endpoint,
                    timeout: 30
                )

                // Always update with latest results from backend.
                // Filter out any kept senders client-side too (belt + braces with the
                // backend filter — handles a stale cache window where a freshly-kept
                // sender hasn't been purged from the backend's in-memory cache yet).
                let kept = keptSenderEmails
                if kept.isEmpty {
                    senders = response.senders
                } else {
                    senders = response.senders.filter { !kept.contains($0.email.lowercased()) }
                }
                totalSenderEmails = response.totalEmails ?? senders.reduce(0) { $0 + $1.count }
                print("[fetchSenders] Poll \(pollCount): \(senders.count) senders, \(totalSenderEmails) emails")

                isScanning = response.scanning ?? false

                // True plateau = NEITHER the sender count NOR the total
                // email count has moved for 90 seconds. Either signal
                // moving means the backend is actively pulling new
                // headers — keep polling so the user sees live updates
                // and the final count reflects every sender in the
                // mailbox, not a premature truncation.
                let progressed = senders.count != lastSenderCount
                    || totalSenderEmails != lastTotalEmails
                if progressed {
                    stallStreak = 0
                    lastSenderCount = senders.count
                    lastTotalEmails = totalSenderEmails
                } else {
                    stallStreak += 1
                }
                if stallStreak >= 60 { // 60 polls × 1.5s = 90s of no growth
                    print("[fetchSenders] Plateau detected — exiting poll loop")
                    break
                }
            } catch {
                print("Fetch senders error: \(error)")
                break
            }

            if isScanning {
                pollCount += 1
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds — matches backend progressive cache updates
            }
        }

        print("[fetchSenders] Final: \(senders.count) senders, \(totalSenderEmails) emails (polls: \(pollCount))")
        isSendersLoading = false
    }
    
}
