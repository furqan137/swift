import Foundation
import Photos

// MARK: - Blurry Photos
extension SimilarPhotosStore {

    // MARK: Blurred Photos
    //
    // The dual-signal sharpness score from PhotoAnalyzer (min of Laplacian
    // variance + Tenengrad) ranges roughly:
    //   < 30   : very blurry        (clearly out of focus / motion blur)
    //   30-50  : moderately blurry  (soft, low detail — still obviously bad)
    //   50-110 : slightly blurry    (borderline — soft pets/kids/handheld shots)
    //   110+   : sharp
    //
    // Threshold widened from 80 → 110 after a recall audit against
    // Cleanup-class competitors. Real-world handheld phone shots routinely
    // produce sharpness scores in the 80-110 band — soft pet photos,
    // hand-held low-light, motion at the subject. Those frames are what
    // the user means when they say "blurred photo" and the swipe-deck UX
    // makes the borderline cases trivially easy to keep with a right-swipe.
    // The phone-aspect-ratio + screenshot guards below still catch the
    // main false-positive sources (UI captures with flat regions that
    // inflate either gradient signal into the blurred band).
    //
    // False-positive guards:
    //   • Real screenshots (smart album + phone-aspect-ratio fallback) —
    //     flat UI regions inflate the blurred score
    //   • Phone-shaped portrait images that slipped past screenshot detection —
    //     belt-and-suspenders against the same UI/screenshot leak
    //   • Tiny pixel area (< 50 KP) — chat stickers / iCloud micro-thumbnails
    //   • Tiny files (< 30 KB)      — same reason

    static let blurrySharpnessThresholdVery: Double = 30.0
    static let blurrySharpnessThresholdModerate: Double = 50.0
    // Widened to 110 from 80. The previous cutoff was tuned for Laplacian-
    // only sharpness; once Tenengrad joined the score (min-combine), the
    // numeric band for "obviously soft" handheld shots shifted upward and
    // 80 was leaving recall on the table — the exact deficit the user
    // pointed at vs. Cleanup-class competitors.
    static let blurrySharpnessThresholdSlight: Double = 110.0
    static let blurryMinPixelArea: Int = 50_000
    static let blurryMinFileSize: Int64 = 30_000

    /// True if this photo should be shown in the Blurry Photos list.
    /// Intentionally does NOT exclude grouped/duplicate photos — a blurry
    /// photo the user might want to delete is blurry regardless of whether
    /// it also has a duplicate. The user can choose to delete it from
    /// either the Duplicates flow or the Blurry flow.
    func passesBlurryFilter(
        _ photo: AnalyzedPhoto,
        groupedIds: Set<String>
    ) -> Bool {
        if PhotoAnalyzer.isMetadataOnly(photo) { return false }
        if realScreenshotIds.contains(photo.assetIdentifier) { return false }
        let area = photo.pixelWidth * photo.pixelHeight
        if area < Self.blurryMinPixelArea { return false }
        if let size = photo.fileSize, size < Self.blurryMinFileSize { return false }
        // Belt-and-suspenders: even if a phone screenshot escaped the smart-
        // album + aspect-ratio fallback (e.g., scan happened before the asset
        // was indexed), block anything with phone-screen geometry from the
        // Blurry card. Real photos here are 4:3 or 16:9, well below 1.95.
        let longSide = max(photo.pixelWidth, photo.pixelHeight)
        let shortSide = min(photo.pixelWidth, photo.pixelHeight)
        if shortSide > 0, shortSide <= 1500 {
            let ratio = Double(longSide) / Double(shortSide)
            if ratio >= 1.95 && ratio <= 2.35 { return false }
        }
        return photo.sharpnessScore < Self.blurrySharpnessThresholdSlight
    }

    /// Cheap passthrough — the actual analyzedIndex walk + filter + sort
    /// happens once inside `recomputeDashboardSnapshot()` (which shares the
    /// pass with the Other Photos walk so the index is read exactly once for
    /// both cards). Freshness is governed by the recompute call sites.
    var blurryPhotos: [ScreenshotAsset] { blurryPhotosCache }

    var blurryPhotoCount: Int { blurryPhotosCache.count }

    var blurryPhotoBytes: Int64 {
        blurryPhotosCache.reduce(Int64(0)) { $0 + $1.fileSize }
    }

}

