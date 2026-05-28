import Foundation

// MARK: - Quality Scoring
enum QualityScoring {

    // Normalization constants (based on typical photo characteristics)
    private static let sharpnessMin: Double = 0
    private static let sharpnessMax: Double = 2000    // Very sharp photos
    private static let resolutionMin: Double = 10     // log(~22000 pixels) - tiny image
    private static let resolutionMax: Double = 17     // log(~24MP) - high-res photo
    private static let fileSizeMin: Double = 10       // log(~22KB)
    private static let fileSizeMax: Double = 18       // log(~65MB)

    // MARK: Guardrail 3: Blurry Penalty
    //
    // The "best" picker chooses which photo in a Similar group to keep.
    // A blurry photo can sneak past the sharpness signal if it has a high
    // resolution or large file size — and once a blurry photo is "best,"
    // the swipe deck pre-marks every sharper sibling for delete. We bump
    // the penalty so that scenario can't happen.
    //
    //   sharpnessFloor: 100 (unchanged — Laplacian-variance scale)
    //   blurryPenalty: 0.25 → 0.40  one blurry frame now loses 0.40 raw
    //                  score, which exceeds any plausible resolution +
    //                  filesize advantage for an out-of-focus image.
    private static let sharpnessFloor: Double = 100
    private static let blurryPenalty: Double = 0.40

    /// Clamps and normalizes a value to 0...1 range
    private static func normalize(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0.5 }
        let clamped = Swift.min(Swift.max(value, min), max)
        return (clamped - min) / (max - min)
    }

    /// Calculates a quality score for a photo (0.0 to 1.0)
    /// Higher scores indicate better quality photos worth keeping
    /// Applies penalty for blurry photos (sharpness below floor)
    static func qualityScore(for photo: AnalyzedPhoto) -> Double {
        // Resolution score (log scale)
        let resolution = Double(photo.pixelWidth * photo.pixelHeight)
        let resolutionLog = log(max(1, resolution))
        let resolutionNorm = normalize(resolutionLog, min: resolutionMin, max: resolutionMax)

        // Sharpness score (already computed, just normalize)
        let sharpnessNorm = normalize(photo.sharpnessScore, min: sharpnessMin, max: sharpnessMax)

        // File size score (log scale) - larger files often have more detail
        let fileSize = Double(photo.fileSize ?? 0)
        let fileSizeLog = log(max(1, fileSize))
        let fileSizeNorm = normalize(fileSizeLog, min: fileSizeMin, max: fileSizeMax)

        // Weighted combination
        // Sharpness is most important, then resolution, then file size
        var totalScore = 0.55 * sharpnessNorm +
                         0.35 * resolutionNorm +
                         0.10 * fileSizeNorm

        // GUARDRAIL 3: Apply penalty for blurry photos
        // This prevents selecting a blurry photo as "best" when sharper alternatives exist
        if photo.sharpnessScore < sharpnessFloor {
            totalScore = max(0, totalScore - blurryPenalty)
        }

        return totalScore
    }

    /// Checks if a photo is considered blurry
    static func isBlurry(_ photo: AnalyzedPhoto) -> Bool {
        return photo.sharpnessScore < sharpnessFloor
    }

    /// Picks the best photo from a cluster based on quality score
    /// Returns the assetIdentifier of the best photo
    static func pickBest(in cluster: [AnalyzedPhoto]) -> String {
        guard !cluster.isEmpty else { return "" }
        guard cluster.count > 1 else { return cluster[0].assetIdentifier }

        var bestPhoto = cluster[0]
        var bestScore = qualityScore(for: bestPhoto)

        for photo in cluster.dropFirst() {
            let score = qualityScore(for: photo)
            if score > bestScore {
                bestScore = score
                bestPhoto = photo
            }
        }

        return bestPhoto.assetIdentifier
    }

    /// Returns scored photos sorted by quality (best first)
    static func ranked(cluster: [AnalyzedPhoto]) -> [(photo: AnalyzedPhoto, score: Double)] {
        cluster
            .map { (photo: $0, score: qualityScore(for: $0)) }
            .sorted { $0.score > $1.score }
    }
}

