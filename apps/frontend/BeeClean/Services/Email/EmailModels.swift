import Foundation
import SwiftUI

// MARK: - Gmail Category
struct GmailCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let labelId: String
    var count: Int
    
    var icon: String {
        switch id {
        case "primary": return "tray.full"
        case "social": return "person.2"
        case "promotions": return "tag"
        case "updates": return "arrow.down.circle"
        case "forums": return "quote.bubble"
        case "spam": return "trash.fill"
        default: return "envelope"
        }
    }

    /// Single source of truth for the category's accent color. Drives the
    /// category-picker badge, the detail-view header icon, and every email
    /// row's unread tick / leading rail / avatar-selected state, so the
    /// entire category reads as one cohesive surface. Distinct for every
    /// known Gmail category (including Primary, Starred, Important, Trash,
    /// Sent, Drafts) so the tick is always visible and on-brand.
    var tintColor: Color {
        switch id {
        case "primary":    return Color(hex: "0EA5E9") // sky blue
        case "social":     return Color(hex: "2563EB") // blue
        case "promotions": return Color(hex: "D97706") // amber
        case "updates":    return Color(hex: "059669") // emerald
        case "forums":     return Color(hex: "7C3AED") // violet
        case "spam":       return Color(hex: "DC2626") // red
        case "important":  return Color(hex: "F59E0B") // honey
        case "starred":    return Color(hex: "EAB308") // gold
        case "sent":       return Color(hex: "0891B2") // cyan
        case "drafts":     return Color(hex: "6366F1") // indigo
        case "trash":      return Color(hex: "71717A") // zinc
        default:           return Color(hex: "475569") // slate — never black, so the tick is always visible
        }
    }
}

// MARK: - Email Message
struct EmailMessage: Codable, Identifiable, Hashable {
    static func == (lhs: EmailMessage, rhs: EmailMessage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    let id: String
    let threadId: String
    let snippet: String
    let labelIds: [String]?
    let isRead: Bool
    let isStarred: Bool
    let from: String
    let subject: String
    let date: String?
    let hasUnsubscribe: Bool
    
    // Pre-computed on decode to avoid regex in tight loops
    let senderName: String
    let senderEmail: String
    
    enum CodingKeys: String, CodingKey {
        case id, threadId, snippet, labelIds, isRead, isStarred, from, subject, date, hasUnsubscribe
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        threadId = try c.decode(String.self, forKey: .threadId)
        snippet = try c.decode(String.self, forKey: .snippet)
        labelIds = try c.decodeIfPresent([String].self, forKey: .labelIds)
        isRead = try c.decode(Bool.self, forKey: .isRead)
        isStarred = try c.decode(Bool.self, forKey: .isStarred)
        from = try c.decode(String.self, forKey: .from)
        subject = try c.decode(String.self, forKey: .subject)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        hasUnsubscribe = try c.decode(Bool.self, forKey: .hasUnsubscribe)
        
        // Pre-compute sender fields once at decode time
        if let match = from.range(of: "^[^<]+", options: .regularExpression) {
            senderName = String(from[match]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        } else {
            senderName = from
        }
        // Guard against malformed headers where `>` precedes `<` or the
        // brackets overlap — otherwise `index(after: start)..<end` can
        // produce `lower > upper` and Swift traps with
        // "Range requires lowerBound <= upperBound".
        if let start = from.firstIndex(of: "<"),
           let end = from.firstIndex(of: ">"),
           start < end,
           from.index(after: start) <= end {
            senderEmail = String(from[from.index(after: start)..<end]).lowercased()
        } else {
            senderEmail = from.lowercased()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadId, forKey: .threadId)
        try c.encode(snippet, forKey: .snippet)
        try c.encodeIfPresent(labelIds, forKey: .labelIds)
        try c.encode(isRead, forKey: .isRead)
        try c.encode(isStarred, forKey: .isStarred)
        try c.encode(from, forKey: .from)
        try c.encode(subject, forKey: .subject)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encode(hasUnsubscribe, forKey: .hasUnsubscribe)
    }

    /// Mock initializer for local data generation (bypasses Codable)
    init(
        id: String,
        threadId: String,
        snippet: String,
        labelIds: [String]?,
        isRead: Bool,
        isStarred: Bool,
        from: String,
        subject: String,
        date: String?,
        hasUnsubscribe: Bool
    ) {
        self.id = id
        self.threadId = threadId
        self.snippet = snippet
        self.labelIds = labelIds
        self.isRead = isRead
        self.isStarred = isStarred
        self.from = from
        self.subject = subject
        self.date = date
        self.hasUnsubscribe = hasUnsubscribe

        if let match = from.range(of: "^[^<]+", options: .regularExpression) {
            self.senderName = String(from[match]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        } else {
            self.senderName = from
        }
        if let start = from.firstIndex(of: "<"),
           let end = from.firstIndex(of: ">"),
           start < end,
           from.index(after: start) <= end {
            self.senderEmail = String(from[from.index(after: start)..<end]).lowercased()
        } else {
            self.senderEmail = from.lowercased()
        }
    }
}

// MARK: - Email Sender
struct EmailSender: Codable, Identifiable {
    let name: String
    let email: String
    let count: Int
    let hasUnsubscribe: Bool
    
    var id: String { email }
}

// MARK: - API Response Models
struct CategoriesResponse: Codable {
    let categories: [GmailCategory]
    let totalEmails: Int?
    /// True while the backend is running a wave-based revalidation. The
    /// client polls this endpoint every 1.5s while the flag is set, so the
    /// counts update in near-real-time as Gmail reports them.
    let scanning: Bool?
}

struct MessagesResponse: Decodable {
    let messages: [EmailMessage]
    let nextPageToken: String?
    let count: Int
    let filteredCount: Int?
    /// True while the backend is progressively filling the page cache for
    /// this category. The client polls every 1.5s while the flag is set so
    /// fresh emails appear without manual refresh.
    let scanning: Bool?

    /// Wrapper that absorbs decode failures for individual messages
    /// so one malformed entry doesn't kill the whole response.
    private struct LossyMessage: Decodable {
        let value: EmailMessage?
        init(from decoder: Decoder) throws {
            value = try? EmailMessage(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case messages, nextPageToken, count, filteredCount, scanning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        filteredCount = try c.decodeIfPresent(Int.self, forKey: .filteredCount)
        scanning = try c.decodeIfPresent(Bool.self, forKey: .scanning)
        let lossy = try c.decode([LossyMessage].self, forKey: .messages)
        messages = lossy.compactMap(\.value)
    }
}

struct SendersResponse: Codable {
    let senders: [EmailSender]
    let totalSenders: Int
    let totalEmails: Int?
    let scanning: Bool?
}

struct GmailProfile: Codable {
    let email: String
    let messagesTotal: Int?
    let threadsTotal: Int?
    let matches: Bool
}

// MARK: - Refresh Response (History API)
struct RefreshResponse: Codable {
    let historyId: String?
    let totalEmails: Int?
    let categories: [RefreshCategory]?
    let newMessageIds: [String]?
    let deletedMessageIds: [String]?
    let hasChanges: Bool
    let historyExpired: Bool?
}

struct RefreshCategory: Codable {
    let id: String
    let labelId: String
    let count: Int
}

struct DeleteResponse: Codable {
    let success: Bool
    let deletedCount: Int
    // Per-message failure detail. Optional for backward compatibility with
    // the legacy `/email/delete` response; the refactored `/email/trash`
    // endpoint always populates it (empty array when everything succeeded).
    let failed: [FailedMessageResult]?
}

struct FailedMessageResult: Codable, Equatable {
    let messageId: String
    let reason: String
}

struct TokenExpiredResponse: Codable {
    let error: String
}

struct UnsubscribeResponse: Codable {
    let success: Bool
    let message: String
    let deletedCount: Int
}

struct UntrashResponse: Codable {
    let success: Bool
    let recoveredCount: Int
    let failed: [FailedMessageResult]?
}

// MARK: - Email Attachment
struct EmailAttachment: Codable {
    let filename: String
    let mimeType: String
    let size: Int
    let attachmentId: String?
}

// MARK: - Email Detail
struct EmailDetail: Codable {
    let id: String
    let threadId: String
    let snippet: String
    let labelIds: [String]?
    let isRead: Bool
    let isStarred: Bool
    let from: String
    let to: String
    let cc: String
    let subject: String
    let date: String?
    let hasUnsubscribe: Bool
    let bodyHtml: String
    let bodyText: String
    let attachments: [EmailAttachment]
    let sizeEstimate: Int?
    
    // Pre-computed at decode time
    let senderName: String
    let senderEmail: String
    
    enum CodingKeys: String, CodingKey {
        case id, threadId, snippet, labelIds, isRead, isStarred, from, to, cc, subject, date
        case hasUnsubscribe, bodyHtml, bodyText, attachments, sizeEstimate
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        threadId = try c.decode(String.self, forKey: .threadId)
        snippet = try c.decode(String.self, forKey: .snippet)
        labelIds = try c.decodeIfPresent([String].self, forKey: .labelIds)
        isRead = try c.decode(Bool.self, forKey: .isRead)
        isStarred = try c.decode(Bool.self, forKey: .isStarred)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        cc = try c.decode(String.self, forKey: .cc)
        subject = try c.decode(String.self, forKey: .subject)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        hasUnsubscribe = try c.decode(Bool.self, forKey: .hasUnsubscribe)
        bodyHtml = try c.decode(String.self, forKey: .bodyHtml)
        bodyText = try c.decode(String.self, forKey: .bodyText)
        attachments = try c.decode([EmailAttachment].self, forKey: .attachments)
        sizeEstimate = try c.decodeIfPresent(Int.self, forKey: .sizeEstimate)
        
        if let match = from.range(of: "^[^<]+", options: .regularExpression) {
            senderName = String(from[match]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        } else {
            senderName = from
        }
        // Guard against malformed headers where `>` precedes `<` or the
        // brackets overlap — otherwise `index(after: start)..<end` can
        // produce `lower > upper` and Swift traps with
        // "Range requires lowerBound <= upperBound".
        if let start = from.firstIndex(of: "<"),
           let end = from.firstIndex(of: ">"),
           start < end,
           from.index(after: start) <= end {
            senderEmail = String(from[from.index(after: start)..<end]).lowercased()
        } else {
            senderEmail = from.lowercased()
        }
    }

    /// Direct init for mock data.
    init(
        id: String, threadId: String, snippet: String, labelIds: [String]?,
        isRead: Bool, isStarred: Bool, from: String, to: String, cc: String,
        subject: String, date: String?, hasUnsubscribe: Bool,
        bodyHtml: String, bodyText: String, attachments: [EmailAttachment] = [],
        sizeEstimate: Int? = nil
    ) {
        self.id = id; self.threadId = threadId; self.snippet = snippet
        self.labelIds = labelIds; self.isRead = isRead; self.isStarred = isStarred
        self.from = from; self.to = to; self.cc = cc; self.subject = subject
        self.date = date; self.hasUnsubscribe = hasUnsubscribe
        self.bodyHtml = bodyHtml; self.bodyText = bodyText
        self.attachments = attachments; self.sizeEstimate = sizeEstimate

        if let match = from.range(of: "^[^<]+", options: .regularExpression) {
            senderName = String(from[match]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        } else { senderName = from }
        if let start = from.firstIndex(of: "<"),
           let end = from.firstIndex(of: ">"),
           start < end,
           from.index(after: start) <= end {
            senderEmail = String(from[from.index(after: start)..<end]).lowercased()
        } else { senderEmail = from.lowercased() }
    }
}

// MARK: - Filter Options
struct EmailFilters {
    var olderThan: Int? = nil
    var readOnly: Bool = false
    var unreadOnly: Bool = false
    var excludeStarred: Bool = true
    var excludeKeywords: [String] = []
    var targetKeywords: [String] = []
    var senderContains: String = ""
    var subjectContains: String = ""
    var hasAttachments: Bool? = nil
    var sizeFilter: SizeFilter = .any
    var sortOrder: SortOrder = .newest
    
    enum SizeFilter: String, CaseIterable {
        case any = "Any size"
        case small = "Under 100 KB"
        case medium = "100 KB - 1 MB"
        case large = "Over 1 MB"
        case huge = "Over 5 MB"
        
        var queryParam: String? {
            switch self {
            case .any: return nil
            case .small: return "smaller:100K"
            case .medium: return "larger:100K smaller:1M"
            case .large: return "larger:1M"
            case .huge: return "larger:5M"
            }
        }
    }
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest first"
        case oldest = "Oldest first"
    }

    var activeFilterCount: Int {
        var count = 0
        if olderThan != nil { count += 1 }
        if readOnly || unreadOnly { count += 1 }
        if !excludeStarred { count += 1 }
        if sizeFilter != .any { count += 1 }
        if hasAttachments != nil { count += 1 }
        if !senderContains.isEmpty { count += 1 }
        if !subjectContains.isEmpty { count += 1 }
        if !excludeKeywords.isEmpty { count += 1 }
        if !targetKeywords.isEmpty { count += 1 }
        if sortOrder != .newest { count += 1 }
        return count
    }
}

// MARK: - Shared Formatters (avoid recreation in tight loops)
enum EmailFormatters {
    /// Reusable number formatter for email counts
    static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    
    /// Pre-compiled regex for cleaning snippets
    static let numericEntityRegex: NSRegularExpression? = try? NSRegularExpression(pattern: "&#(\\d+);")
    static let junkRegex: NSRegularExpression? = try? NSRegularExpression(pattern: "[A-Za-z0-9+/=_-]{40,}")
    
    /// Shared date parsing formatters (expensive to create)
    static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "dd MMM yyyy HH:mm:ss z",
            "EEE, d MMM yyyy HH:mm:ss Z (z)"
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()
    
    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    
    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy\nh:mm a"
        return f
    }()
    
    /// Format a number with commas
    static func numFmt(_ num: Int) -> String {
        numberFormatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
    
    /// Parse an email date string into a short relative string (e.g. "2h ago")
    static func shortDate(_ dateString: String) -> String {
        for formatter in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
            }
        }
        return String(dateString.prefix(11))
    }
    
    /// Parse an email date string into a display format
    static func displayDate(_ dateString: String) -> String {
        for formatter in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return displayDateFormatter.string(from: date)
            }
        }
        return dateString
    }
    
    /// Clean HTML entities and junk from snippet text
    static func cleanSnippet(_ s: String) -> String {
        var text = s
        let htmlEntities: [(String, String)] = [
            ("&#39;", "'"), ("&amp;", "&"), ("&quot;", "\""),
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&#160;", " "), ("&#x27;", "'"), ("&#x2F;", "/"),
            ("&apos;", "'"), ("&hellip;", "…"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&laquo;", "«"), ("&raquo;", "»"),
            ("&bull;", "•"), ("&copy;", "©"), ("&reg;", "®"),
            ("&trade;", "™"), ("&shy;", ""), ("&zwnj;", ""),
            ("&zwj;", ""), ("&lrm;", ""), ("&rlm;", "")
        ]
        for (entity, replacement) in htmlEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        if let regex = numericEntityRegex {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        if let junk = junkRegex {
            let range = NSRange(text.startIndex..., in: text)
            text = junk.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Email Errors
enum EmailError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to access your emails"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        }
    }
}
