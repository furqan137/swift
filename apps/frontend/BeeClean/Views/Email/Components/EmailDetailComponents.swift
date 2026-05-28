import SwiftUI

// MARK: - Email Detail Top Bar (dark nav with category breadcrumb)
struct EmailDetailTopBar: View {
    let isTrashed: Bool
    var categoryName: String = ""
    let onBack: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.arrowNudge(.backward)
                onBack()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    if !categoryName.isEmpty {
                        Text(categoryName)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .padding(.leading, 10)
                .padding(.trailing, categoryName.isEmpty ? 10 : 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color(hex: "1C1917"))
                )
            }

            Spacer()

            if isTrashed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Trashed")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button(action: onTrash) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Email Detail Sender Card
struct EmailDetailSenderCard: View {
    let detail: EmailDetail

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: avatarGradient(for: detail.senderName),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Text(String(detail.senderName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.senderName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)

                    Text(detail.senderEmail)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .lineLimit(1)
                }

                Spacer()

                if let date = detail.date {
                    Text(formatDate(date))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if let userEmail = AuthService.shared.currentUser?.email {
                Text("Delivered to: \(userEmail)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    private func avatarGradient(for name: String) -> [Color] {
        let gradients: [[Color]] = [
            [.blue, .purple], [.purple, .pink], [.orange, .red],
            [.green, .teal], [.pink, .orange], [.teal, .blue],
            [.indigo, .purple], [.mint, .green]
        ]
        return gradients[abs(name.hashValue) % gradients.count]
    }

    private func formatDate(_ dateString: String) -> String {
        EmailFormatters.displayDate(dateString)
    }
}

// MARK: - Email Detail Attachments
struct EmailDetailAttachments: View {
    let attachments: [EmailAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments, id: \.filename) { att in
                    HStack(spacing: 6) {
                        Image(systemName: attachmentIcon(for: att.mimeType))
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "1C1917"))

                        Text(att.filename)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "1C1917"))
                            .lineLimit(1)

                        Text(formatSize(att.size))
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "F5F5F4"))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func attachmentIcon(for mimeType: String) -> String {
        if mimeType.contains("image") { return "photo" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "doc.zipper" }
        if mimeType.contains("video") { return "film" }
        if mimeType.contains("audio") { return "music.note" }
        return "doc"
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
