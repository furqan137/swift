import Foundation

// MARK: - Message Intent

enum MessageIntent: String, Codable {
    case photoSearch
    case conversation
    case followUp
}

// MARK: - Query Classifier

/// On-device, deterministic classifier for user messages.
/// NO ML, NO LLM — pure keyword-based rules.
struct QueryClassifier {

    /// Classify a user message into one of three intents.
    ///
    /// Priority order:
    /// 1. .followUp (if previous results exist AND message has follow-up signals)
    /// 2. .conversation (greetings, meta questions, acknowledgments)
    /// 3. .photoSearch (default for content queries)
    ///
    /// - Parameters:
    ///   - text: The user's message
    ///   - previousMessages: Recent message history (used for follow-up detection)
    /// - Returns: The classified intent
    static func classify(
        _ text: String,
        previousMessages: [AIMessage]
    ) -> MessageIntent {

        // Step 1a: Normalize input
        let normalized = normalize(text)

        guard !normalized.isEmpty else {
            return .conversation // Safe default for empty input
        }

        // Step 1b: Check for .followUp FIRST
        if isFollowUp(normalized, previousMessages: previousMessages) {
            return .followUp
        }

        // Step 1c: Check for .conversation
        if isConversation(normalized) {
            return .conversation
        }

        // Step 1d: Default to .photoSearch
        return .photoSearch
    }

    // MARK: - Normalization

    private static func normalize(_ text: String) -> String {
        var result = text.lowercased()
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip trailing punctuation (?, !, ., multiple)
        while let last = result.last, "?!.".contains(last) {
            result.removeLast()
        }

        // Collapse multiple spaces
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return result
    }

    // MARK: - Follow-up Detection

    private static func isFollowUp(
        _ normalized: String,
        previousMessages: [AIMessage]
    ) -> Bool {

        // Condition A: Recent assistant message with photo results
        let recentMessages = Array(previousMessages.suffix(4))
        let hasPreviousResults = recentMessages.reversed().contains { msg in
            msg.role == .assistant &&
            msg.state == .complete &&
            msg.assetIds != nil &&
            !(msg.assetIds?.isEmpty ?? true)
        }

        guard hasPreviousResults else {
            return false // No previous results to follow up on
        }

        // Condition B: Message has follow-up signals AND NOT new-search signals

        // Check for new-search signals first (disqualifies follow-up)
        let newSearchVerbs = ["find", "show", "pull up", "get me", "search for"]
        if newSearchVerbs.contains(where: { normalized.contains($0) }) {
            return false
        }

        let photoNouns = ["pics", "photos", "pictures", "images"]
        if photoNouns.contains(where: { normalized.contains($0) }) {
            return false
        }

        // Check for follow-up signals
        var hasFollowUpSignal = false

        // Pronouns referencing prior content
        let pronouns = ["they", "them", "these", "those", "it", "this one", "that one"]
        if pronouns.contains(where: { normalized.contains($0) }) {
            hasFollowUpSignal = true
        }

        // Comparison/preference words
        let comparisonWords = ["or", "vs", "versus", "better", "worse", "prefer", "favorite", "which"]
        if comparisonWords.contains(where: { normalized.contains($0) }) {
            hasFollowUpSignal = true
        }

        // Opinion solicitations and statements
        let opinionPhrases = ["you think", "do you", "your opinion", "what do you", "which one", "which is", "isn't", "aren't"]
        if opinionPhrases.contains(where: { normalized.contains($0) }) {
            hasFollowUpSignal = true
        }

        // Definite article + descriptor patterns
        let definitePhrases = ["the purple", "the yellow", "the first", "the last",
                               "the blurry", "the one with", "the second", "the third"]
        if definitePhrases.contains(where: { normalized.contains($0) }) {
            hasFollowUpSignal = true
        }

        return hasFollowUpSignal
    }

    // MARK: - Conversation Detection

    private static func isConversation(_ normalized: String) -> Bool {

        // Greeting patterns (exact match)
        let greetingPattern = "^(hi|hey|hello|yo|sup|good morning|good night|good evening|what's up|wassup|howdy)( bee)?$"
        if normalized.range(of: greetingPattern, options: .regularExpression) != nil {
            return true
        }

        // Queries that look like follow-ups but lack photo-related context
        // (e.g., "which is your favorite" with no previous results)
        let orphanFollowUpPatterns = [
            "which is your", "which one", "your favorite", "do you prefer",
            "do you like", "what do you think", "isn't", "aren't"
        ]
        let hasPhotoContext = ["pic", "photo", "image", "selfie", "screenshot"].contains(where: { normalized.contains($0) })
        if !hasPhotoContext && orphanFollowUpPatterns.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Asks about Bee
        let metaQuestions = [
            "how are you", "how's it going", "how you doing",
            "what can you do", "who are you", "are you ai", "are you real",
            "what are you", "are you human", "how do you work"
        ]
        if metaQuestions.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Pure acknowledgments (exact match)
        let acknowledgments = [
            "thanks", "thank you", "ty", "okay", "ok", "cool", "nice",
            "lol", "lmao", "haha", "hahaha", "yeah", "yes", "no", "nope",
            "sure", "alright"
        ]
        if acknowledgments.contains(normalized) {
            return true
        }

        // Just addresses Bee
        let beeAddressPattern = "^(bee|hi bee|hey bee)$"
        if normalized.range(of: beeAddressPattern, options: .regularExpression) != nil {
            return true
        }

        // Direct expression of state
        let statePhrases = [
            "i'm bored", "i'm tired", "i'm sad", "i had a long day",
            "i miss", "i love you"
        ]
        if statePhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Compliments/comments about Bee
        let compliments = [
            "you're funny", "you're cool", "you're cute", "you're so", "i like you", "nice work"
        ]
        if compliments.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Under 3 words with no photo-related nouns AND no follow-up signals
        let wordCount = normalized.split(separator: " ").count
        if wordCount < 3 {
            let photoNouns = ["pics", "photos", "pictures", "images", "selfies",
                             "screenshots", "beach", "dog", "cat", "food", "wedding"]
            let hasPhotoNoun = photoNouns.contains(where: { normalized.contains($0) })

            let followUpSignals = ["they", "them", "these", "those", "it",
                                   "or", "vs", "prefer"]
            let hasFollowUpSignal = followUpSignals.contains(where: { normalized.contains($0) })

            // Single word "which" or "favorite" should be conversation
            if normalized == "which" || normalized == "favorite" {
                return true
            }

            if !hasPhotoNoun && !hasFollowUpSignal {
                return true
            }
        }

        return false
    }
}
