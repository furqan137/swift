import Foundation
import SwiftData

extension SimilarPersistence {

    // MARK: - Staleness

    /// Returns true if cached data is older than `maxAge`.
    @MainActor
    static func isCacheStale(maxAge: TimeInterval = 24 * 60 * 60) -> Bool {
        let context = container.mainContext
        var descriptor = FetchDescriptor<CachedGroup>(
            sortBy: [SortDescriptor(\.clusteredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let newest = try? context.fetch(descriptor).first else { return true }
        return Date().timeIntervalSince(newest.clusteredAt) > maxAge
    }

    // MARK: - Cached Asset IDs

    /// Returns the set of all asset IDs currently in the photo cache.
    /// Cheap — reads only the assetId column.
    @MainActor
    static func cachedAssetIds() -> Set<String> {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedPhoto>()
        guard let cached = try? context.fetch(descriptor) else { return [] }
        return Set(cached.map(\.assetId))
    }

    // MARK: - Scan Summary (JSON)

    private static let summaryFileName = "scan_summary_v3.json"

    private static var summaryFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(summaryFileName)
    }

    static func loadScanSummary() -> ScanSummary {
        guard let data = try? Data(contentsOf: summaryFileURL),
              let summary = try? JSONDecoder.withISO8601.decode(ScanSummary.self, from: data)
        else { return .empty }
        return summary
    }

    static func saveScanSummary(_ summary: ScanSummary) {
        guard let data = try? JSONEncoder.withISO8601.encode(summary) else { return }
        try? data.write(to: summaryFileURL, options: .atomic)
    }

    // MARK: - Duplicate Detail (JSON)

    private static let duplicateDetailFileName = "scan_detail_duplicate_v2.json"

    private static var duplicateDetailFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(duplicateDetailFileName)
    }

    static func loadDuplicateScanResult() -> DuplicateScanResult {
        guard let data = try? Data(contentsOf: duplicateDetailFileURL),
              let result = try? JSONDecoder.withISO8601.decode(DuplicateScanResult.self, from: data)
        else { return .empty }
        return result
    }

    static func saveDuplicateScanResult(_ result: DuplicateScanResult) {
        guard let data = try? JSONEncoder.withISO8601.encode(result) else { return }
        try? data.write(to: duplicateDetailFileURL, options: .atomic)
    }

    // MARK: - Screenshot Detail (JSON)

    private static let screenshotDetailFileName = "scan_detail_screenshots_v2.json"

    private static var screenshotDetailFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(screenshotDetailFileName)
    }

    static func loadScreenshotScanResult() -> ScreenshotScanResult {
        guard let data = try? Data(contentsOf: screenshotDetailFileURL),
              let result = try? JSONDecoder.withISO8601.decode(ScreenshotScanResult.self, from: data)
        else { return .empty }
        return result
    }

    static func saveScreenshotScanResult(_ result: ScreenshotScanResult) {
        guard let data = try? JSONEncoder.withISO8601.encode(result) else { return }
        try? data.write(to: screenshotDetailFileURL, options: .atomic)
    }

    // MARK: - Screen Recording Detail (JSON)

    private static let screenRecordingDetailFileName = "scan_detail_screen_recordings_v1.json"

    private static var screenRecordingDetailFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(screenRecordingDetailFileName)
    }

    static func loadScreenRecordingScanResult() -> ScreenshotScanResult {
        guard let data = try? Data(contentsOf: screenRecordingDetailFileURL),
              let result = try? JSONDecoder.withISO8601.decode(ScreenshotScanResult.self, from: data)
        else { return .empty }
        return result
    }

    static func saveScreenRecordingScanResult(_ result: ScreenshotScanResult) {
        guard let data = try? JSONEncoder.withISO8601.encode(result) else { return }
        try? data.write(to: screenRecordingDetailFileURL, options: .atomic)
    }

    // MARK: - Short Video Detail (JSON)

    private static let shortVideoDetailFileName = "scan_detail_short_videos_v1.json"

    private static var shortVideoDetailFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(shortVideoDetailFileName)
    }

    static func loadShortVideoScanResult() -> ScreenshotScanResult {
        guard let data = try? Data(contentsOf: shortVideoDetailFileURL),
              let result = try? JSONDecoder.withISO8601.decode(ScreenshotScanResult.self, from: data)
        else { return .empty }
        return result
    }

    static func saveShortVideoScanResult(_ result: ScreenshotScanResult) {
        guard let data = try? JSONEncoder.withISO8601.encode(result) else { return }
        try? data.write(to: shortVideoDetailFileURL, options: .atomic)
    }

    // MARK: - Long Video Detail (JSON)

    private static let longVideoDetailFileName = "scan_detail_long_videos_v1.json"

    private static var longVideoDetailFileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(longVideoDetailFileName)
    }

    static func loadLongVideoScanResult() -> ScreenshotScanResult {
        guard let data = try? Data(contentsOf: longVideoDetailFileURL),
              let result = try? JSONDecoder.withISO8601.decode(ScreenshotScanResult.self, from: data)
        else { return .empty }
        return result
    }

    static func saveLongVideoScanResult(_ result: ScreenshotScanResult) {
        guard let data = try? JSONEncoder.withISO8601.encode(result) else { return }
        try? data.write(to: longVideoDetailFileURL, options: .atomic)
    }

}
