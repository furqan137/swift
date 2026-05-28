import SwiftUI
import Photos
import Foundation

// MARK: - Smart Tags (Photos)
//
// Each flag maps to a PHAsset.mediaSubtypes bit (or derived metadata) and
// surfaces as a content-type badge on the card. These also feed the
// savings estimator — screenshots compress dramatically better than
// landscape HEICs, bursts share a lot of visual content, etc.
struct PhotoSmartTags: Equatable {
    var isScreenshot: Bool = false
    var isLivePhoto: Bool = false
    var isBurst: Bool = false
    var isHDR: Bool = false
    var isPortrait: Bool = false  // depth-effect photo
    var isPanorama: Bool = false
    var isSelfie: Bool = false    // front-camera, detected via EXIF if available

    /// Primary badge to feature on the card, in priority order. Screenshots
    /// and Live Photos are the highest-value content-type cues for a
    /// "Cleaner Guru-style" compressor because they dominate library churn.
    var primaryBadge: (icon: String, label: String)? {
        if isScreenshot  { return ("camera.viewfinder", "Screenshot") }
        if isLivePhoto   { return ("livephoto", "Live") }
        if isPortrait    { return ("person.crop.circle", "Portrait") }
        if isPanorama    { return ("pano", "Pano") }
        if isBurst       { return ("square.stack.3d.up.fill", "Burst") }
        if isHDR         { return ("sun.max.fill", "HDR") }
        if isSelfie      { return ("person.fill", "Selfie") }
        return nil
    }
}

// MARK: - Photo Asset
struct PhotoAsset: Identifiable {
    let id: String
    let asset: PHAsset?
    let fileSize: Int64
    let potentialSavings: Int64
    let creationDate: Date
    let resolution: CGSize?
    /// Detected source format ("HEIC", "JPEG", "PNG", "RAW", "DNG"…). nil = unknown.
    let format: String?
    /// True when the asset's primary resource is iCloud-only (no local copy).
    /// Surfaced on the card so users know tapping compress will trigger a
    /// network fetch from Photos' iCloud backing store.
    let isInCloud: Bool
    /// Content-type smart tags — drive the card badge and savings math.
    let tags: PhotoSmartTags
    /// Source-app provenance — drives the SocialSourceBadge overlay on
    /// the Compress photo tile. Detected via the same two-tier path the
    /// similar/duplicate scan uses (filename prefix for Snapchat /
    /// WhatsApp / Telegram / Messenger / TikTok; EXIF Software tag for
    /// Instagram + any of the above when filename was sanitized).
    var sourceApp: PhotoSource?

    init(
        id: String,
        asset: PHAsset?,
        fileSize: Int64,
        potentialSavings: Int64,
        creationDate: Date,
        resolution: CGSize?,
        format: String?,
        isInCloud: Bool = false,
        tags: PhotoSmartTags = PhotoSmartTags(),
        sourceApp: PhotoSource? = nil
    ) {
        self.id = id
        self.asset = asset
        self.fileSize = fileSize
        self.potentialSavings = potentialSavings
        self.creationDate = creationDate
        self.resolution = resolution
        self.format = format
        self.isInCloud = isInCloud
        self.tags = tags
        self.sourceApp = sourceApp
    }

    var formattedSavings: String {
        // Static path — same rationale as VideoAsset.formattedSavings.
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }

    var formattedDimensions: String? {
        guard let resolution = resolution, resolution.width > 0, resolution.height > 0 else { return nil }
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }

    var formattedFormat: String {
        format ?? "PHOTO"
    }

    /// Relative capture date for the card — "today", "2d ago", "Apr 2024".
    /// Gives users immediate context for what photo they're looking at
    /// without needing a full timestamp.
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

    /// One-time DateFormatter instances — `DateFormatter()` is ~1ms to
    /// allocate; doing it per-cell during scroll was tens of ms of pure
    /// allocator churn. Static lets get initialized exactly once.
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
}

// MARK: - Cache Snapshot
// Codable projection of a PhotoAsset minus the non-serializable PHAsset
// reference. Written to disk after a scan so the next app launch can
// rehydrate the grid instantly (rehydration re-looks up PHAssets in one
// batch `fetchAssets(withLocalIdentifiers:)` call, which is ~2 orders of
// magnitude cheaper than re-running the per-asset PHAssetResource fetch).
struct CachedPhotoSnapshot: Codable {
    let id: String
    let fileSize: Int64
    let potentialSavings: Int64
    let creationTimestamp: TimeInterval
    let pixelWidth: Double
    let pixelHeight: Double
    let format: String?
    let isInCloud: Bool
    let isScreenshot: Bool
    let isLivePhoto: Bool
    let isBurst: Bool
    let isHDR: Bool
    let isPortrait: Bool
    let isPanorama: Bool
    let isSelfie: Bool
    /// Persisted source-app raw value. Optional so blobs written before
    /// the field existed decode cleanly (Swift auto-decodes absent keys
    /// as nil for Optionals).
    var sourceAppRaw: String?

    init(from photo: PhotoAsset) {
        self.id = photo.id
        self.fileSize = photo.fileSize
        self.potentialSavings = photo.potentialSavings
        self.creationTimestamp = photo.creationDate.timeIntervalSince1970
        self.pixelWidth = Double(photo.resolution?.width ?? 0)
        self.pixelHeight = Double(photo.resolution?.height ?? 0)
        self.format = photo.format
        self.isInCloud = photo.isInCloud
        self.isScreenshot = photo.tags.isScreenshot
        self.isLivePhoto = photo.tags.isLivePhoto
        self.isBurst = photo.tags.isBurst
        self.isHDR = photo.tags.isHDR
        self.isPortrait = photo.tags.isPortrait
        self.isPanorama = photo.tags.isPanorama
        self.isSelfie = photo.tags.isSelfie
        self.sourceAppRaw = photo.sourceApp?.rawValue
    }

    /// Rehydrate back into a PhotoAsset given a live PHAsset reference.
    /// Callers batch-fetch the PHAssets via `fetchAssets(withLocalIdentifiers:)`
    /// and pass each one here — the snapshot supplies all the metadata
    /// that would otherwise require a full resource round-trip.
    func toPhotoAsset(asset: PHAsset?) -> PhotoAsset {
        let resolution: CGSize? = (pixelWidth > 0 && pixelHeight > 0)
            ? CGSize(width: pixelWidth, height: pixelHeight)
            : nil
        let tags = PhotoSmartTags(
            isScreenshot: isScreenshot,
            isLivePhoto: isLivePhoto,
            isBurst: isBurst,
            isHDR: isHDR,
            isPortrait: isPortrait,
            isPanorama: isPanorama,
            isSelfie: isSelfie
        )
        return PhotoAsset(
            id: id,
            asset: asset,
            fileSize: fileSize,
            potentialSavings: potentialSavings,
            creationDate: Date(timeIntervalSince1970: creationTimestamp),
            resolution: resolution,
            format: format,
            isInCloud: isInCloud,
            tags: tags,
            sourceApp: sourceAppRaw.flatMap { PhotoSource(rawValue: $0) }
        )
    }
}

// MARK: - Format Detection
extension PhotoAsset {
    /// Best-effort format inference from a PHAsset's first resource.
    static func detectFormat(from resource: PHAssetResource?) -> String? {
        guard let resource = resource else { return nil }
        let uti = resource.uniformTypeIdentifier.lowercased()
        if uti.contains("heic") || uti.contains("heif") { return "HEIC" }
        if uti.contains("jpeg") || uti.contains("jpg")  { return "JPEG" }
        if uti.contains("png")                          { return "PNG"  }
        if uti.contains("dng")                          { return "DNG"  }
        if uti.contains("raw")                          { return "RAW"  }
        if uti.contains("webp")                         { return "WEBP" }
        if uti.contains("gif")                          { return "GIF"  }

        // Fallback: filename extension
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        switch ext {
        case "heic", "heif": return "HEIC"
        case "jpg", "jpeg":  return "JPEG"
        case "png":          return "PNG"
        case "dng":          return "DNG"
        case "raw":          return "RAW"
        case "webp":         return "WEBP"
        case "gif":          return "GIF"
        default:             return ext.isEmpty ? nil : ext.uppercased()
        }
    }
}
