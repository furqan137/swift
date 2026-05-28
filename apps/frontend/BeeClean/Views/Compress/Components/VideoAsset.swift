import SwiftUI
import Photos
import Foundation

// MARK: - Smart Tags (Videos)
//
// Same pattern as PhotoSmartTags — content-type flags that feed card
// badges and savings math. 4K detection is derived from resolution rather
// than mediaSubtype since iOS doesn't report it as a subtype.
struct VideoSmartTags: Equatable {
    var isSlowMo: Bool = false          // mediaSubtypes.videoHighFrameRate
    var isTimelapse: Bool = false       // mediaSubtypes.videoTimelapse
    var isCinematic: Bool = false       // mediaSubtypes.videoCinematic (iOS 16+)
    var is4K: Bool = false              // derived from natural resolution ≥ 3840
    var isHEVC: Bool = false            // derived from resource UTI
    var isHDR: Bool = false             // reserved for future HDR10/Dolby detection

    var primaryBadge: (icon: String, label: String)? {
        if isSlowMo     { return ("slowmo", "Slo-Mo") }
        if isTimelapse  { return ("timelapse", "Time-Lapse") }
        if isCinematic  { return ("film.stack", "Cinematic") }
        if is4K         { return ("4k.tv", "4K") }
        if isHDR        { return ("sun.max.fill", "HDR") }
        return nil
    }
}

// MARK: - Video Asset
struct VideoAsset: Identifiable {
    let id: String
    let asset: PHAsset?
    let fileSize: Int64
    let potentialSavings: Int64
    let duration: TimeInterval
    let creationDate: Date
    let resolution: CGSize?
    let bitrate: Float?
    /// True when the asset's primary resource is iCloud-only (no local copy).
    /// See PhotoAsset.isInCloud for rationale.
    let isInCloud: Bool
    /// Content-type smart tags — drive the card badge and savings math.
    let tags: VideoSmartTags
    /// Source-app provenance — drives the badge on Compress flow tiles.
    var sourceApp: PhotoSource?

    init(
        id: String,
        asset: PHAsset?,
        fileSize: Int64,
        potentialSavings: Int64,
        duration: TimeInterval,
        creationDate: Date,
        resolution: CGSize?,
        bitrate: Float?,
        isInCloud: Bool = false,
        tags: VideoSmartTags = VideoSmartTags(),
        sourceApp: PhotoSource? = nil
    ) {
        self.id = id
        self.asset = asset
        self.fileSize = fileSize
        self.potentialSavings = potentialSavings
        self.duration = duration
        self.creationDate = creationDate
        self.resolution = resolution
        self.bitrate = bitrate
        self.isInCloud = isInCloud
        self.tags = tags
        self.sourceApp = sourceApp
    }
    
    var formattedDuration: String {
        let safeDuration = max(duration, 0)
        let total = Int(safeDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedSavings: String {
        // ByteCountFormatter is internally caching but allocating one per
        // call still costs ~10–20µs and our 2-col card grid reads this on
        // every cell layout pass. The static `string(fromByteCount:countStyle:)`
        // is the canonical zero-alloc path Apple ships for exactly this case.
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }
    
    var formattedBitrate: String? {
        guard let bitrate = bitrate, bitrate > 0, bitrate.isFinite else { return nil }
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else {
            return String(format: "%.0f kbps", bitrate / 1_000)
        }
    }

    /// Cached date formatters. DateFormatter is hideously expensive to
    /// construct (~1ms each) and the per-call instances were being created
    /// every time a card laid out — multiplied by hundreds of cells in
    /// the Compress grid that's tens of ms of pure allocator churn per
    /// scroll frame. Static lets are initialized exactly once.
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    /// Relative capture date — mirrors PhotoAsset.formattedCaptureDate.
    var formattedCaptureDate: String {
        let now = Date()
        let interval = now.timeIntervalSince(creationDate)
        let seconds = Int(interval)
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        if days < 365 {
            return Self.monthDayFormatter.string(from: creationDate)
        }
        return Self.monthYearFormatter.string(from: creationDate)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Cache Snapshot
// See CachedPhotoSnapshot in PhotoAsset.swift for the rationale — this is
// the video counterpart.
struct CachedVideoSnapshot: Codable {
    let id: String
    let fileSize: Int64
    let potentialSavings: Int64
    let duration: TimeInterval
    let creationTimestamp: TimeInterval
    let pixelWidth: Double
    let pixelHeight: Double
    let bitrate: Float?
    let isInCloud: Bool
    let isSlowMo: Bool
    let isTimelapse: Bool
    let isCinematic: Bool
    let is4K: Bool
    let isHEVC: Bool
    let isHDR: Bool
    /// Source-app raw value — Optional so blobs persisted before this
    /// feature decode cleanly (Swift auto-Codable for Optionals treats an
    /// absent key as nil).
    var sourceAppRaw: String?

    init(from video: VideoAsset) {
        self.id = video.id
        self.fileSize = video.fileSize
        self.potentialSavings = video.potentialSavings
        self.duration = video.duration
        self.creationTimestamp = video.creationDate.timeIntervalSince1970
        self.pixelWidth = Double(video.resolution?.width ?? 0)
        self.pixelHeight = Double(video.resolution?.height ?? 0)
        self.bitrate = video.bitrate
        self.isInCloud = video.isInCloud
        self.isSlowMo = video.tags.isSlowMo
        self.isTimelapse = video.tags.isTimelapse
        self.isCinematic = video.tags.isCinematic
        self.is4K = video.tags.is4K
        self.isHEVC = video.tags.isHEVC
        self.isHDR = video.tags.isHDR
        self.sourceAppRaw = video.sourceApp?.rawValue
    }

    func toVideoAsset(asset: PHAsset?) -> VideoAsset {
        let resolution: CGSize? = (pixelWidth > 0 && pixelHeight > 0)
            ? CGSize(width: pixelWidth, height: pixelHeight)
            : nil
        let tags = VideoSmartTags(
            isSlowMo: isSlowMo,
            isTimelapse: isTimelapse,
            isCinematic: isCinematic,
            is4K: is4K,
            isHEVC: isHEVC,
            isHDR: isHDR
        )
        return VideoAsset(
            id: id,
            asset: asset,
            fileSize: fileSize,
            potentialSavings: potentialSavings,
            duration: duration,
            creationDate: Date(timeIntervalSince1970: creationTimestamp),
            resolution: resolution,
            bitrate: bitrate,
            isInCloud: isInCloud,
            tags: tags,
            sourceApp: sourceAppRaw.flatMap { PhotoSource(rawValue: $0) }
        )
    }
}

// MARK: - Helper Functions
func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
