import XCTest
@testable import BeeClean

final class QueryParserTests: XCTestCase {

    let knownLocations = [
        "San Francisco",
        "New York",
        "Los Angeles",
        "Paris",
        "London",
        "Tokyo",
        "Hawaii",
        "Miami Beach"
    ]

    // MARK: - Direct Trigger Tests

    func testDuplicates() {
        let result = QueryParser.parse("duplicates", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findDuplicates)
        XCTAssertEqual(result.extractedComponents.triggerType, .duplicates)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testDuplicatesVariant() {
        let result = QueryParser.parse("find duplicate photos", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findDuplicates)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testScreenshots() {
        let result = QueryParser.parse("screenshots", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findScreenshots)
        XCTAssertEqual(result.extractedComponents.triggerType, .screenshots)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testScreenshotsVariant() {
        let result = QueryParser.parse("show me my screenshots", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findScreenshots)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testLargest() {
        let result = QueryParser.parse("largest photos", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findLargest)
        XCTAssertEqual(result.extractedComponents.triggerType, .largest)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testLargestVariant() {
        let result = QueryParser.parse("biggest files", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findLargest)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    // MARK: - Date Extraction Tests

    func testYesterday() {
        let result = QueryParser.parse("photos from yesterday", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByDate)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "yesterday")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.3)
    }

    func testLastWeek() {
        let result = QueryParser.parse("show me photos from last week", knownLocations: knownLocations)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last week")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.3)
    }

    func testLastSummer() {
        let result = QueryParser.parse("beach photos from last summer", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last summer")
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("beach"))
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testThisYear() {
        let result = QueryParser.parse("photos from this year", knownLocations: knownLocations)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "this year")
    }

    func testSpecificYear() {
        let result = QueryParser.parse("photos in 2023", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByDate)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "in 2023")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.3)
    }

    func testSpecificMonth() {
        let result = QueryParser.parse("photos in december", knownLocations: knownLocations)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "in december")
    }

    func testLastMonth() {
        let result = QueryParser.parse("last month", knownLocations: knownLocations)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last month")
    }

    // MARK: - Location Extraction Tests

    func testLocationOnly() {
        let result = QueryParser.parse("photos in Paris", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByLocation)
        XCTAssertEqual(result.action.location, "Paris")
        XCTAssertEqual(result.extractedComponents.locationPhrase, "Paris")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.3)
    }

    func testLocationWithContent() {
        let result = QueryParser.parse("sunset photos in Hawaii", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertEqual(result.action.location, "Hawaii")
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("sunset"))
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testLocationCaseInsensitive() {
        let result = QueryParser.parse("photos from LONDON", knownLocations: knownLocations)
        XCTAssertEqual(result.action.location, "London")
    }

    // MARK: - Content Extraction Tests

    func testSimpleContent() {
        let result = QueryParser.parse("dog photos", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("dog"))
        XCTAssertEqual(result.action.contentQuery, "dog")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.4)
    }

    func testMultiWordContent() {
        let result = QueryParser.parse("golden retriever at the beach", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("golden"))
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("retriever"))
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("beach"))
        XCTAssertGreaterThanOrEqual(result.confidence, 0.4)
    }

    func testStopWordsRemoved() {
        let result = QueryParser.parse("show me the cat", knownLocations: knownLocations)
        // "show", "me", "the" should be removed
        XCTAssertEqual(result.extractedComponents.contentTokens, ["cat"])
    }

    // MARK: - Compound Query Tests

    func testContentPlusDate() {
        let result = QueryParser.parse("beach photos from last summer", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("beach"))
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last summer")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testContentPlusLocation() {
        let result = QueryParser.parse("sunset in Tokyo", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("sunset"))
        XCTAssertEqual(result.action.location, "Tokyo")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testContentPlusDatePlusLocation() {
        let result = QueryParser.parse("beach photos in Hawaii last summer", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("beach"))
        XCTAssertEqual(result.action.location, "Hawaii")
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
    }

    func testDatePlusLocation() {
        let result = QueryParser.parse("photos in Paris last year", knownLocations: knownLocations)
        // Should prefer location as primary since content is empty
        XCTAssertEqual(result.action.location, "Paris")
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.6)
    }

    // MARK: - Edge Cases & Confidence Tests

    func testEmptyQuery() {
        let result = QueryParser.parse("", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertLessThanOrEqual(result.confidence, 0.2)
    }

    func testVagueQuery() {
        let result = QueryParser.parse("good ones", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertLessThanOrEqual(result.confidence, 0.5)
        // "good" should be kept as content token
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("good"))
    }

    func testAmbiguousQuery() {
        let result = QueryParser.parse("the best", knownLocations: knownLocations)
        XCTAssertLessThanOrEqual(result.confidence, 0.5)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("best"))
    }

    func testStructuredQueryHighConfidence() {
        let result = QueryParser.parse("coffee shop in San Francisco last week", knownLocations: knownLocations)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.9)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("coffee"))
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("shop"))
        XCTAssertEqual(result.action.location, "San Francisco")
        XCTAssertNotNil(result.action.dateRange)
    }

    func testDateOnlyQuery() {
        let result = QueryParser.parse("last week", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByDate)
        XCTAssertNotNil(result.action.dateRange)
        // Content tokens should be empty
        XCTAssertTrue(result.extractedComponents.contentTokens.isEmpty)
    }

    func testLocationOnlyQuery() {
        let result = QueryParser.parse("New York", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByLocation)
        XCTAssertEqual(result.action.location, "New York")
        XCTAssertTrue(result.extractedComponents.contentTokens.isEmpty)
    }

    // MARK: - Real-World Query Tests

    func testCoffeeQuery() {
        let result = QueryParser.parse("coffee photos", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("coffee"))
        XCTAssertGreaterThanOrEqual(result.confidence, 0.4)
    }

    func testDogBeachQuery() {
        let result = QueryParser.parse("my dog at the beach", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("dog"))
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("beach"))
        // "my", "at", "the" should be filtered
        XCTAssertFalse(result.extractedComponents.contentTokens.contains("my"))
        XCTAssertFalse(result.extractedComponents.contentTokens.contains("at"))
        XCTAssertFalse(result.extractedComponents.contentTokens.contains("the"))
    }

    func testSunsetQuery() {
        let result = QueryParser.parse("sunset photos from last summer", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("sunset"))
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }

    func testFoodQuery() {
        let result = QueryParser.parse("food pictures from yesterday", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("food"))
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "yesterday")
    }

    func testFlowerQuery() {
        let result = QueryParser.parse("flower photos in the garden", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("flower"))
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("garden"))
    }

    // MARK: - Multi-Word Location Tests

    func testMultiWordLocation() {
        let result = QueryParser.parse("photos in San Francisco", knownLocations: knownLocations)
        XCTAssertEqual(result.action.location, "San Francisco")
        XCTAssertEqual(result.extractedComponents.locationPhrase, "San Francisco")
    }

    func testMultiWordLocationWithContent() {
        let result = QueryParser.parse("sunset at Miami Beach", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertEqual(result.action.location, "Miami Beach")
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("sunset"))
    }

    // MARK: - Seasonal Query Tests

    func testWinterQuery() {
        let result = QueryParser.parse("snow photos from last winter", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("snow"))
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last winter")
    }

    func testFallQuery() {
        let result = QueryParser.parse("photos from last fall", knownLocations: knownLocations)
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last fall")
    }

    func testSpringQuery() {
        let result = QueryParser.parse("flowers from last spring", knownLocations: knownLocations)
        XCTAssertEqual(result.action.type, .findByContent)
        XCTAssertTrue(result.extractedComponents.contentTokens.contains("flowers"))
        XCTAssertNotNil(result.action.dateRange)
        XCTAssertEqual(result.extractedComponents.datePhrase, "last spring")
    }

    // MARK: - Confidence Score Validation

    func testHighConfidenceStructured() {
        let queries = [
            "beach photos in Hawaii last summer",
            "coffee shop in San Francisco yesterday",
            "duplicates"
        ]

        for query in queries {
            let result = QueryParser.parse(query, knownLocations: knownLocations)
            XCTAssertGreaterThanOrEqual(result.confidence, 0.7,
                                        "Query '\(query)' should have high confidence")
        }
    }

    func testLowConfidenceAmbiguous() {
        let queries = [
            "good ones",
            "the best",
            "nice pictures"
        ]

        for query in queries {
            let result = QueryParser.parse(query, knownLocations: knownLocations)
            XCTAssertLessThanOrEqual(result.confidence, 0.5,
                                     "Query '\(query)' should have low confidence")
        }
    }

    func testMediumConfidencePartial() {
        let queries = [
            "dog photos",
            "sunset",
            "in Paris"
        ]

        for query in queries {
            let result = QueryParser.parse(query, knownLocations: knownLocations)
            XCTAssertGreaterThan(result.confidence, 0.3,
                                 "Query '\(query)' should have at least medium confidence")
        }
    }
}
