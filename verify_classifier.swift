#!/usr/bin/env swift
import Foundation

// Copy of QueryClassifier logic for verification
enum MessageIntent: String {
    case photoSearch
    case conversation
    case followUp
}

struct AIMessage {
    enum Role { case user, assistant }
    enum State { case complete }
    let role: Role
    let content: String
    let state: State
    let assetIds: [String]?
}

func normalize(_ text: String) -> String {
    var result = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = result.last, "?!.".contains(last) {
        result.removeLast()
    }
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return result
}

func isFollowUp(_ normalized: String, previousMessages: [AIMessage]) -> Bool {
    let recentMessages = Array(previousMessages.suffix(4))
    let hasPreviousResults = recentMessages.reversed().contains { msg in
        msg.role == .assistant &&
        msg.state == .complete &&
        msg.assetIds != nil &&
        !(msg.assetIds?.isEmpty ?? true)
    }

    guard hasPreviousResults else { return false }

    let newSearchVerbs = ["find", "show", "pull up", "get me", "search for"]
    if newSearchVerbs.contains(where: { normalized.contains($0) }) { return false }

    let photoNouns = ["pics", "photos", "pictures", "images"]
    if photoNouns.contains(where: { normalized.contains($0) }) { return false }

    var hasFollowUpSignal = false

    let pronouns = ["they", "them", "these", "those", "it", "this one", "that one"]
    if pronouns.contains(where: { normalized.contains($0) }) { hasFollowUpSignal = true }

    let comparisonWords = ["or", "vs", "versus", "better", "worse", "prefer", "favorite", "which"]
    if comparisonWords.contains(where: { normalized.contains($0) }) { hasFollowUpSignal = true }

    let opinionPhrases = ["you think", "do you", "your opinion", "what do you", "which one", "which is", "isn't", "aren't"]
    if opinionPhrases.contains(where: { normalized.contains($0) }) { hasFollowUpSignal = true }

    let definitePhrases = ["the purple", "the yellow", "the first", "the last",
                           "the blurry", "the one with", "the second", "the third"]
    if definitePhrases.contains(where: { normalized.contains($0) }) { hasFollowUpSignal = true }

    return hasFollowUpSignal
}

func isConversation(_ normalized: String) -> Bool {
    let greetingPattern = "^(hi|hey|hello|yo|sup|good morning|good night|good evening|what's up|wassup|howdy)( bee)?$"
    if normalized.range(of: greetingPattern, options: .regularExpression) != nil { return true }

    let orphanFollowUpPatterns = [
        "which is your", "which one", "your favorite", "do you prefer",
        "do you like", "what do you think", "isn't", "aren't"
    ]
    let hasPhotoContext = ["pic", "photo", "image", "selfie", "screenshot"].contains(where: { normalized.contains($0) })
    if !hasPhotoContext && orphanFollowUpPatterns.contains(where: { normalized.contains($0) }) {
        return true
    }

    let metaQuestions = [
        "how are you", "how's it going", "how you doing",
        "what can you do", "who are you", "are you ai", "are you real",
        "what are you", "are you human", "how do you work"
    ]
    if metaQuestions.contains(where: { normalized.contains($0) }) { return true }

    let acknowledgments = [
        "thanks", "thank you", "ty", "okay", "ok", "cool", "nice",
        "lol", "lmao", "haha", "hahaha", "yeah", "yes", "no", "nope",
        "sure", "alright"
    ]
    if acknowledgments.contains(normalized) { return true }

    let beeAddressPattern = "^(bee|hi bee|hey bee)$"
    if normalized.range(of: beeAddressPattern, options: .regularExpression) != nil { return true }

    let statePhrases = [
        "i'm bored", "i'm tired", "i'm sad", "i had a long day",
        "i miss", "i love you"
    ]
    if statePhrases.contains(where: { normalized.contains($0) }) { return true }

    let compliments = [
        "you're funny", "you're cool", "you're cute", "you're so", "i like you", "nice work"
    ]
    if compliments.contains(where: { normalized.contains($0) }) { return true }

    let wordCount = normalized.split(separator: " ").count
    if wordCount < 3 {
        let photoNouns = ["pics", "photos", "pictures", "images", "selfies",
                         "screenshots", "beach", "dog", "cat", "food", "wedding"]
        let hasPhotoNoun = photoNouns.contains(where: { normalized.contains($0) })

        let followUpSignals = ["they", "them", "these", "those", "it",
                               "or", "vs", "prefer"]
        let hasFollowUpSignal = followUpSignals.contains(where: { normalized.contains($0) })

        if normalized == "which" || normalized == "favorite" { return true }

        if !hasPhotoNoun && !hasFollowUpSignal { return true }
    }

    return false
}

func classify(_ text: String, previousMessages: [AIMessage]) -> MessageIntent {
    let normalized = normalize(text)
    guard !normalized.isEmpty else { return .conversation }

    if isFollowUp(normalized, previousMessages: previousMessages) { return .followUp }
    if isConversation(normalized) { return .conversation }
    return .photoSearch
}

// Test runner
var passed = 0
var failed = 0

func test(_ name: String, _ query: String, expected: MessageIntent, previousMessages: [AIMessage] = []) {
    let result = classify(query, previousMessages: previousMessages)
    if result == expected {
        passed += 1
        print("✓ \(name)")
    } else {
        failed += 1
        print("✗ \(name): expected \(expected.rawValue), got \(result.rawValue)")
    }
}

func mockAssistant(assetIds: [String] = ["photo1", "photo2"]) -> AIMessage {
    AIMessage(role: .assistant, content: "Here are your photos", state: .complete, assetIds: assetIds)
}

func mockUser(_ text: String) -> AIMessage {
    AIMessage(role: .user, content: text, state: .complete, assetIds: nil)
}

print("Running QueryClassifier Verification Tests\n")

// Greetings (10 tests)
test("Greeting: hi", "hi", expected: .conversation)
test("Greeting: hi bee", "hi bee", expected: .conversation)
test("Greeting: hey", "hey", expected: .conversation)
test("Greeting: hey bee", "hey bee", expected: .conversation)
test("Greeting: hello", "hello", expected: .conversation)
test("Greeting: HI BEE!!!", "HI BEE!!!", expected: .conversation)
test("Greeting: yo", "yo", expected: .conversation)
test("Greeting: good morning bee", "good morning bee", expected: .conversation)
test("Greeting: sup", "sup", expected: .conversation)
test("Greeting: wassup", "wassup", expected: .conversation)

// Meta questions (10 tests)
test("Meta: how are you", "how are you", expected: .conversation)
test("Meta: how you doing", "how you doing", expected: .conversation)
test("Meta: what can you do", "what can you do", expected: .conversation)
test("Meta: who are you", "who are you", expected: .conversation)
test("Meta: are you ai", "are you ai", expected: .conversation)
test("Meta: are you real", "are you real", expected: .conversation)
test("Meta: how do you work", "how do you work", expected: .conversation)
test("Meta: what are you", "what are you", expected: .conversation)
test("Meta: are you human", "are you human", expected: .conversation)
test("Meta: how's it going", "how's it going", expected: .conversation)

// Acknowledgments (8 tests)
test("Ack: thanks", "thanks", expected: .conversation)
test("Ack: ok", "ok", expected: .conversation)
test("Ack: okay", "okay", expected: .conversation)
test("Ack: cool", "cool", expected: .conversation)
test("Ack: lol", "lol", expected: .conversation)
test("Ack: haha", "haha", expected: .conversation)
test("Ack: yeah", "yeah", expected: .conversation)
test("Ack: nice", "nice", expected: .conversation)

// Photo search (15 tests)
test("Search: find pics of beach", "find pics of beach", expected: .photoSearch)
test("Search: show me my dog", "show me my dog", expected: .photoSearch)
test("Search: pictures from last summer", "pictures from last summer", expected: .photoSearch)
test("Search: selfies", "selfies", expected: .photoSearch)
test("Search: screenshots", "screenshots", expected: .photoSearch)
test("Search: show me food pics", "show me food pics", expected: .photoSearch)
test("Search: pull up wedding photos", "pull up wedding photos", expected: .photoSearch)
test("Search: get me pics of mom", "get me pics of mom", expected: .photoSearch)
test("Search: find pics from new york", "find pics from new york", expected: .photoSearch)
test("Search: show me pictures of sunsets", "show me pictures of sunsets", expected: .photoSearch)
test("Search: beach photos from 2019", "beach photos from 2019", expected: .photoSearch)
test("Search: find my best friend", "find my best friend", expected: .photoSearch)
test("Search: pictures of my cat", "pictures of my cat", expected: .photoSearch)
test("Search: show selfies", "show selfies", expected: .photoSearch)
test("Search: find european trip pics", "find european trip pics", expected: .photoSearch)

// Follow-ups (12 tests, require previous results)
let withResults = [mockUser("show me flowers"), mockAssistant()]
test("FollowUp: which is your favorite", "which is your favorite", expected: .followUp, previousMessages: withResults)
test("FollowUp: do you prefer purple or yellow", "do you prefer the purple or yellow", expected: .followUp, previousMessages: withResults)
test("FollowUp: isn't she cute", "isn't she cute", expected: .followUp, previousMessages: withResults)
test("FollowUp: which one do you like", "which one do you like", expected: .followUp, previousMessages: withResults)
test("FollowUp: what do you think", "what do you think", expected: .followUp, previousMessages: withResults)
test("FollowUp: which one is your fav", "which one is your fav", expected: .followUp, previousMessages: withResults)
test("FollowUp: the first or the last", "the first or the last", expected: .followUp, previousMessages: withResults)
test("FollowUp: do you like the second one", "do you like the second one", expected: .followUp, previousMessages: withResults)
test("FollowUp: the blurry one is funny", "the blurry one is funny", expected: .followUp, previousMessages: withResults)
test("FollowUp: which is prettier", "which is prettier", expected: .followUp, previousMessages: withResults)
test("FollowUp: your favorite of these", "your favorite of these", expected: .followUp, previousMessages: withResults)
test("FollowUp: the one with the toy", "the one with the toy", expected: .followUp, previousMessages: withResults)

// Search after results (should NOT be follow-up)
test("SearchAfterResults: show me dogs", "show me dogs", expected: .photoSearch, previousMessages: withResults)
test("SearchAfterResults: find pics from college", "find pics from college", expected: .photoSearch, previousMessages: withResults)
test("SearchAfterResults: pictures of food", "pictures of food", expected: .photoSearch, previousMessages: withResults)
test("SearchAfterResults: show me my mom", "show me my mom", expected: .photoSearch, previousMessages: withResults)
test("SearchAfterResults: selfies", "selfies", expected: .photoSearch, previousMessages: withResults)

// Edge cases (10 tests)
test("Edge: empty string", "", expected: .conversation)
test("Edge: just 'the'", "the", expected: .conversation)
test("Edge: just 'bee'", "bee", expected: .conversation)
test("Edge: beach (one word)", "beach", expected: .photoSearch)
test("Edge: which (no previous results)", "which", expected: .conversation)
test("Edge: what alone", "what", expected: .conversation)
test("Edge: i'm bored", "i'm bored", expected: .conversation)
test("Edge: i love you", "i love you", expected: .conversation)
test("Edge: you're so cool", "you're so cool", expected: .conversation)

// Additional edge cases from test suite
test("Edge: followup requires results", "which is your favorite", expected: .conversation)
let emptyAssets = [mockUser("show me flowers"), mockAssistant(assetIds: [])]
test("Edge: empty assetIds", "which is your favorite", expected: .conversation, previousMessages: emptyAssets)

print("\n" + String(repeating: "=", count: 50))
print("Results: \(passed) passed, \(failed) failed")
print(String(repeating: "=", count: 50))

exit(failed == 0 ? 0 : 1)
