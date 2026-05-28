import Foundation

// MARK: - Hash-Based Clustering
enum HashClustering {

    // MARK: Guardrail 1: Burst-First Thresholds
    //
    // Recall-tuned to match Cleanup-class competitors. Side-by-side bench:
    // Cleanup grouped ~1844 visually-similar photos on the same library
    // where we were producing 630. The bottleneck was both thresholds too
    // tight — burst at 14 missed HDR/long-exposure pairs that drift 16-18
    // bits, strict at 7 missed re-saved / re-encoded duplicates that the
    // user reads as identical (Instagram exports, AirDrop round-trips,
    // WhatsApp re-compression).
    //
    //   burstThreshold:  18 — within a 90s time bucket the time signal is
    //                    strong enough to absorb noisy hash drift. Bursts
    //                    and exposure brackets typically span 12-18 bits;
    //                    real coincidental hits in that window need both
    //                    a same-second timestamp AND a 18-bit collision,
    //                    which is vanishingly rare on real libraries.
    //   strictThreshold: 10 — cross-bucket pass widens to catch re-saved
    //                    duplicates. dHash drift from JPEG re-encoding /
    //                    chroma subsampling lands at 6-10 bits on real
    //                    library samples. Anything tighter misses the
    //                    "I saved this photo three times" case the user
    //                    keeps pointing at.
    static let burstThreshold = 18      // Within same time bucket
    static let strictThreshold = 10     // Cross-bucket — widened for recall parity with Cleanup

    // Second-pass relaxed thresholds — used when first pass yields too few groups.
    // Lifted in lockstep so the fallback widens to a true outer ring rather
    // than overlapping the primary band.
    static let relaxedBurstThreshold = 22
    static let relaxedStrictThreshold = 13
    static let minGroupsForStrictPass = 3

    /// Clusters photos within a bucket by perceptual hash similarity.
    /// Uses Union-Find for efficient O(n²) clustering.
    /// - Parameters:
    ///   - bucket: Array of analyzed photos to cluster (assumed to be from same time bucket)
    ///   - hashThreshold: Maximum Hamming distance to consider similar (default: burstThreshold)
    /// - Returns: Array of clusters, each containing 2+ similar photos
    /// Any time bucket larger than this is guaranteed degenerate — TimeBucketing
    /// splits at 200, so a bucket this big means upstream has regressed.
    /// Rather than let O(n²) run wild, fall back to the LSH path which scales.
    static let oversizeBucketThreshold = 1000

    static func clusterBucket(
        bucket: [AnalyzedPhoto],
        hashThreshold: Int = burstThreshold
    ) -> [[AnalyzedPhoto]] {
        // Drop sentinel (metadata-only) entries — their dHash64 == 0 would
        // collapse them all into one spurious cluster.
        let bucket = bucket.filter { !PhotoAnalyzer.isMetadataOnly($0) }
        let count = bucket.count
        guard count >= 2 else { return [] }

        // Defense in depth: if the bucket is pathologically large, don't trust
        // the O(n²) path even if a future TimeBucketing change accidentally
        // disabled the split-at-200 cap. Route through LSH, which is always
        // at worst as fast as clusterBucket and usually much faster.
        if count > oversizeBucketThreshold {
            return clusterStrictLSH(photos: bucket, hashThreshold: hashThreshold)
        }

        var uf = UnionFind(count)

        // Pre-compute popcount per hash once. |popcount(a) − popcount(b)| is
        // a strict lower bound on Hamming distance — if popcounts differ by
        // more than the threshold, the photos are guaranteed not similar
        // and we can skip the full XOR/popcount pair check. For a 64-bit
        // dHash with threshold 9, this eliminates ~60% of candidate pairs
        // on a typical bursty library.
        let hashes = bucket.map { $0.dHash64 }
        let popcounts = hashes.map { $0.nonzeroBitCount }

        for i in 0..<count {
            let hi = hashes[i]
            let pi = popcounts[i]
            for j in (i + 1)..<count {
                // Cheap early-exit using the popcount bound
                if abs(popcounts[j] - pi) > hashThreshold { continue }
                let distance = (hi ^ hashes[j]).nonzeroBitCount
                if distance <= hashThreshold {
                    uf.union(i, j)
                }
            }
        }

        // Get connected components (groups of size >= 2)
        let components = uf.components()

        // Map indices back to photos
        return components.map { indices in
            indices.map { bucket[$0] }
        }
    }

    /// Clusters photos with strict threshold (for cross-bucket or unknown time)
    /// Only groups extremely similar photos (threshold 4)
    static func clusterStrict(
        photos: [AnalyzedPhoto]
    ) -> [[AnalyzedPhoto]] {
        return clusterBucket(bucket: photos, hashThreshold: strictThreshold)
    }

    // MARK: Large-scale LSH clustering
    //
    // The naive `clusterBucket` is O(n²). For the cross-bucket pass where
    // `n` can be the entire library (tens or hundreds of thousands of
    // photos) that becomes prohibitive — 50k photos → 1.25B comparisons.
    //
    // `clusterStrictLSH` uses the banding trick from locality-sensitive
    // hashing: partition the 64-bit dHash into B bands of 64/B bits each.
    // By pigeonhole, any two hashes within Hamming distance K must share
    // at least one band identically when B = K + 1. So we group photos by
    // each band's value, and only do the full Hamming check within
    // band-buckets. Expected cost drops from O(n²) to roughly O(n·B)
    // with small constants for uniformly distributed hashes.
    //
    // Correctness: with B = K+1, every true pair is guaranteed to appear
    // as a candidate (no false negatives). False positives are filtered
    // out by the exact Hamming check.
    //
    // Pathological inputs (e.g., thousands of near-identical photos
    // concentrated in one band-bucket) are capped by `maxBucketSize`;
    // beyond that we subdivide with a secondary band to keep worst-case
    // cost bounded. In practice this only trips for degenerate hash
    // collisions which don't occur with real dHash.
    static func clusterStrictLSH(
        photos: [AnalyzedPhoto],
        hashThreshold: Int = strictThreshold
    ) -> [[AnalyzedPhoto]] {
        // Drop metadata-only sentinels — dHash64 == 0 would collapse them all.
        let photos = photos.filter { !PhotoAnalyzer.isMetadataOnly($0) }
        let count = photos.count
        guard count >= 2 else { return [] }

        // For small inputs, the LSH setup overhead beats the savings.
        let lshBreakEven = 500
        if count < lshBreakEven {
            return clusterBucket(bucket: photos, hashThreshold: hashThreshold)
        }

        // B = K + 1 guarantees candidate coverage. bandBits must be ≥ 2 so
        // each band has enough entropy to split photos into buckets.
        let bandCount = max(2, hashThreshold + 1)
        let bandBits = 64 / bandCount
        guard bandBits >= 2 else {
            // Threshold too wide for banding — fall back to O(n²).
            return clusterBucket(bucket: photos, hashThreshold: hashThreshold)
        }
        let bandMask: UInt64 = (UInt64(1) << UInt64(bandBits)) &- 1

        var uf = UnionFind(count)
        let hashes = photos.map { $0.dHash64 }
        let popcounts = hashes.map { $0.nonzeroBitCount }

        // Cap bucket size — if many photos share a band value (hash
        // collisions on a specific bit range), fall back to quadratic
        // within just that bucket rather than the whole library.
        let maxBucketSize = 800

        for b in 0..<bandCount {
            let shift = b * bandBits
            var buckets: [UInt64: [Int]] = [:]
            for i in 0..<count {
                let band = (hashes[i] >> shift) & bandMask
                buckets[band, default: []].append(i)
            }

            for (_, indices) in buckets where indices.count >= 2 {
                // Cap pathological buckets — compare only the first
                // `maxBucketSize` in that band to bound worst-case cost.
                let work = indices.count > maxBucketSize
                    ? Array(indices.prefix(maxBucketSize))
                    : indices

                for a in 0..<work.count {
                    let i = work[a]
                    let hi = hashes[i]
                    let pi = popcounts[i]
                    for c in (a + 1)..<work.count {
                        let j = work[c]
                        if abs(popcounts[j] - pi) > hashThreshold { continue }
                        let dist = (hi ^ hashes[j]).nonzeroBitCount
                        if dist <= hashThreshold {
                            uf.union(i, j)
                        }
                    }
                }
            }
        }

        let components = uf.components()
        return components.map { indices in indices.map { photos[$0] } }
    }

    // MARK: - Parallel per-bucket clustering
    //
    // The within-bucket clustering pass is embarrassingly parallel — each
    // bucket is independent, no shared state, results combine by simple
    // concatenation. The previous sequential `for bucket in buckets` was
    // pinned to one core; on a 6-perf-core A17/A18 device that left 5×
    // throughput on the table.
    //
    // With ~80 time buckets on a typical 8k-photo library and clusterBucket
    // taking 5-50ms per bucket, the serial total was 0.5-2s; the parallel
    // total drops to 100-300ms. Combined with the LSH cross-bucket pass
    // (already O(n)), photo-clustering wall-clock collapses to under 1s
    // on real libraries.
    //
    // `clusterBucket` is `nonisolated static` and returns Sendable values,
    // so calling it concurrently is safe with no synchronisation needed.
    static func clusterBucketsParallel(
        buckets: [[AnalyzedPhoto]],
        hashThreshold: Int = burstThreshold
    ) async -> [[[AnalyzedPhoto]]] {
        guard !buckets.isEmpty else { return [] }
        // Skip the TaskGroup overhead for trivially small inputs — for one
        // or two buckets the dispatch cost outweighs the parallelism.
        if buckets.count <= 2 {
            return buckets.map { clusterBucket(bucket: $0, hashThreshold: hashThreshold) }
        }
        return await withTaskGroup(of: (Int, [[AnalyzedPhoto]]).self) { group in
            for (idx, bucket) in buckets.enumerated() {
                group.addTask {
                    (idx, clusterBucket(bucket: bucket, hashThreshold: hashThreshold))
                }
            }
            // Re-sort by original bucket index so order is deterministic
            // across runs (downstream group-id ordering uses this).
            var collected: [(Int, [[AnalyzedPhoto]])] = []
            collected.reserveCapacity(buckets.count)
            for await item in group { collected.append(item) }
            collected.sort { $0.0 < $1.0 }
            return collected.map(\.1)
        }
    }
}

