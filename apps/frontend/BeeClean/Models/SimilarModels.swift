import Foundation
import SwiftUI

// MARK: - Photo Source
//
// Provenance signal for every photo/video in the library: which app
// originally saved this file? Drives the per-tile badge overlay and
// the dedicated per-source cleanup cards on the Charging tab.
//
// Detection runs in two tiers (see PhotoSourceDetector for policy):
//   • Tier 1 (inline, ~1ms/asset): filename-prefix match for apps with
//     deterministic naming — Snapchat / WhatsApp / TikTok / Telegram /
//     Messenger. Fires inside PhotoAnalyzer.analyzeAsset.
//   • Tier 2 (background, ~10ms/asset, post-scan): EXIF Software tag for
//     Instagram (saves files as IMG_XXXX.jpg — filename can't help).
//
// `.camera` is the explicit "user's own capture" sentinel — badge view
// renders nothing for it (or for `nil` when Tier 2 hasn't run yet).
//
// Inlined here instead of a standalone Models/PhotoSource.swift because
// the Xcode project's build phase is hand-edited (same rationale as
// BCAppReset). When the project gains synchronized groups, extract to
// its own file.
enum PhotoSource: String, Codable, Hashable, Sendable, CaseIterable {
    case instagram
    case snapchat
    case tiktok
    case whatsapp
    case telegram
    case messenger
    case camera

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .snapchat:  return "Snapchat"
        case .tiktok:    return "TikTok"
        case .whatsapp:  return "WhatsApp"
        case .telegram:  return "Telegram"
        case .messenger: return "Messenger"
        case .camera:    return "Camera"
        }
    }

    /// 1–2 letter monogram rendered inside the badge circle.
    var monogram: String {
        switch self {
        case .instagram: return "IG"
        case .snapchat:  return "S"
        case .tiktok:    return "TT"
        case .whatsapp:  return "W"
        case .telegram:  return "Tg"
        case .messenger: return "M"
        case .camera:    return ""
        }
    }

    /// Brand-tinted background for the badge.
    var brandColor: Color {
        switch self {
        case .instagram: return Color(hex: "E1306C")   // Instagram pink
        case .snapchat:  return Color(hex: "FFFC00")   // Snapchat yellow
        case .tiktok:    return Color(hex: "010101")   // TikTok black
        case .whatsapp:  return Color(hex: "25D366")   // WhatsApp green
        case .telegram:  return Color(hex: "2AABEE")   // Telegram blue
        case .messenger: return Color(hex: "00B2FF")   // Messenger blue
        case .camera:    return .clear
        }
    }

    /// Monogram foreground — black against yellow, white everywhere else.
    var monogramColor: Color {
        switch self {
        case .snapchat: return .black
        default:        return .white
        }
    }

    /// True for any source that warrants a badge. `.camera` returns false
    /// so vanilla camera shots stay clean.
    var isExternal: Bool { self != .camera }
}

// MARK: - Scan Summary (persisted as scan_summary_v3.json)
struct ScanSummary: Codable, Equatable {
    var similarGroupsCount: Int
    var similarToCleanCount: Int
    var duplicateGroupsCount: Int
    var duplicateToCleanCount: Int
    var screenshotCount: Int
    var screenshotTotalBytes: Int64
    var screenshotGroupsCount: Int
    var screenshotToCleanCount: Int
    var videoGroupsCount: Int
    var videoToCleanCount: Int
    var screenRecordingCount: Int
    var screenRecordingTotalBytes: Int64
    var shortVideoCount: Int
    var shortVideoTotalBytes: Int64
    var longVideoCount: Int
    var longVideoTotalBytes: Int64
    var lastScanDate: Date?

    init(
        similarGroupsCount: Int,
        similarToCleanCount: Int,
        duplicateGroupsCount: Int,
        duplicateToCleanCount: Int,
        screenshotCount: Int,
        screenshotTotalBytes: Int64,
        screenshotGroupsCount: Int,
        screenshotToCleanCount: Int,
        videoGroupsCount: Int = 0,
        videoToCleanCount: Int = 0,
        screenRecordingCount: Int = 0,
        screenRecordingTotalBytes: Int64 = 0,
        shortVideoCount: Int = 0,
        shortVideoTotalBytes: Int64 = 0,
        longVideoCount: Int = 0,
        longVideoTotalBytes: Int64 = 0,
        lastScanDate: Date? = nil
    ) {
        self.similarGroupsCount = similarGroupsCount
        self.similarToCleanCount = similarToCleanCount
        self.duplicateGroupsCount = duplicateGroupsCount
        self.duplicateToCleanCount = duplicateToCleanCount
        self.screenshotCount = screenshotCount
        self.screenshotTotalBytes = screenshotTotalBytes
        self.screenshotGroupsCount = screenshotGroupsCount
        self.screenshotToCleanCount = screenshotToCleanCount
        self.videoGroupsCount = videoGroupsCount
        self.videoToCleanCount = videoToCleanCount
        self.screenRecordingCount = screenRecordingCount
        self.screenRecordingTotalBytes = screenRecordingTotalBytes
        self.shortVideoCount = shortVideoCount
        self.shortVideoTotalBytes = shortVideoTotalBytes
        self.longVideoCount = longVideoCount
        self.longVideoTotalBytes = longVideoTotalBytes
        self.lastScanDate = lastScanDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        similarGroupsCount = try container.decode(Int.self, forKey: .similarGroupsCount)
        similarToCleanCount = try container.decode(Int.self, forKey: .similarToCleanCount)
        duplicateGroupsCount = try container.decode(Int.self, forKey: .duplicateGroupsCount)
        duplicateToCleanCount = try container.decode(Int.self, forKey: .duplicateToCleanCount)
        screenshotCount = try container.decode(Int.self, forKey: .screenshotCount)
        screenshotTotalBytes = try container.decode(Int64.self, forKey: .screenshotTotalBytes)
        screenshotGroupsCount = try container.decode(Int.self, forKey: .screenshotGroupsCount)
        screenshotToCleanCount = try container.decode(Int.self, forKey: .screenshotToCleanCount)
        videoGroupsCount = try container.decodeIfPresent(Int.self, forKey: .videoGroupsCount) ?? 0
        videoToCleanCount = try container.decodeIfPresent(Int.self, forKey: .videoToCleanCount) ?? 0
        screenRecordingCount = try container.decodeIfPresent(Int.self, forKey: .screenRecordingCount) ?? 0
        screenRecordingTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .screenRecordingTotalBytes) ?? 0
        shortVideoCount = try container.decodeIfPresent(Int.self, forKey: .shortVideoCount) ?? 0
        shortVideoTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .shortVideoTotalBytes) ?? 0
        longVideoCount = try container.decodeIfPresent(Int.self, forKey: .longVideoCount) ?? 0
        longVideoTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .longVideoTotalBytes) ?? 0
        lastScanDate = try container.decodeIfPresent(Date.self, forKey: .lastScanDate)
    }

    static let empty = ScanSummary(
        similarGroupsCount: 0,
        similarToCleanCount: 0,
        duplicateGroupsCount: 0,
        duplicateToCleanCount: 0,
        screenshotCount: 0,
        screenshotTotalBytes: 0,
        screenshotGroupsCount: 0,
        screenshotToCleanCount: 0,
        videoGroupsCount: 0,
        videoToCleanCount: 0,
        screenRecordingCount: 0,
        screenRecordingTotalBytes: 0,
        shortVideoCount: 0,
        shortVideoTotalBytes: 0,
        longVideoCount: 0,
        longVideoTotalBytes: 0,
        lastScanDate: nil
    )
}

// MARK: - Duplicate Scan Detail (persisted as scan_detail_duplicate_v2.json)
struct PhotoDuplicateGroup: Codable, Equatable, Identifiable {
    let id: UUID
    let keepAssetId: String
    let deleteAssetIds: [String]
    let confidence: Double
    let totalBytes: Int64

    var count: Int { 1 + deleteAssetIds.count }
}

struct DuplicateScanResult: Codable, Equatable {
    var groups: [PhotoDuplicateGroup]
    var scannedAt: Date

    static let empty = DuplicateScanResult(groups: [], scannedAt: Date.distantPast)
}

// MARK: - Screenshot Detection (persisted as scan_detail_screenshots_v2.json)
struct ScreenshotAsset: Codable, Equatable, Identifiable, Hashable {
    let assetId: String
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64
    /// Provenance — drives the per-tile badge overlay. Optional so JSON
    /// blobs persisted before the source-detection feature decode cleanly
    /// (Swift's automatic Codable decodes an absent key as nil for Optionals).
    var sourceApp: PhotoSource? = nil

    var id: String { assetId }

    init(
        assetId: String,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64,
        sourceApp: PhotoSource? = nil
    ) {
        self.assetId = assetId
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.sourceApp = sourceApp
    }
}

struct ScreenshotScanResult: Codable, Equatable {
    var screenshots: [ScreenshotAsset]
    var totalBytes: Int64
    var scannedAt: Date

    static let empty = ScreenshotScanResult(screenshots: [], totalBytes: 0, scannedAt: Date.distantPast)

    var count: Int { screenshots.count }
}

// MARK: - Similar Group Item
struct SimilarGroupItem: Identifiable, Hashable, Sendable {
    let assetId: String
    let isBest: Bool
    var isSelectedForDelete: Bool
    let score: Double
    let hash: UInt64
    let fileSize: Int64
    /// Provenance — drives the per-thumbnail badge inside group/duplicate
    /// cards. Defaults to nil so existing construction sites keep working.
    var sourceApp: PhotoSource?

    var id: String { assetId }

    init(
        assetId: String,
        isBest: Bool = false,
        isSelectedForDelete: Bool = false,
        score: Double = 0,
        hash: UInt64 = 0,
        fileSize: Int64 = 0,
        sourceApp: PhotoSource? = nil
    ) {
        self.assetId = assetId
        self.isBest = isBest
        self.isSelectedForDelete = isSelectedForDelete
        self.score = score
        self.hash = hash
        self.fileSize = fileSize
        self.sourceApp = sourceApp
    }
}

// MARK: - Per-Group View Model
struct SimilarGroupVM: Identifiable {
    let id: UUID
    let count: Int
    let totalBytes: Int64
    let confidence: Double
    let createdAt: Date
    let bestId: String
    var items: [SimilarGroupItem]

    var bytesSaved: Int64 {
        items
            .filter { $0.isSelectedForDelete }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

    var selectedCount: Int {
        items.filter(\.isSelectedForDelete).count
    }
}

// MARK: - Identifiable conformance for navigation
extension SimilarGroupVM: Hashable {
    static func == (lhs: SimilarGroupVM, rhs: SimilarGroupVM) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Delete Progress
struct DeleteProgress {
    var totalToDelete: Int = 0
    var deleted: Int = 0
    var failed: Int = 0
    var currentChunk: Int = 0
    var totalChunks: Int = 0

    var fraction: Double {
        guard totalToDelete > 0 else { return 0 }
        return Double(deleted + failed) / Double(totalToDelete)
    }

    var isComplete: Bool {
        (deleted + failed) >= totalToDelete && totalToDelete > 0
    }
}

// MARK: - Group Source
enum GroupSource {
    case photos
    case duplicates
    case screenshots
    case videos

    var title: String {
        switch self {
        case .photos: return "Similar Group"
        case .duplicates: return "Duplicate Group"
        case .screenshots: return "Screenshot Group"
        case .videos: return "Video Group"
        }
    }

    var themeColor: Color {
        // Match the home-card accent palette (ChargingView). Photos and
        // videos live on separate palettes so the detail screens carry
        // the same color identity as their entry tile.
        switch self {
        case .photos: return .categoryViolet      // Similar Photos
        case .duplicates: return .categorySky     // Duplicates
        case .screenshots: return .categoryTeal   // Similar Screenshots
        case .videos: return .categoryCrimson     // Similar Videos — video palette
        }
    }

    var itemLabel: String {
        switch self {
        case .photos: return "photos"
        case .duplicates: return "photos"
        case .screenshots: return "screenshots"
        case .videos: return "videos"
        }
    }
}

// MARK: - Similar Group
struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let assetIds: [String]
    let bestId: String
    let totalBytes: Int64
    let createdAt: Date
    let confidence: Double

    init(
        id: UUID = UUID(),
        assetIds: [String],
        bestId: String,
        totalBytes: Int64 = 0,
        createdAt: Date = Date(),
        confidence: Double = 1.0
    ) {
        self.id = id
        self.assetIds = assetIds
        self.bestId = bestId
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.confidence = confidence
    }

    var count: Int { assetIds.count }

    var deletableIds: [String] {
        assetIds.filter { $0 != bestId }
    }
}
