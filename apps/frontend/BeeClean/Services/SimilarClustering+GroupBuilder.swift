import Foundation

// MARK: - Group Building
enum GroupBuilder {

    // MARK: Guardrail 2: Minimum Size/Savings Filter
    //
    // Last gate before a group surfaces in the UI. Calibration switched
    // to favour PRECISION over recall: the user explicitly asked for
    // "no bad outputs" and "categorize correctly." The cross-bucket
    // threshold above is now tight (7 bits), so anything that DOES
    // pass clustering is high-quality already; the confidence floor
    // here is the second backstop against the rare borderline group
    // (HDR pair from different sessions, identical-frame burst across
    // a daylight-saving-time boundary, etc.).
    //
    //   minConfidence:   0.20 — groups whose avg Hamming distance from
    //                    the "best" photo sits at or below ~13 bits.
    //                    Below 0.20 the cluster is incoherent and would
    //                    frustrate the swiper. Tightened back from the
    //                    earlier 0.15 floor.
    //   minBytesForPair: 50_000 — keep pairs that save ≥ 50 KB (small
    //                    screenshot duplicates, chat-app exports). Below
    //                    that the cleanup work outweighs the storage win.
    static let minGroupSize: Int = 2
    static let minConfidence: Double = 0.20
    static let minBytesForPair: Int64 = 50_000

    /// Converts clusters of AnalyzedPhoto into SimilarGroup models
    /// Applies guardrails to filter out junk groups
    /// - Parameter clusters: Array of photo clusters from HashClustering
    /// - Returns: Array of SimilarGroup with bestId, confidence, etc.
    static func buildGroups(from clusters: [[AnalyzedPhoto]]) -> [SimilarGroup] {
        clusters.compactMap { cluster in
            guard let group = buildGroup(from: cluster) else { return nil }

            // GUARDRAIL 2: Filter out junk groups
            if !passesGuardrails(group) {
                return nil
            }

            return group
        }
    }

    /// Checks if a group passes minimum quality guardrails
    /// - Returns: false if group should be hidden
    static func passesGuardrails(_ group: SimilarGroup) -> Bool {
        // Rule 1: Confidence must be above threshold
        if group.confidence < minConfidence {
            return false
        }

        // Rule 2: Pairs (2 photos) must have meaningful savings
        if group.count == 2 && group.totalBytes < minBytesForPair {
            return false
        }

        return true
    }

    /// Filters an array of groups, removing those that don't pass guardrails
    static func filterGroups(_ groups: [SimilarGroup]) -> [SimilarGroup] {
        groups.filter { passesGuardrails($0) }
    }

    /// Builds a single SimilarGroup from a cluster
    private static func buildGroup(from cluster: [AnalyzedPhoto]) -> SimilarGroup? {
        guard cluster.count >= 2 else { return nil }

        // Pick the best photo
        let bestId = QualityScoring.pickBest(in: cluster)

        // Get all asset IDs
        let assetIds = cluster.map { $0.assetIdentifier }

        // Sum total bytes
        let totalBytes = cluster.reduce(Int64(0)) { sum, photo in
            sum + (photo.fileSize ?? 0)
        }

        // Find earliest creation date
        let createdAt = cluster
            .compactMap { $0.creationDate }
            .min() ?? Date()

        // Calculate confidence based on average hamming distance
        let confidence = calculateConfidence(cluster: cluster, bestId: bestId)

        return SimilarGroup(
            id: UUID(),
            assetIds: assetIds,
            bestId: bestId,
            totalBytes: totalBytes,
            createdAt: createdAt,
            confidence: confidence
        )
    }

    /// Creates SimilarGroupItem array from a SimilarGroup
    /// - Parameters:
    ///   - group: The SimilarGroup to convert
    ///   - analyzedIndex: Dictionary mapping assetIdentifier to AnalyzedPhoto
    /// - Returns: Array of SimilarGroupItem sorted with best first, then by score descending
    static func items(
        for group: SimilarGroup,
        analyzedIndex: [String: AnalyzedPhoto]
    ) -> [SimilarGroupItem] {
        var result: [SimilarGroupItem] = []

        for assetId in group.assetIds {
            guard let photo = analyzedIndex[assetId] else { continue }

            let isBest = assetId == group.bestId
            let score = QualityScoring.qualityScore(for: photo)

            let item = SimilarGroupItem(
                assetId: assetId,
                isBest: isBest,
                // Browse-first: user explicitly chooses what to delete.
                // The previous `!isBest` default pre-checked every
                // non-best photo on entry, surfaced the delete bar
                // immediately, and made the screen feel like the app
                // had already picked for the user. The
                // `selectAllNonBestDuplicates()` / `...Screenshots()` /
                // `...Videos()` paths in SimilarPhotosStore+Selection
                // still let the user grab the suggested set in one
                // tap via the top-bar Select-All pill — they just
                // have to opt in.
                isSelectedForDelete: false,
                score: score,
                hash: photo.dHash64,
                fileSize: photo.fileSize ?? 0
            )

            result.append(item)
        }

        // Sort: best first, then by score descending
        result.sort { item1, item2 in
            if item1.isBest != item2.isBest {
                return item1.isBest  // Best comes first
            }
            return item1.score > item2.score  // Higher score first
        }

        return result
    }

    /// Calculates confidence score based on hash similarity
    /// Higher confidence = photos are more similar
    private static func calculateConfidence(cluster: [AnalyzedPhoto], bestId: String) -> Double {
        guard let bestPhoto = cluster.first(where: { $0.assetIdentifier == bestId }) else {
            return 1.0
        }

        let others = cluster.filter { $0.assetIdentifier != bestId }
        guard !others.isEmpty else { return 1.0 }

        // Calculate average hamming distance from best to others
        let totalDistance = others.reduce(0) { sum, photo in
            sum + hammingDistance(bestPhoto.dHash64, photo.dHash64)
        }
        let avgDistance = Double(totalDistance) / Double(others.count)

        // Convert distance to confidence (0-16 distance maps to 1-0 confidence)
        // Distance 0 = confidence 1.0, Distance 16+ = confidence 0.0
        let confidence = max(0, min(1, 1.0 - (avgDistance / 16.0)))

        return confidence
    }
}

// MARK: - Bucket Statistics (for debugging/logging)
extension TimeBucketing {

    struct BucketStats {
        let totalBuckets: Int
        let totalPhotos: Int
        let averageBucketSize: Double
        let maxBucketSize: Int
        let minBucketSize: Int
        let singletonBuckets: Int  // Buckets with only 1 photo
    }

    static func stats(for buckets: [[AnalyzedPhoto]]) -> BucketStats {
        guard !buckets.isEmpty else {
            return BucketStats(
                totalBuckets: 0,
                totalPhotos: 0,
                averageBucketSize: 0,
                maxBucketSize: 0,
                minBucketSize: 0,
                singletonBuckets: 0
            )
        }

        let sizes = buckets.map { $0.count }
        let total = sizes.reduce(0, +)

        return BucketStats(
            totalBuckets: buckets.count,
            totalPhotos: total,
            averageBucketSize: Double(total) / Double(buckets.count),
            maxBucketSize: sizes.max() ?? 0,
            minBucketSize: sizes.min() ?? 0,
            singletonBuckets: sizes.filter { $0 == 1 }.count
        )
    }
}
