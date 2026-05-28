import SwiftUI

extension EmailCategoryDetailView {
    // MARK: - Glass Backdrop
    /// Exact same 3-stop blue-lavender → light-gray gradient used by the
    /// Email landing page (`EmailCleanerView.glassBackdrop`). Tapping
    /// into a category card now stays on the same canvas instead of
    /// jumping to a flat sheet.
    var glassBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header Section
    var headerSection: some View {
        VStack(spacing: 0) {
            CategoryDetailHeader(
                categoryName: categoryDisplayName,
                categoryIcon: category.icon,
                categoryColor: categoryColor,
                hasActiveFilters: hasActiveFilters,
                onBack: {
                    BottomNavBarVisibility.shared.releaseHide()
                    dismiss()
                },
                onFilter: { showFilters = true }
            )

            // Live counter
            LiveCounterText(
                hasActiveFilters: hasActiveFilters,
                searchText: searchText,
                visibleCount: visibleMessages.count,
                loadedCount: messages.count,
                totalEstimate: totalEstimate,
                hasNextPage: nextPageToken != nil,
                isScanning: emailService.scanningCategoryIDs.contains(category.id)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // Search bar
            CategoryDetailSearchBar(
                searchText: $searchText,
                messagesEmpty: messages.isEmpty,
                visibleCount: visibleMessages.count,
                totalLoaded: messages.count
            )

            // Quick Clean CTA — rendered unconditionally for every category
            // so the header's vertical layout is deterministic on first
            // frame. Count is the max of the prefetched category total and
            // what's actually loaded, so it's never zero while data exists
            // and never shifts once loading completes.
            QuickCleanCTA(
                categoryName: category.name,
                emailCount: max(totalEstimate, category.count, messages.count),
                onStart: { showQuickClean = true }
            )

            // Active filter chips
            if hasActiveFilters {
                activeFilterChips
            }

            Divider().background(Color.black.opacity(0.06))
        }
    }

    // MARK: - Active Filter Chips
    var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let days = filters.olderThan {
                    ActiveFilterChip(text: "≥ \(days)d old", icon: "clock") {
                        filters.olderThan = nil; Task { await loadMessages() }
                    }
                }
                if filters.readOnly {
                    ActiveFilterChip(text: "Read", icon: "envelope.open") {
                        filters.readOnly = false; Task { await loadMessages() }
                    }
                }
                if filters.unreadOnly {
                    ActiveFilterChip(text: "Unread", icon: "envelope.badge") {
                        filters.unreadOnly = false; Task { await loadMessages() }
                    }
                }
                if !filters.senderContains.isEmpty {
                    ActiveFilterChip(text: "From: \(filters.senderContains)", icon: "person") {
                        filters.senderContains = ""; Task { await loadMessages() }
                    }
                }
                if !filters.subjectContains.isEmpty {
                    ActiveFilterChip(text: "Subject: \(filters.subjectContains)", icon: "text.alignleft") {
                        filters.subjectContains = ""; Task { await loadMessages() }
                    }
                }
                if let hasAtt = filters.hasAttachments {
                    ActiveFilterChip(text: hasAtt ? "Has attachments" : "No attachments", icon: "paperclip") {
                        filters.hasAttachments = nil; Task { await loadMessages() }
                    }
                }
                if filters.sizeFilter != .any {
                    ActiveFilterChip(text: filters.sizeFilter.rawValue, icon: "arrow.up.arrow.down") {
                        filters.sizeFilter = .any; Task { await loadMessages() }
                    }
                }
                if !filters.excludeKeywords.isEmpty {
                    ActiveFilterChip(text: "Protect: \(filters.excludeKeywords.joined(separator: ", "))", icon: "shield") {
                        filters.excludeKeywords = []; Task { await loadMessages() }
                    }
                }
                if !filters.targetKeywords.isEmpty {
                    ActiveFilterChip(text: "Keywords: \(filters.targetKeywords.joined(separator: ", "))", icon: "target") {
                        filters.targetKeywords = []; Task { await loadMessages() }
                    }
                }

                Button {
                    filters = EmailFilters()
                    Task { await loadMessages() }
                } label: {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    // (paginationTriggerIds moved to a cached @State above; updated via
    // `.onChange(of: messages)` below so it's no longer rebuilt per
    // scroll tick from inside ForEach.onAppear.)

    // MARK: - Email List
    var emailList: some View {
        let msgs = visibleMessages
        let total = msgs.count
        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 6) {
                ForEach(msgs.indices, id: \.self) { idx in
                    let message = msgs[idx]
                    CompactEmailRow(
                        message: message,
                        isSelected: selectedMessages.contains(message.id),
                        accent: categoryColor,
                        onToggle: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                if selectedMessages.contains(message.id) {
                                    selectedMessages.remove(message.id)
                                } else {
                                    selectedMessages.insert(message.id)
                                }
                            }
                        },
                        onTap: { selectedEmailForDetail = message }
                    )
                    .id(message.id)
                    .onAppear {
                        // O(1) scroll progress
                        if total > 1 {
                            scrollProgress = CGFloat(idx) / CGFloat(total - 1)
                        }
                        // O(1) pagination trigger. Suppressed while
                        // loadAllPages() is draining in the background —
                        // racing with the drainer was exactly what the
                        // "stuck at 201" bug was about.
                        if nextPageToken != nil && !isLoadingMore && !isDrainingAllPages && searchText.isEmpty && paginationTriggerIds.contains(message.id) {
                            Task { await loadMore() }
                        }
                    }
                }

                if searchText.isEmpty {
                    paginationFooter
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, selectedMessages.isEmpty ? 20 : 100)
        }
    }

    // MARK: - Scroll Scrubber
    var emailScrollScrubber: some View {
        GeometryReader { geo in
            let msgCount = max(1, messages.count)
            let trackHeight = max(80, geo.size.height - (selectedMessages.isEmpty ? 8 : 80))
            let thumbRatio = min(1.0, 7.0 / CGFloat(msgCount))
            let thumbHeight = max(44, trackHeight * thumbRatio)
            let maxOffset = trackHeight - thumbHeight

            HStack {
                Spacer()
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 6, height: trackHeight)

                    Capsule()
                        .fill(Color.black)
                        .frame(width: 6, height: thumbHeight)
                        .offset(y: scrollProgress * maxOffset)
                        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: scrollProgress)
                }
                .padding(.trailing, 2)
            }
        }
    }

    @ViewBuilder
    var paginationFooter: some View {
        if nextPageToken != nil {
            if isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                        .scaleEffect(0.8)
                    Text("Loading \(numFmt(messages.count + 1))–\(numFmt(min(messages.count + 100, totalEstimate))) of \(numFmt(totalEstimate))...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "78716C"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Tappable fallback — always available if auto-trigger missed
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Load more emails")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                }
                .onAppear {
                    // Auto-trigger when this button becomes visible —
                    // skip while loadAllPages() is already draining so
                    // we don't race the background loop into its
                    // same-token bail (the old "stuck at 201" path).
                    if !isDrainingAllPages {
                        Task { await loadMore() }
                    }
                }
            }
        }
    }

}
