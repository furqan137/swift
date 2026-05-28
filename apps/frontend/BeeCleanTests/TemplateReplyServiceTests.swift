import XCTest
@testable import BeeClean

final class TemplateReplyServiceTests: XCTestCase {

    let service = TemplateReplyService.shared

    // MARK: - Determinism

    func testDeterminism() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 25,
            contentQuery: "beach", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "beach photos"
        )
        let first = service.reply(for: ctx)
        for _ in 0..<10 {
            XCTAssertEqual(service.reply(for: ctx), first, "Same input must produce the same output")
        }
    }

    // MARK: - Variant Spread

    func testVariantSpread() {
        let queries = ["beach photos", "cat pictures", "sunset images", "dogs playing",
                       "food pics", "mountain views", "city skyline", "flowers garden"]
        var replies = Set<String>()
        for q in queries {
            let ctx = ReplyContext(
                intent: .photoSearch, action: .findByContent, resultCount: 15,
                contentQuery: q.components(separatedBy: " ").first, location: nil,
                datePhrase: nil, dateRange: nil, originalQuery: q
            )
            replies.insert(service.reply(for: ctx))
        }
        XCTAssertGreaterThan(replies.count, 1, "Different queries should produce different variants")
    }

    // MARK: - No Unsubstituted Tokens

    func testNoUnsubstitutedTokens() {
        let intents: [MessageIntent] = [.photoSearch, .conversation, .followUp]
        let actions: [AIActionType?] = [.findByContent, .findByDate, .findByLocation,
                                         .findLargest, .findDuplicates, .findScreenshots, nil]
        let counts = [0, 1, 5, 50]
        let queries = ["test query", "another search", "hello there"]

        for intent in intents {
            for action in actions {
                for count in counts {
                    for q in queries {
                        let ctx = ReplyContext(
                            intent: intent, action: action, resultCount: count,
                            contentQuery: "stuff", location: "Paris",
                            datePhrase: "last summer", dateRange: nil,
                            originalQuery: q
                        )
                        let reply = service.reply(for: ctx)
                        XCTAssertFalse(reply.contains("{count}"), "Unsubstituted {count} in: \(reply)")
                        XCTAssertFalse(reply.contains("{content}"), "Unsubstituted {content} in: \(reply)")
                        XCTAssertFalse(reply.contains("{location}"), "Unsubstituted {location} in: \(reply)")
                        XCTAssertFalse(reply.contains("{dateLabel}"), "Unsubstituted {dateLabel} in: \(reply)")
                    }
                }
            }
        }
    }

    // MARK: - Snapshot Tests

    func testSnapshotBeachPhotosMany() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 42,
            contentQuery: "beach", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "beach photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertFalse(reply.isEmpty)
        XCTAssertTrue(reply.contains("beach"), "Should mention content query")
    }

    func testSnapshotCatsFew() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 3,
            contentQuery: "cats", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "show me cats"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("3"))
        XCTAssertTrue(reply.contains("cats"))
    }

    func testSnapshotDateSearch() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByDate, resultCount: 20,
            contentQuery: nil, location: nil, datePhrase: "last summer",
            dateRange: nil, originalQuery: "photos from last summer"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("last summer"))
    }

    func testSnapshotLocationSearch() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByLocation, resultCount: 15,
            contentQuery: nil, location: "Paris", datePhrase: nil,
            dateRange: nil, originalQuery: "photos in Paris"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("Paris"))
    }

    func testSnapshotContentLocationDate() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 8,
            contentQuery: "sunset", location: "Hawaii", datePhrase: "2023",
            dateRange: nil, originalQuery: "sunset in Hawaii from 2023"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("sunset"))
        XCTAssertTrue(reply.contains("Hawaii"))
        XCTAssertTrue(reply.contains("2023"))
    }

    func testSnapshotDuplicates() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findDuplicates, resultCount: 30,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "duplicates"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.lowercased().contains("duplicate"))
    }

    func testSnapshotScreenshots() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findScreenshots, resultCount: 50,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "screenshots"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.lowercased().contains("screenshot"))
    }

    func testSnapshotLargest() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findLargest, resultCount: 10,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "largest photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.lowercased().contains("large") || reply.lowercased().contains("big"))
    }

    func testSnapshotGreeting() {
        let ctx = ReplyContext(
            intent: .conversation, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "hi"
        )
        let reply = service.reply(for: ctx)
        XCTAssertFalse(reply.isEmpty)
    }

    func testSnapshotMeta() {
        let ctx = ReplyContext(
            intent: .conversation, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "what can you do"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("photo"), "Meta reply should mention photos")
    }

    func testSnapshotThanks() {
        let ctx = ReplyContext(
            intent: .conversation, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "thanks"
        )
        let reply = service.reply(for: ctx)
        XCTAssertFalse(reply.isEmpty)
    }

    func testSnapshotFollowUp() {
        let ctx = ReplyContext(
            intent: .followUp, action: nil, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "which one do you prefer"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.lowercased().contains("see") || reply.lowercased().contains("find") || reply.lowercased().contains("search"))
    }

    func testSnapshotZeroResultContent() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 0,
            contentQuery: "unicorn", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "unicorn photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertFalse(reply.isEmpty)
        XCTAssertTrue(reply.contains("unicorn"))
    }

    func testSnapshotZeroResultDate() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByDate, resultCount: 0,
            contentQuery: nil, location: nil, datePhrase: "January 2010",
            dateRange: nil, originalQuery: "photos from January 2010"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("January 2010"))
    }

    func testSnapshotZeroResultLocation() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByLocation, resultCount: 0,
            contentQuery: nil, location: "Antarctica", datePhrase: nil,
            dateRange: nil, originalQuery: "photos from Antarctica"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("Antarctica"))
    }

    func testSnapshotSingleResult() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 1,
            contentQuery: "wedding", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "wedding photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("1"))
    }

    func testSnapshotUnicodeLocation() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByLocation, resultCount: 5,
            contentQuery: nil, location: "S\u{00E3}o Paulo", datePhrase: nil,
            dateRange: nil, originalQuery: "photos in S\u{00E3}o Paulo"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("S\u{00E3}o Paulo"))
    }

    func testSnapshotLongContentQueryTruncation() {
        let longQuery = "a very long content query string that exceeds thirty characters easily"
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 10,
            contentQuery: longQuery, location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: longQuery
        )
        let reply = service.reply(for: ctx)
        XCTAssertFalse(reply.contains(longQuery), "Long content should be truncated")
        XCTAssertTrue(reply.contains("\u{2026}"), "Truncated content should have ellipsis")
    }

    // MARK: - Edge Cases

    func testZeroResultsNoEmoji() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 0,
            contentQuery: "party", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "party photos"
        )
        let reply = service.reply(for: ctx)
        // Zero results should not have celebration
        XCTAssertFalse(reply.contains("!") && reply.contains("Found") && reply.contains("0"),
                        "Zero results should not sound celebratory")
    }

    func testSingularPhrasing() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 1,
            contentQuery: "car", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "car photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("1"))
    }

    func testManyBucketForLargeCount() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 1000,
            contentQuery: "nature", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "nature photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("1000"))
    }

    // MARK: - Pluralization Helper

    func testPluralSingular() {
        // Access via a photo search with 1 result — the template uses singular form
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 1,
            contentQuery: "tree", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "tree photo"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("1"), "Single result should show count 1")
    }

    func testPluralPlural() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByContent, resultCount: 5,
            contentQuery: "tree", location: nil, datePhrase: nil, dateRange: nil,
            originalQuery: "tree photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("5"))
    }

    // MARK: - Date Range Fallback

    func testDateRangeFallbackWhenNoPhraseProvided() {
        let ctx = ReplyContext(
            intent: .photoSearch, action: .findByDate, resultCount: 10,
            contentQuery: nil, location: nil, datePhrase: nil,
            dateRange: AIDateRange(start: "2023-06-01", end: "2023-08-31"),
            originalQuery: "summer 2023 photos"
        )
        let reply = service.reply(for: ctx)
        XCTAssertTrue(reply.contains("2023-06-01") || reply.contains("2023-08-31"),
                       "Should fall back to date range formatting")
    }
}
