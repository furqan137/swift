import SwiftUI

// MARK: - Email Detail View
struct EmailDetailView: View {
    let message: EmailMessage
    var categoryName: String = ""
    @StateObject private var emailService = EmailService.shared
    @StateObject private var undoMgr = EmailUndoManager()
    @State private var detail: EmailDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showTrashConfirm = false
    @State private var isTrashing = false
    @State private var isTrashed = false
    @State private var webViewHeight: CGFloat = 300
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                EmailDetailTopBar(
                    isTrashed: isTrashed,
                    categoryName: categoryName,
                    onBack: { dismiss() },
                    onTrash: { showTrashConfirm = true }
                )

                if let detail = detail {
                    emailReader(detail)
                } else {
                    // Show what we already know from the list item — instant, no loading
                    instantPreview
                }
            }
        }
        .navigationBarHidden(true)
        .hidesBottomNavBar()
        .undoToast(undoMgr)
        .alert("Move to Trash?", isPresented: $showTrashConfirm) {
            Button("Delete", role: .destructive) { Task { await trashEmail() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email will be moved to trash.")
        }
        .task { await loadDetail() }
    }

    // MARK: - Instant Preview (from list data, no network)
    private var instantPreview: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(message.subject)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                // Sender info from list data
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "E8E8ED"))
                            .frame(width: 40, height: 40)
                        Text(String(message.senderName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "78716C"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.senderName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                        Text(message.senderEmail)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }

                    Spacer()

                    if let date = message.date {
                        Text(EmailFormatters.shortDate(date))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                Divider().padding(.horizontal, 16)

                // Snippet as placeholder
                Text(EmailFormatters.cleanSnippet(message.snippet))
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "78716C"))
                    .padding(16)

                // Loading indicator for full body
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "A1A1AA")))
                            .scaleEffect(0.7)
                        Text("Loading full email...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Text("Couldn't load full email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "78716C"))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "A1A1AA"))
                        Button {
                            Task { await loadDetail() }
                        } label: {
                            Text(BCLoc.retry.tr)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(hex: "1C1917"))
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
            }
            .padding(.bottom, 60)
        }
    }

    private func emailReader(_ detail: EmailDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(detail.subject)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    EmailDetailSenderCard(detail: detail)

                    let tags = buildTags(detail)
                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.text) { tag in
                                    MiniTag(text: tag.text, color: tag.color, icon: tag.icon)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 10)
                    }

                    Divider().padding(.horizontal, 16)

                    if !detail.attachments.isEmpty {
                        EmailDetailAttachments(attachments: detail.attachments)
                        Divider().padding(.horizontal, 16)
                    }

                    emailBodyContent(detail)
                }
                .padding(.bottom, 60)
            }
        }


    @ViewBuilder
    private func emailBodyContent(_ detail: EmailDetail) -> some View {
        if !detail.bodyHtml.isEmpty {
            AutoSizingWebView(html: detail.bodyHtml, dynamicHeight: $webViewHeight)
                .frame(height: webViewHeight)
                .padding(.top, 4)
        } else if !detail.bodyText.isEmpty {
            Text(detail.bodyText)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1C1917").opacity(0.85))
                .padding(16)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .foregroundColor(Color(hex: "A1A1AA"))
                Text("No content")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    // Loading and error states are now handled inline by instantPreview

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        detail = await emailService.fetchEmailDetail(messageId: message.id)
        if detail == nil { errorMessage = emailService.error ?? "Unknown error" }
        isLoading = false
    }

    private func trashEmail() async {
        // Optimistic UI + background trash. Gmail's trash endpoint is
        // idempotent, so a late-arriving /trash followed by /untrash (from
        // Undo) converges correctly.
        isTrashed = true
        let messageId = message.id
        Task {
            let result = await emailService.trashMessagesDetailed(messageIds: [messageId])
            await MainActor.run {
                if result.succeededIds.isEmpty {
                    // Trash failed — roll back the optimistic UI and surface
                    // the failure via the toast so the user knows.
                    isTrashed = false
                    undoMgr.showUndo(result: result, provider: .gmail)
                } else {
                    undoMgr.showUndo(result: result, provider: .gmail) { recovered in
                        if recovered { self.isTrashed = false } else { self.dismiss() }
                    }
                }
            }
        }
    }

    private struct TagInfo: Identifiable {
        let text: String; let color: Color; let icon: String
        var id: String { text }
    }

    private func buildTags(_ detail: EmailDetail) -> [TagInfo] {
        var tags: [TagInfo] = []
        if !detail.isRead { tags.append(TagInfo(text: "Unread", color: .blue, icon: "envelope.badge.fill")) }
        if detail.isStarred { tags.append(TagInfo(text: "Starred", color: .yellow, icon: "star.fill")) }
        if detail.hasUnsubscribe { tags.append(TagInfo(text: "Has Unsubscribe", color: .orange, icon: "link")) }
        if !detail.attachments.isEmpty {
            tags.append(TagInfo(text: "\(detail.attachments.count) file\(detail.attachments.count > 1 ? "s" : "")", color: .purple, icon: "paperclip"))
        }
        return tags
    }
}
