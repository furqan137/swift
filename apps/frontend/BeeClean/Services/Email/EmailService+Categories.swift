import Foundation

extension EmailService {
    // MARK: - Verify Gmail Profile
    func verifyProfile() async -> GmailProfile? {
        do {
            let profile: GmailProfile = try await authenticatedRequest(endpoint: "/email/profile")
            print("Gmail profile verified: \(profile.email) matches=\(profile.matches)")
            return profile
        } catch {
            print("Profile verification error: \(error)")
            return nil
        }
    }
    
    // MARK: - Fetch Categories
    /// Polls /email/categories every 1.5s while the backend reports
    /// `scanning: true` (mirroring the /senders polling pattern). The first
    /// response returns instantly with the latest cached counts; subsequent
    /// polls pick up the wave-based revalidation as it completes.
    func fetchCategories(scope: String = "inbox") async {
        // Only show loading skeleton if we have NO cached data
        let hadData = !categories.isEmpty
        if !hadData {
            isLoading = true
            error = nil
        }

        var isScanning = true
        var pollCount = 0
        let maxPolls = 60 // ~90s upper bound at 1.5s/poll

        while isScanning && pollCount < maxPolls {
            do {
                let response: CategoriesResponse = try await authenticatedRequest(endpoint: "/email/categories?scope=\(scope)")
                categories = response.categories
                if let total = response.totalEmails {
                    totalEmailCount = total
                } else {
                    totalEmailCount = response.categories.reduce(0) { $0 + $1.count }
                }
                isScanning = response.scanning ?? false
                isCategoriesScanning = isScanning
                if pollCount == 0 {
                    // Prefetch all categories in background so navigation is instant
                    prefetchAllCategories(scope: scope)
                }
            } catch {
                // Only set error if we have nothing to show
                if !hadData {
                    self.error = error.localizedDescription
                }
                print("Fetch categories error: \(error)")
                isCategoriesScanning = false
                break
            }

            if isScanning {
                pollCount += 1
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s — matches backend wave cadence
            }
        }

        isCategoriesScanning = false
        isLoading = false
    }
    
    // MARK: - Build Filter Query
    func buildFilterQuery(_ filters: EmailFilters?) -> [String] {
        var queryItems: [String] = []
        guard let filters = filters else { return queryItems }
        
        if let days = filters.olderThan {
            queryItems.append("olderThan=\(days)")
        }
        if filters.readOnly {
            queryItems.append("isRead=true")
        } else if filters.unreadOnly {
            queryItems.append("isRead=false")
        }
        if filters.excludeStarred {
            queryItems.append("excludeStarred=true")
        }
        if !filters.senderContains.isEmpty {
            queryItems.append("from=\(filters.senderContains.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if !filters.subjectContains.isEmpty {
            queryItems.append("subject=\(filters.subjectContains.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let hasAttachments = filters.hasAttachments {
            queryItems.append("hasAttachment=\(hasAttachments)")
        }
        if let sizeQuery = filters.sizeFilter.queryParam {
            queryItems.append("sizeFilter=\(sizeQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if !filters.excludeKeywords.isEmpty {
            let kw = filters.excludeKeywords.joined(separator: ",")
            queryItems.append("excludeKeywords=\(kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if !filters.targetKeywords.isEmpty {
            let kw = filters.targetKeywords.joined(separator: ",")
            queryItems.append("targetKeywords=\(kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if filters.sortOrder == .oldest {
            queryItems.append("sortOrder=oldest")
        }
        return queryItems
    }
    
    // MARK: - Fetch Messages
    func fetchMessages(category: String, scope: String = "inbox", filters: EmailFilters? = nil, maxResults: Int = 500) async -> (messages: [EmailMessage], nextPageToken: String?, filteredCount: Int?) {
        error = nil
        do {
            var endpoint = "/email/messages/\(category)?maxResults=\(maxResults)&scope=\(scope)"
            let queryItems = buildFilterQuery(filters)
            if !queryItems.isEmpty {
                endpoint += "&" + queryItems.joined(separator: "&")
            }
            let response: MessagesResponse = try await authenticatedRequest(endpoint: endpoint)

            // If the backend is mid-scan, keep polling silently in the
            // background. Each poll updates `messageCache[category]` so any
            // open Detail view sees fresh waves arrive without manual refresh.
            // Filter-applied requests are skipped — we only track the
            // unfiltered first-page cache.
            if (response.scanning ?? false) && filters == nil {
                startRealtimePoll(category: category, scope: scope, maxResults: maxResults)
            }

            return (response.messages, response.nextPageToken, response.filteredCount)
        } catch {
            self.error = error.localizedDescription
            print("Fetch messages error: \(error)")
            return ([], nil, nil)
        }
    }

}
