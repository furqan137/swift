import Foundation

// MARK: - Time Bucketing
/// Groups photos into time-based buckets for efficient similarity comparison.
/// Photos taken close together in time are more likely to be duplicates.
enum TimeBucketing {

    /// Groups photos into buckets where consecutive photos are within the time window.
    /// - Parameters:
    ///   - photos: Array of analyzed photos (will be sorted by createdAt)
    ///   - secondsWindow: Maximum time gap between consecutive photos in a bucket (default: 60s)
    ///   - burstIds: Optional map of assetId → PHAsset.burstIdentifier. Photos
    ///     sharing a non-empty burst id are grouped into a single bucket up
    ///     front, regardless of inter-shot timing or bucket size — Apple's own
    ///     burst grouping is a stronger signal than a 90-second time window.
    ///     Photos without a burst id fall through to the standard time-window
    ///     bucketing path.
    /// - Returns: Array of photo buckets, each containing temporally close photos
    // Default time window for grouping burst photos
    static let defaultTimeWindow: TimeInterval = 90  // Was 45s — wider window catches more similar shots

    static func timeBuckets(
        photos: [AnalyzedPhoto],
        secondsWindow: TimeInterval = defaultTimeWindow,
        burstIds: [String: String] = [:]
    ) -> [[AnalyzedPhoto]] {
        // Metadata-only photos (decode failed) have a sentinel hash of 0 and
        // sharpnessScore < 0. They MUST NOT enter clustering or they would
        // all collide at Hamming distance 0 and form a giant fake group.
        // They still live in analyzedIndex so they appear in Other Photos.
        let photos = photos.filter { !PhotoAnalyzer.isMetadataOnly($0) }
        guard !photos.isEmpty else { return [] }

        // Burst-first split. Apple groups burst captures behind a shared
        // burstIdentifier; with `includeAllBurstAssets = true` we see every
        // frame in the burst. A burst can span 200+ frames over several
        // seconds, easily blowing past the 90s time window's natural splits.
        // Pulling burst sets into their own buckets up front catches every
        // intra-burst duplicate even when a single burst spans multiple
        // 30-second sub-bucketing windows in `splitIfNeeded`.
        var burstBuckets: [String: [AnalyzedPhoto]] = [:]
        var nonBurst: [AnalyzedPhoto] = []
        nonBurst.reserveCapacity(photos.count)
        for photo in photos {
            if let burstId = burstIds[photo.assetIdentifier], !burstId.isEmpty {
                burstBuckets[burstId, default: []].append(photo)
            } else {
                nonBurst.append(photo)
            }
        }
        let burstClusters: [[AnalyzedPhoto]] = burstBuckets.values.map { Array($0) }

        // Photos with no creationDate (cloud-imported, screenshots from
        // older iOS versions, AirDropped images with stripped metadata) used
        // to fall back to .distantPast — which made every nil-date asset
        // collapse into one giant fake bucket. Pull them out here and emit
        // each as its own singleton bucket; the cross-bucket LSH pass
        // (clusterStrictLSH) still catches real similarity between them.
        // Project to (photo, date) tuples so the non-nil date becomes
        // structural — eliminates three force-unwraps below that previously
        // claimed "safe" only because of an invariant the type system didn't
        // enforce. compactMap drops anything with nil date in one pass.
        let dated: [(photo: AnalyzedPhoto, date: Date)] = nonBurst.compactMap { photo in
            guard let date = photo.creationDate else { return nil }
            return (photo, date)
        }
        let dateless = nonBurst.filter { $0.creationDate == nil }

        var buckets: [[AnalyzedPhoto]] = burstClusters
        buckets.append(contentsOf: dateless.map { [$0] })

        guard !dated.isEmpty else { return buckets }

        let sorted = dated.sorted { $0.date < $1.date }
        guard let firstEntry = sorted.first else { return buckets }

        var currentBucket: [AnalyzedPhoto] = [firstEntry.photo]
        var lastDate = firstEntry.date

        for i in 1..<sorted.count {
            let entry = sorted[i]
            let photo = entry.photo
            let photoDate = entry.date
            let gap = photoDate.timeIntervalSince(lastDate)

            if gap <= secondsWindow {
                // Still within window, add to current bucket
                currentBucket.append(photo)
            } else {
                // Gap too large, finalize current bucket and start new one
                buckets.append(contentsOf: splitIfNeeded(currentBucket))
                currentBucket = [photo]
            }

            lastDate = photoDate
        }

        // Don't forget the last bucket
        if !currentBucket.isEmpty {
            buckets.append(contentsOf: splitIfNeeded(currentBucket))
        }

        return buckets
    }

    /// Splits a bucket into smaller sub-buckets if it exceeds the size limit.
    /// Uses a 30-second window for sub-bucketing.
    private static func splitIfNeeded(_ bucket: [AnalyzedPhoto], maxSize: Int = 200) -> [[AnalyzedPhoto]] {
        guard bucket.count > maxSize else {
            return [bucket]
        }

        // Re-bucket with tighter 30s window
        return timeBucketsStrict(photos: bucket, secondsWindow: 30, maxSize: maxSize)
    }

    /// Strict bucketing with hard size limit - will force-split even if within time window.
    private static func timeBucketsStrict(
        photos: [AnalyzedPhoto],
        secondsWindow: TimeInterval,
        maxSize: Int
    ) -> [[AnalyzedPhoto]] {
        guard !photos.isEmpty else { return [] }

        // Assume already sorted from parent call
        var buckets: [[AnalyzedPhoto]] = []
        var currentBucket: [AnalyzedPhoto] = [photos[0]]
        var bucketStartDate = photos[0].creationDate ?? Date.distantPast
        var lastDate = bucketStartDate

        for i in 1..<photos.count {
            let photo = photos[i]
            let photoDate = photo.creationDate ?? Date.distantPast
            let gapFromLast = photoDate.timeIntervalSince(lastDate)
            let gapFromStart = photoDate.timeIntervalSince(bucketStartDate)

            // Split if: gap too large OR bucket too big OR time span from bucket start exceeds window
            let shouldSplit = gapFromLast > secondsWindow ||
                              currentBucket.count >= maxSize ||
                              gapFromStart > secondsWindow * 2

            if shouldSplit {
                buckets.append(currentBucket)
                currentBucket = [photo]
                bucketStartDate = photoDate
            } else {
                currentBucket.append(photo)
            }

            lastDate = photoDate
        }

        if !currentBucket.isEmpty {
            buckets.append(currentBucket)
        }

        return buckets
    }
}

