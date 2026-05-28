import Foundation
import Photos

// MARK: - Parsed Query

struct ParsedQuery {
    let action: AIAction
    let originalQuery: String
    let confidence: Float  // 0-1, used to decide if we need LLM fallback
    let extractedComponents: QueryComponents
}

struct QueryComponents {
    let datePhrase: String?
    let locationPhrase: String?
    let contentTokens: [String]
    let triggerType: TriggerType?

    enum TriggerType: String {
        case duplicates
        case screenshots
        case largest
    }
}

// MARK: - Query Parser

/// On-device natural language query parser for photo search.
///
/// Extracts structured search parameters from user queries without
/// requiring an LLM. Returns confidence score to decide if LLM
/// fallback is needed for ambiguous queries.
class QueryParser {

    // MARK: - Known Location Matching

    /// Match query against known locations from photo library.
    /// Returns the best match and the matched phrase.
    private static func extractLocation(
        from query: String,
        knownLocations: [String]
    ) -> (location: String, phrase: String)? {
        let lowercased = query.lowercased()

        // Try exact matches first (e.g., "San Francisco", "Paris")
        for location in knownLocations {
            let locLower = location.lowercased()
            if lowercased.contains(locLower) {
                return (location, location)
            }
        }

        // Try partial matches (e.g., "photos in SF" matches "San Francisco")
        let commonAbbreviations: [String: String] = [
            "sf": "San Francisco",
            "la": "Los Angeles",
            "nyc": "New York",
            "ny": "New York"
        ]

        for (abbr, fullName) in commonAbbreviations {
            if lowercased.contains(" \(abbr) ") || lowercased.contains(" \(abbr)") {
                if knownLocations.contains(where: { $0.lowercased().contains(fullName.lowercased()) }) {
                    return (fullName, abbr)
                }
            }
        }

        return nil
    }

    // MARK: - Date Extraction

    /// Extract date range from query using NSDataDetector + relative patterns.
    private static func extractDateRange(from query: String) -> (dateRange: AIDateRange, phrase: String)? {
        let lowercased = query.lowercased()

        // Relative date patterns
        let patterns: [(pattern: String, range: AIDateRange, phrase: String)] = [
            // Yesterday/today/tomorrow
            ("yesterday", yesterdayRange(), "yesterday"),
            ("today", todayRange(), "today"),
            ("this week", thisWeekRange(), "this week"),
            ("last week", lastWeekRange(), "last week"),

            // Seasonal
            ("last summer", lastSummerRange(), "last summer"),
            ("this summer", thisSummerRange(), "this summer"),
            ("last winter", lastWinterRange(), "last winter"),
            ("last fall", lastFallRange(), "last fall"),
            ("last spring", lastSpringRange(), "last spring"),

            // Month-based
            ("last month", lastMonthRange(), "last month"),
            ("this month", thisMonthRange(), "this month"),
            ("last year", lastYearRange(), "last year"),
            ("this year", thisYearRange(), "this year"),

            // Common phrases
            ("in 2024", year2024Range(), "in 2024"),
            ("in 2023", year2023Range(), "in 2023"),
            ("in 2022", year2022Range(), "in 2022"),
            ("in january", januaryThisYearRange(), "in january"),
            ("in february", februaryThisYearRange(), "in february"),
            ("in march", marchThisYearRange(), "in march"),
            ("in april", aprilThisYearRange(), "in april"),
            ("in may", mayThisYearRange(), "in may"),
            ("in june", juneThisYearRange(), "in june"),
            ("in july", julyThisYearRange(), "in july"),
            ("in august", augustThisYearRange(), "in august"),
            ("in september", septemberThisYearRange(), "in september"),
            ("in october", octoberThisYearRange(), "in october"),
            ("in november", novemberThisYearRange(), "in november"),
            ("in december", decemberThisYearRange(), "in december")
        ]

        for (pattern, range, phrase) in patterns {
            if lowercased.contains(pattern) {
                return (range, phrase)
            }
        }

        // Try NSDataDetector for explicit dates ("photos from June 15 2024")
        if let detected = detectExplicitDate(in: query) {
            return detected
        }

        return nil
    }

    private static func detectExplicitDate(in query: String) -> (AIDateRange, String)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let matches = detector.matches(in: query, range: NSRange(query.startIndex..., in: query))
        guard let match = matches.first,
              let range = Range(match.range, in: query),
              let date = match.date else {
            return nil
        }

        let phrase = String(query[range])
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return (
            AIDateRange(
                start: ISO8601DateFormatter().string(from: startOfDay),
                end: ISO8601DateFormatter().string(from: endOfDay)
            ),
            phrase
        )
    }

    // MARK: - Direct Triggers

    private static func detectTrigger(from query: String) -> QueryComponents.TriggerType? {
        let lowercased = query.lowercased()

        if lowercased.contains("duplicate") || lowercased.contains("duplicates") {
            return .duplicates
        }

        if lowercased.contains("screenshot") || lowercased.contains("screenshots") {
            return .screenshots
        }

        if lowercased.contains("largest") || lowercased.contains("biggest") ||
           (lowercased.contains("large") && lowercased.contains("file")) {
            return .largest
        }

        return nil
    }

    // MARK: - Content Extraction

    /// Extract content query by removing date/location/trigger phrases.
    private static func extractContentTokens(
        from query: String,
        removingPhrases phrases: [String]
    ) -> [String] {
        var cleaned = query.lowercased()

        // Remove extracted phrases
        for phrase in phrases {
            cleaned = cleaned.replacingOccurrences(of: phrase.lowercased(), with: " ")
        }

        // Remove common stop words and search action words
        let stopWords: Set<String> = [
            "show", "me", "find", "get", "photos", "pictures", "images",
            "from", "in", "at", "on", "the", "a", "an", "of", "my",
            "with", "taken", "i", "took", "some", "all", "any"
        ]

        let tokens = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }

        return tokens
    }

    // MARK: - Confidence Scoring

    /// Calculate confidence score based on extracted structure.
    ///
    /// High confidence (0.7-1.0): Clear date/location/trigger + content words
    /// Medium confidence (0.4-0.7): Some structure but vague
    /// Low confidence (0.0-0.4): Ambiguous, needs LLM clarification
    private static func calculateConfidence(
        components: QueryComponents,
        hasContentTokens: Bool
    ) -> Float {
        var score: Float = 0.0

        // Direct triggers = very high confidence
        if components.triggerType != nil {
            return 0.95
        }

        // Date extraction adds confidence
        if components.datePhrase != nil {
            score += 0.3
        }

        // Location extraction adds confidence
        if components.locationPhrase != nil {
            score += 0.3
        }

        // Content tokens add confidence
        if hasContentTokens {
            score += 0.4
        } else if components.datePhrase == nil && components.locationPhrase == nil {
            // No structure at all = very low confidence
            return 0.2
        }

        return min(score, 1.0)
    }

    // MARK: - Main Parser

    static func parse(_ query: String, knownLocations: [String]) -> ParsedQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedQuery(
                action: AIAction(
                    type: .findByContent,
                    description: "Search all photos",
                    contentQuery: ""
                ),
                originalQuery: query,
                confidence: 0.1,
                extractedComponents: QueryComponents(
                    datePhrase: nil,
                    locationPhrase: nil,
                    contentTokens: [],
                    triggerType: nil
                )
            )
        }

        // 1. Check for direct triggers first
        let trigger = detectTrigger(from: trimmed)

        // 2. Extract date range
        let dateExtraction = extractDateRange(from: trimmed)

        // 3. Extract location
        let locationExtraction = extractLocation(from: trimmed, knownLocations: knownLocations)

        // 4. Collect removed phrases
        var removedPhrases: [String] = []
        if let datePhrase = dateExtraction?.phrase {
            removedPhrases.append(datePhrase)
        }
        if let locPhrase = locationExtraction?.phrase {
            removedPhrases.append(locPhrase)
        }

        // 5. Extract content tokens
        let contentTokens = extractContentTokens(from: trimmed, removingPhrases: removedPhrases)

        // 6. Build components
        let components = QueryComponents(
            datePhrase: dateExtraction?.phrase,
            locationPhrase: locationExtraction?.phrase,
            contentTokens: contentTokens,
            triggerType: trigger
        )

        // 7. Calculate confidence
        let confidence = calculateConfidence(
            components: components,
            hasContentTokens: !contentTokens.isEmpty
        )

        // 8. Build action
        let action = buildAction(
            from: components,
            dateRange: dateExtraction?.dateRange,
            location: locationExtraction?.location,
            query: trimmed
        )

        return ParsedQuery(
            action: action,
            originalQuery: query,
            confidence: confidence,
            extractedComponents: components
        )
    }

    private static func buildAction(
        from components: QueryComponents,
        dateRange: AIDateRange?,
        location: String?,
        query: String
    ) -> AIAction {
        // Direct triggers
        if let trigger = components.triggerType {
            switch trigger {
            case .duplicates:
                return AIAction(
                    type: .findDuplicates,
                    description: "Find duplicate photos"
                )
            case .screenshots:
                return AIAction(
                    type: .findScreenshots,
                    description: "Find screenshots"
                )
            case .largest:
                return AIAction(
                    type: .findLargest,
                    description: "Find largest files"
                )
            }
        }

        // Determine primary action type
        let hasContent = !components.contentTokens.isEmpty
        let hasDate = dateRange != nil
        let hasLocation = location != nil

        if hasContent || (!hasDate && !hasLocation) {
            // Default to content search.
            // `hasDate` only reflects whether a dateRange resolved — a
            // few range helpers (yesterdayRange / lastWeekRange) produce
            // a dateRange WITHOUT also writing back a `datePhrase`, so
            // the previous `datePhrase!` force-unwrap would crash on
            // those queries. Fall back to a generic noun.
            let contentQuery = components.contentTokens.joined(separator: " ")
            let datePhrase = components.datePhrase ?? "that period"
            let locationPhrase = location ?? ""
            return AIAction(
                type: .findByContent,
                description: "Search photos" + (hasDate ? " from \(datePhrase)" : "") + (hasLocation ? " in \(locationPhrase)" : ""),
                dateRange: dateRange,
                location: location,
                contentQuery: contentQuery.isEmpty ? query : contentQuery
            )
        } else if hasLocation && !hasContent {
            // Pure location search
            return AIAction(
                type: .findByLocation,
                description: "Photos in \(location ?? "this area")",
                dateRange: dateRange,
                location: location
            )
        } else {
            // Pure date search — same datePhrase-vs-dateRange asymmetry
            // as the branch above; nil-coalesce so a programmatic
            // dateRange without a parsed phrase can't crash.
            return AIAction(
                type: .findByDate,
                description: "Photos from \(components.datePhrase ?? "that period")",
                dateRange: dateRange
            )
        }
    }

    // MARK: - Date Range Helpers

    private static func yesterdayRange() -> AIDateRange {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let start = calendar.startOfDay(for: yesterday)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func todayRange() -> AIDateRange {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func thisWeekRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: now)!
        let startOfWeek = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: startOfWeek),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastWeekRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let thisWeekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: now)!
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!
        let start = calendar.startOfDay(for: lastWeekStart)
        let end = calendar.startOfDay(for: thisWeekStart)
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastSummerRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        // Last summer = previous year's Jun-Aug if we're before June, else this year's
        let summerYear = currentMonth < 6 ? currentYear - 1 : currentYear

        let start = calendar.date(from: DateComponents(year: summerYear, month: 6, day: 1))!
        let end = calendar.date(from: DateComponents(year: summerYear, month: 9, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func thisSummerRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: currentYear, month: 6, day: 1))!
        let end = calendar.date(from: DateComponents(year: currentYear, month: 9, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastWinterRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        // Winter spans Dec-Feb, so "last winter" = Dec (year-1) to Feb (year)
        let start = calendar.date(from: DateComponents(year: currentYear - 1, month: 12, day: 1))!
        let end = calendar.date(from: DateComponents(year: currentYear, month: 3, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastFallRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let fallYear = currentMonth < 9 ? currentYear - 1 : currentYear
        let start = calendar.date(from: DateComponents(year: fallYear, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: fallYear, month: 12, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastSpringRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let springYear = currentMonth < 3 ? currentYear - 1 : currentYear
        let start = calendar.date(from: DateComponents(year: springYear, month: 3, day: 1))!
        let end = calendar.date(from: DateComponents(year: springYear, month: 6, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastMonthRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let components = calendar.dateComponents([.year, .month], from: lastMonth)
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func thisMonthRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func lastYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: currentYear - 1, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func thisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: currentYear + 1, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func year2024Range() -> AIDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func year2023Range() -> AIDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func year2022Range() -> AIDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2022, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func januaryThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 2, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func februaryThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 2, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 3, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func marchThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 3, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 4, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func aprilThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 4, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 5, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func mayThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 5, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func juneThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 7, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func julyThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 7, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 8, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func augustThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func septemberThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 10, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func octoberThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 10, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 11, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func novemberThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 11, day: 1))!
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }

    private static func decemberThisYearRange() -> AIDateRange {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 12, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return AIDateRange(
            start: ISO8601DateFormatter().string(from: start),
            end: ISO8601DateFormatter().string(from: end)
        )
    }
}
