import Foundation

// MARK: - Reply Context

struct ReplyContext {
    let intent: MessageIntent
    let action: AIActionType?
    let resultCount: Int
    let contentQuery: String?
    let location: String?
    let datePhrase: String?
    let dateRange: AIDateRange?
    let originalQuery: String
}

// MARK: - Result Count Bucket

enum ResultCountBucket {
    case zero, one, few, many

    init(_ count: Int) {
        switch count {
        case 0: self = .zero
        case 1: self = .one
        case 2...9: self = .few
        default: self = .many
        }
    }
}

// MARK: - Template Reply Service

final class TemplateReplyService {
    static let shared = TemplateReplyService()
    private init() {}

    func reply(for ctx: ReplyContext) -> String {
        switch ctx.intent {
        case .photoSearch:
            return photoSearchReply(ctx)
        case .conversation:
            return conversationReply(ctx)
        case .followUp:
            return followUpReply(ctx)
        }
    }

    // MARK: - Helpers

    private func plural(_ n: Int, _ singular: String, _ plural: String) -> String {
        n == 1 ? singular : plural
    }

    private func humanizeDate(phrase: String?, range: AIDateRange?) -> String? {
        if let phrase = phrase, !phrase.isEmpty { return phrase }
        guard let range = range else { return nil }
        if let start = range.start, let end = range.end {
            return "from \(start) to \(end)"
        } else if let start = range.start {
            return "since \(start)"
        } else if let end = range.end {
            return "before \(end)"
        }
        return nil
    }

    private func truncateContent(_ s: String?, maxLen: Int = 30) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        if s.count <= maxLen { return s }
        return String(s.prefix(maxLen - 1)) + "\u{2026}"
    }

    /// Deterministic variant index derived from the original query.
    private func variantIndex(for query: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return abs(query.lowercased().hashValue) % count
    }

    /// Substitute tokens in a template string.
    private func substitute(_ template: String, ctx: ReplyContext) -> String {
        var s = template
        s = s.replacingOccurrences(of: "{count}", with: "\(ctx.resultCount)")
        if let c = truncateContent(ctx.contentQuery) {
            s = s.replacingOccurrences(of: "{content}", with: c)
        }
        if let loc = ctx.location {
            s = s.replacingOccurrences(of: "{location}", with: loc)
        }
        if let d = humanizeDate(phrase: ctx.datePhrase, range: ctx.dateRange) {
            s = s.replacingOccurrences(of: "{dateLabel}", with: d)
        }
        return s
    }

    // MARK: - Photo Search Reply

    private func photoSearchReply(_ ctx: ReplyContext) -> String {
        guard let action = ctx.action else {
            return genericPhotoReply(ctx)
        }

        switch action {
        case .findByContent:
            return contentReply(ctx)
        case .findByDate:
            return dateReply(ctx)
        case .findByLocation:
            return locationReply(ctx)
        case .findLargest:
            return largestReply(ctx)
        case .findDuplicates:
            return duplicatesReply(ctx)
        case .findScreenshots:
            return screenshotsReply(ctx)
        default:
            return genericPhotoReply(ctx)
        }
    }

    // MARK: - FIND_BY_CONTENT

    private func contentReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)
        let hasLoc = ctx.location != nil && !ctx.location!.isEmpty
        let hasDate = humanizeDate(phrase: ctx.datePhrase, range: ctx.dateRange) != nil

        let templates: [String]
        switch (bucket, hasLoc, hasDate) {
        case (.zero, false, false):
            templates = [
                "Hmm, I couldn't find any {content} photos.",
                "No {content} photos turned up. Try different wording?",
                "Came up empty on {content}. Maybe try a broader search?"
            ]
        case (.zero, true, false):
            templates = [
                "No {content} photos in {location}. Try a different search?",
                "Couldn't find {content} in {location}.",
                "Nothing for {content} in {location}. Want to try without the location?"
            ]
        case (.zero, false, true):
            templates = [
                "No {content} photos {dateLabel}. Try a wider date range?",
                "Couldn't find {content} {dateLabel}.",
                "Nothing for {content} {dateLabel}. Maybe adjust the timeframe?"
            ]
        case (.zero, true, true):
            templates = [
                "No {content} photos in {location} {dateLabel}.",
                "Couldn't find {content} in {location} {dateLabel}.",
                "Nothing for {content} in {location} {dateLabel}. Try broadening your search?"
            ]
        case (.one, false, false):
            templates = [
                "Found 1 {content} photo. Here it is.",
                "Just the one {content} photo. Take a look.",
                "Pulled 1 {content} photo for you."
            ]
        case (.one, true, false):
            templates = [
                "Found 1 {content} photo in {location}.",
                "Just one {content} photo from {location}. Here it is.",
                "Pulled 1 {content} photo in {location}."
            ]
        case (.one, false, true):
            templates = [
                "Found 1 {content} photo {dateLabel}.",
                "Just one {content} photo {dateLabel}. Take a look.",
                "Pulled 1 {content} photo {dateLabel}."
            ]
        case (.one, true, true):
            templates = [
                "Found 1 {content} photo in {location} {dateLabel}.",
                "Just one {content} photo from {location} {dateLabel}.",
                "Pulled 1 {content} photo in {location} {dateLabel}."
            ]
        case (.few, false, false):
            templates = [
                "Found {count} {content} photos. Here they are.",
                "Pulled {count} {content} photos for you.",
                "{count} {content} photos. Take a look."
            ]
        case (.few, true, false):
            templates = [
                "Found {count} {content} photos in {location}.",
                "{count} {content} photos from {location}. Here they are.",
                "Pulled {count} {content} photos in {location}."
            ]
        case (.few, false, true):
            templates = [
                "Found {count} {content} photos {dateLabel}.",
                "{count} {content} photos {dateLabel}. Take a look.",
                "Pulled {count} {content} photos {dateLabel}."
            ]
        case (.few, true, true):
            templates = [
                "Found {count} {content} photos in {location} {dateLabel}.",
                "{count} {content} photos from {location} {dateLabel}.",
                "Pulled {count} {content} photos in {location} {dateLabel}."
            ]
        case (.many, false, false):
            templates = [
                "Found {count} {content} photos. Here they are.",
                "{count} {content} photos pulled up for you.",
                "Lots of {content} photos. Here are {count}."
            ]
        case (.many, true, false):
            templates = [
                "Found {count} {content} photos in {location}.",
                "{count} {content} photos from {location}.",
                "Pulled {count} {content} photos in {location}."
            ]
        case (.many, false, true):
            templates = [
                "Found {count} {content} photos {dateLabel}.",
                "{count} {content} photos {dateLabel}.",
                "Pulled {count} {content} photos {dateLabel}."
            ]
        case (.many, true, true):
            templates = [
                "Found {count} {content} photos in {location} {dateLabel}.",
                "{count} {content} photos from {location} {dateLabel}.",
                "Pulled {count} {content} photos in {location} {dateLabel}."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - FIND_BY_DATE

    private func dateReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)
        let dateLabel = humanizeDate(phrase: ctx.datePhrase, range: ctx.dateRange) ?? "that time"

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "No photos \(dateLabel). Try a different date range?",
                "Couldn't find anything \(dateLabel).",
                "Nothing turned up \(dateLabel). Maybe widen the range?"
            ]
        case .one:
            templates = [
                "Found 1 photo \(dateLabel). Here it is.",
                "Just one photo \(dateLabel). Take a look.",
                "Pulled 1 photo \(dateLabel)."
            ]
        case .few:
            templates = [
                "Found {count} photos \(dateLabel).",
                "{count} photos \(dateLabel). Here they are.",
                "Pulled {count} photos \(dateLabel)."
            ]
        case .many:
            templates = [
                "Found {count} photos \(dateLabel).",
                "{count} photos \(dateLabel). Take a look.",
                "Lots of photos \(dateLabel). Here are {count}."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - FIND_BY_LOCATION

    private func locationReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)
        let loc = ctx.location ?? "that location"

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "No photos from \(loc). Try a different place?",
                "Couldn't find any photos in \(loc).",
                "Nothing from \(loc) turned up."
            ]
        case .one:
            templates = [
                "Found 1 photo from \(loc). Here it is.",
                "Just one photo from \(loc). Take a look.",
                "Pulled 1 photo from \(loc)."
            ]
        case .few:
            templates = [
                "Found {count} photos from \(loc).",
                "{count} photos from \(loc). Here they are.",
                "Pulled {count} photos from \(loc)."
            ]
        case .many:
            templates = [
                "Found {count} photos from \(loc).",
                "{count} photos from \(loc). Take a look.",
                "Lots of photos from \(loc). Here are {count}."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - FIND_LARGEST

    private func largestReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "No large files found.",
                "Couldn't find any big files to show."
            ]
        case .one:
            templates = [
                "Here's your biggest file.",
                "Found the largest one. Take a look."
            ]
        case .few:
            templates = [
                "Here are your {count} largest files.",
                "Found {count} big files. Take a look.",
                "Pulled your top {count} largest files."
            ]
        case .many:
            templates = [
                "Here are the {count} largest files.",
                "Found {count} big files. These are the heaviest.",
                "Pulled {count} large files for you."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - FIND_DUPLICATES

    private func duplicatesReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "No duplicates found. Your library looks clean!",
                "Couldn't find any duplicate photos.",
                "All clear on duplicates."
            ]
        case .one:
            templates = [
                "Found 1 duplicate. Here it is.",
                "Just one duplicate turned up."
            ]
        case .few:
            templates = [
                "Found {count} duplicates. Take a look.",
                "{count} duplicates found. Here they are.",
                "Pulled {count} duplicate photos."
            ]
        case .many:
            templates = [
                "Found {count} duplicates. Time to clean up!",
                "{count} duplicates found. Here they are.",
                "Pulled {count} duplicate photos. That's some space you can free up."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - FIND_SCREENSHOTS

    private func screenshotsReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "No screenshots found.",
                "Couldn't find any screenshots."
            ]
        case .one:
            templates = [
                "Found 1 screenshot. Here it is.",
                "Just one screenshot turned up."
            ]
        case .few:
            templates = [
                "Found {count} screenshots. Take a look.",
                "{count} screenshots pulled up.",
                "Here are your {count} screenshots."
            ]
        case .many:
            templates = [
                "Found {count} screenshots.",
                "{count} screenshots. Here they are.",
                "Pulled {count} screenshots for you."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - Generic Photo Fallback

    private func genericPhotoReply(_ ctx: ReplyContext) -> String {
        let bucket = ResultCountBucket(ctx.resultCount)

        let templates: [String]
        switch bucket {
        case .zero:
            templates = [
                "Hmm, nothing came up. Try a different search?",
                "No results found. Want to try different wording?",
                "Came up empty on this one."
            ]
        case .one:
            templates = [
                "Found 1 result. Here it is.",
                "Just one result. Take a look."
            ]
        case .few:
            templates = [
                "Found {count} results. Here they are.",
                "Pulled {count} results for you.",
                "{count} results. Take a look."
            ]
        case .many:
            templates = [
                "Found {count} results. Here they are.",
                "{count} results pulled up for you.",
                "Here are {count} results."
            ]
        }

        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return substitute(templates[idx], ctx: ctx)
    }

    // MARK: - Conversation Reply

    private func conversationReply(_ ctx: ReplyContext) -> String {
        let q = ctx.originalQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Greeting triggers
        let greetings = ["hi", "hey", "hello", "yo", "sup", "what's up", "whats up", "hola", "howdy"]
        if greetings.contains(where: { q == $0 || q.hasPrefix($0 + " ") || q.hasPrefix($0 + "!") }) {
            let templates = [
                "Hey! What are we looking for today?",
                "Hi! Want to search for some photos?",
                "Hey there! What can I find for you?"
            ]
            let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
            return templates[idx]
        }

        // Meta/help triggers
        let helpTriggers = ["what can you do", "help", "how do you work", "what do you do", "capabilities"]
        if helpTriggers.contains(where: { q.contains($0) }) {
            return "I can search your photos by content, date, location, or type. Try asking me things like \"beach photos\", \"photos from last summer\", \"pics in Paris\", \"duplicates\", or \"screenshots\"."
        }

        // Thanks triggers
        let thanksTriggers = ["thank", "thanks", "thx", "ty", "appreciate"]
        if thanksTriggers.contains(where: { q.contains($0) }) {
            let templates = [
                "Anytime!",
                "You got it!",
                "Happy to help!"
            ]
            let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
            return templates[idx]
        }

        // Default conversation fallback
        let templates = [
            "I'm best at finding photos. Try asking me to search for something!",
            "Not sure I follow. Want to search for some photos?",
            "I'm your photo search buddy. What are we looking for?",
            "Try asking me about your photos. I can search by content, date, or location."
        ]
        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return templates[idx]
    }

    // MARK: - Follow-Up Reply

    private func followUpReply(_ ctx: ReplyContext) -> String {
        let templates = [
            "I can find photos but can't actually see them. What do you think?",
            "Wish I could see them with you! I can only search, not view.",
            "I can't see the photos from here. Tell me what you think!",
            "I only know how to find them. Which one stands out to you?"
        ]
        let idx = variantIndex(for: ctx.originalQuery, count: templates.count)
        return templates[idx]
    }
}
