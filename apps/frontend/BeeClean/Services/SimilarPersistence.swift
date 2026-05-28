import Foundation
import SwiftData
import Photos

// MARK: - SwiftData Models

/// Cached analysis result for a single photo asset.
@Model
final class CachedPhoto {
    @Attribute(.unique) var assetId: String
    var dHash64: UInt64
    var sharpnessScore: Double
    var creationDate: Date?
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSize: Int64

    /// Timestamp of when this row was written — used for staleness checks.
    var analyzedAt: Date

    /// Source-app provenance raw value (see `PhotoSource`). Optional with
    /// default nil so SwiftData's additive-field migration is automatic
    /// for existing rows. `nil` means "detection hasn't classified this
    /// asset yet" — the EXIF enrichment pass will backfill on next run.
    var sourceAppRaw: String?

    init(
        assetId: String,
        dHash64: UInt64,
        sharpnessScore: Double,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64,
        analyzedAt: Date = Date(),
        sourceAppRaw: String? = nil
    ) {
        self.assetId = assetId
        self.dHash64 = dHash64
        self.sharpnessScore = sharpnessScore
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.analyzedAt = analyzedAt
        self.sourceAppRaw = sourceAppRaw
    }

    func toAnalyzedPhoto() -> AnalyzedPhoto {
        AnalyzedPhoto(
            id: assetId,
            assetIdentifier: assetId,
            dHash64: dHash64,
            sharpnessScore: sharpnessScore,
            creationDate: creationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            fileSize: fileSize,
            sourceApp: sourceAppRaw.flatMap { PhotoSource(rawValue: $0) }
        )
    }
}

/// Cached similar-photo group with selection state.
@Model
final class CachedGroup {
    @Attribute(.unique) var groupId: UUID
    var bestId: String
    var totalBytes: Int64
    var createdAt: Date
    var confidence: Double

    /// Stored as JSON array — lightweight, avoids a relationship table.
    var itemsJSON: Data

    /// When this group was computed.
    var clusteredAt: Date

    // Decode-once cache. SwiftUI body evaluation hits `.items` per render —
    // without this, every render JSON-decoded the entire item blob (~5–10ms
    // per group access × N renders per swipe).
    @Transient private var _decodedItems: [CachedGroupItem]? = nil

    init(
        groupId: UUID,
        bestId: String,
        totalBytes: Int64,
        createdAt: Date,
        confidence: Double,
        items: [CachedGroupItem],
        clusteredAt: Date = Date()
    ) {
        self.groupId = groupId
        self.bestId = bestId
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.confidence = confidence
        self.itemsJSON = (try? JSONEncoder().encode(items)) ?? Data()
        self.clusteredAt = clusteredAt
        self._decodedItems = items
    }

    var items: [CachedGroupItem] {
        get {
            if let cached = _decodedItems { return cached }
            let decoded = (try? JSONDecoder().decode([CachedGroupItem].self, from: itemsJSON)) ?? []
            _decodedItems = decoded
            return decoded
        }
        set {
            _decodedItems = newValue
            itemsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

/// Lightweight Codable item stored inside CachedGroup.itemsJSON.
struct CachedGroupItem: Codable {
    let assetId: String
    let isBest: Bool
    var isSelectedForDelete: Bool
    let score: Double
    let hash: UInt64
    let fileSize: Int64
    /// Source-app raw value — Optional + `decodeIfPresent` so groups
    /// persisted before source-detection rolled out decode cleanly.
    let sourceAppRaw: String?

    init(
        assetId: String,
        isBest: Bool,
        isSelectedForDelete: Bool,
        score: Double,
        hash: UInt64,
        fileSize: Int64 = 0,
        sourceAppRaw: String? = nil
    ) {
        self.assetId = assetId
        self.isBest = isBest
        self.isSelectedForDelete = isSelectedForDelete
        self.score = score
        self.hash = hash
        self.fileSize = fileSize
        self.sourceAppRaw = sourceAppRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetId = try container.decode(String.self, forKey: .assetId)
        isBest = try container.decode(Bool.self, forKey: .isBest)
        isSelectedForDelete = try container.decode(Bool.self, forKey: .isSelectedForDelete)
        score = try container.decode(Double.self, forKey: .score)
        hash = try container.decode(UInt64.self, forKey: .hash)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        sourceAppRaw = try container.decodeIfPresent(String.self, forKey: .sourceAppRaw)
    }
}

/// Cached similar-screenshot group with selection state.
@Model
final class CachedScreenshotGroup {
    @Attribute(.unique) var groupId: UUID
    var bestId: String
    var totalBytes: Int64
    var createdAt: Date
    var confidence: Double
    var itemsJSON: Data
    var clusteredAt: Date

    @Transient private var _decodedItems: [CachedGroupItem]? = nil

    init(
        groupId: UUID,
        bestId: String,
        totalBytes: Int64,
        createdAt: Date,
        confidence: Double,
        items: [CachedGroupItem],
        clusteredAt: Date = Date()
    ) {
        self.groupId = groupId
        self.bestId = bestId
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.confidence = confidence
        self.itemsJSON = (try? JSONEncoder().encode(items)) ?? Data()
        self.clusteredAt = clusteredAt
        self._decodedItems = items
    }

    var items: [CachedGroupItem] {
        get {
            if let cached = _decodedItems { return cached }
            let decoded = (try? JSONDecoder().decode([CachedGroupItem].self, from: itemsJSON)) ?? []
            _decodedItems = decoded
            return decoded
        }
        set {
            _decodedItems = newValue
            itemsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

/// Cached similar-video group with selection state.
@Model
final class CachedVideoGroup {
    @Attribute(.unique) var groupId: UUID
    var bestId: String
    var totalBytes: Int64
    var createdAt: Date
    var confidence: Double
    var itemsJSON: Data
    var clusteredAt: Date

    @Transient private var _decodedItems: [CachedGroupItem]? = nil

    init(
        groupId: UUID,
        bestId: String,
        totalBytes: Int64,
        createdAt: Date,
        confidence: Double,
        items: [CachedGroupItem],
        clusteredAt: Date = Date()
    ) {
        self.groupId = groupId
        self.bestId = bestId
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.confidence = confidence
        self.itemsJSON = (try? JSONEncoder().encode(items)) ?? Data()
        self.clusteredAt = clusteredAt
        self._decodedItems = items
    }

    var items: [CachedGroupItem] {
        get {
            if let cached = _decodedItems { return cached }
            let decoded = (try? JSONDecoder().decode([CachedGroupItem].self, from: itemsJSON)) ?? []
            _decodedItems = decoded
            return decoded
        }
        set {
            _decodedItems = newValue
            itemsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}

// MARK: - Container Factory

enum SimilarPersistence {

    /// Shared model container — call once at app startup.
    static let container: ModelContainer = {
        let schema = Schema([CachedPhoto.self, CachedGroup.self, CachedScreenshotGroup.self,
                             CachedVideoGroup.self])
        let config = ModelConfiguration("SimilarPhotos", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback: wipe and retry (schema migration failure)
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Last resort: in-memory container so the app doesn't crash.
                // Data won't persist but at least every screen can render.
                print("[SimilarPersistence] Disk container failed after schema wipe, falling back to in-memory: \(error)")
                let memConfig = ModelConfiguration("SimilarPhotos", isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [memConfig])
                } catch {
                    // Truly unrecoverable — surface a clear message instead of `try!`'s
                    // generic fatal so a crash report points at the actual cause.
                    fatalError("SimilarPersistence: in-memory ModelContainer also failed: \(error)")
                }
            }
        }
    }()

}

// MARK: - JSON Coder Helpers

extension JSONEncoder {
    static let withISO8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let withISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
