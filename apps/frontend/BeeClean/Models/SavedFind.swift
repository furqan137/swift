import Foundation

// MARK: - Saved Find Media Type

enum SavedFindMediaType: String, Codable, Hashable {
    case photo
    case video
}

// MARK: - Saved Find Kind
//
// The intent behind the save. The Quick Cleanup swipe deck exposes
// both buttons in its action rail — they share the underlying
// SavedFindsStore but render in their own sections of SavedFindsView.
// Legacy entries (saved via the old Save pill before this enum
// existed) decode as nil and are treated as `.bookmarked` everywhere.
enum SavedFindKind: String, Codable, Hashable, CaseIterable {
    case hearted
    case bookmarked

    var displayName: String {
        switch self {
        case .hearted:    return "Hearted"
        case .bookmarked: return "Bookmarked"
        }
    }

    var sfSymbol: String {
        switch self {
        case .hearted:    return "heart.fill"
        case .bookmarked: return "bookmark.fill"
        }
    }
}

// MARK: - Saved Find Source Category

/// The Photos / Videos cleanup category the user saved the asset from.
/// One case per approved category — Guided Cleanup / Emails / Contacts /
/// Compress / Ask Bee / Secret Space deliberately have no entry here.
enum SavedFindSourceCategory: String, Codable, Hashable {
    case duplicates
    case similarPhotos
    case similarScreenshots
    case screenshots
    case blurredPhotos
    case otherPhotos
    case similarVideos
    case screenRecordings
    case shortRecordings
    case longVideos
    // Compression lanes — dedicated leaves so the Progress chart's
    // chip filter can scope "photo compression only" / "video
    // compression only" and so compression bytes don't leak into
    // Other Photos / Long Videos totals on the breakdown card.
    case photoCompression
    case videoCompression

    var displayName: String {
        switch self {
        case .duplicates:         return "Duplicates"
        case .similarPhotos:      return "Similar Photos"
        case .similarScreenshots: return "Similar Screenshots"
        case .screenshots:        return "Screenshots"
        case .blurredPhotos:      return "Blurred Photos"
        case .otherPhotos:        return "Other Photos"
        case .similarVideos:      return "Similar Videos"
        case .screenRecordings:   return "Screen Recordings"
        case .shortRecordings:    return "Short Recordings"
        case .longVideos:         return "Long Videos"
        case .photoCompression:   return "Photo Compression"
        case .videoCompression:   return "Video Compression"
        }
    }
}

// MARK: - Saved Find

struct SavedFind: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let assetLocalIdentifier: String
    let mediaType: SavedFindMediaType
    let sourceCategory: SavedFindSourceCategory
    let savedAt: Date
    /// Source app the asset originated from (Snapchat / Instagram / etc.).
    /// Optional — only populated for assets the source-detection pipeline
    /// has classified by save-time. Drives the per-tile badge in the
    /// Saved Finds grid and the per-source filter chip row. `nil` for
    /// vanilla camera shots and for entries persisted before this
    /// feature shipped (auto-Codable decodes absent keys as nil for
    /// Optional types).
    let sourceApp: PhotoSource?
    /// Heart vs bookmark intent. Nil for entries persisted before the
    /// rail shipped — `effectiveKind` collapses nil onto `.bookmarked`
    /// so the old Save-pill flow keeps surfacing in the right section.
    let kind: SavedFindKind?

    var effectiveKind: SavedFindKind { kind ?? .bookmarked }

    init(
        id: UUID = UUID(),
        assetLocalIdentifier: String,
        mediaType: SavedFindMediaType,
        sourceCategory: SavedFindSourceCategory,
        savedAt: Date = Date(),
        sourceApp: PhotoSource? = nil,
        kind: SavedFindKind? = .bookmarked
    ) {
        self.id = id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.mediaType = mediaType
        self.sourceCategory = sourceCategory
        self.savedAt = savedAt
        self.sourceApp = sourceApp
        self.kind = kind
    }
}

// MARK: - Save Context
//
// Carried by media surfaces (MediaSwipeView, ZoomablePreviewOverlay, etc.)
// to enable the Save button and tag any item saved through that surface
// with the right category + media type. Optional everywhere: nil means
// the surface is reused by a flow that is NOT allowed to save
// (Guided Cleanup, Compress, etc.) — in those cases no button renders.

struct SavedFindContext: Equatable, Hashable {
    let mediaType: SavedFindMediaType
    let sourceCategory: SavedFindSourceCategory
    /// Per-asset source-app override. For the dedicated source-filtered
    /// cards (Snapchat / Instagram / etc.) this is set at config time so
    /// every save inherits it. For the generic category surfaces
    /// (Other Photos, Duplicates, …) the swipe view enriches the context
    /// dynamically from the active card's `sourceApp` before passing to
    /// `SaveFindButton`, so saves carry app provenance regardless of
    /// where they came from.
    let sourceApp: PhotoSource?

    init(
        mediaType: SavedFindMediaType,
        sourceCategory: SavedFindSourceCategory,
        sourceApp: PhotoSource? = nil
    ) {
        self.mediaType = mediaType
        self.sourceCategory = sourceCategory
        self.sourceApp = sourceApp
    }
}
