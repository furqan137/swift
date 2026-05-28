import Foundation

// MARK: - Cleanup Orchestrator
/// Builds guided cleanup rounds from the DashboardSnapshot.
/// Runs entirely client-side with dopamine-optimized checkpoint pacing.
@MainActor
final class CleanupOrchestrator {
    static let shared = CleanupOrchestrator()
    private init() {}

    /// Checkpoint count from task size, with ±1 jitter, clamped to [2, 5].
    static func checkpointCount(forBytes bytes: Int64) -> Int {
        let mb = Double(bytes) / 1_000_000
        let base: Int
        if mb < 250 { base = 2 }
        else if mb < 750 { base = 3 }
        else if mb < 1500 { base = 4 }
        else { base = 5 }
        return min(5, max(2, base + Int.random(in: -1...1)))
    }

    // MARK: - Scored Candidate (internal)

    private struct ScoredCandidate {
        let assetId: String
        let category: CleanupTaskCategory
        let isBest: Bool
        let fileSize: Int64
        let groupId: String?
        let storageImpact: Double
        let confidenceScore: Double
        let emotionalRisk: Double
        var noveltyScore: Double
    }

    // MARK: - Dashboard-tier plan (lightweight, no store access)

    /// Build a today plan from the current snapshot + clean score.
    /// Used for the dashboard card display. No store walking needed.
    func buildTodayPlan(
        from snapshot: DashboardSnapshot,
        cleanScore: Int
    ) -> TodayCleanupPlan {
        let totalRecoverableGB = Double(snapshot.totalClutterBytes) / 1_000_000_000

        // If nothing to clean, return empty
        guard totalRecoverableGB > 0.001 else {
            return TodayCleanupPlan(
                totalRecoverableBytes: snapshot.totalClutterBytes,
                roundBytes: 0,
                tasks: [],
                estimatedSeconds: 0,
                beeHealthScore: cleanScore,
                subtitle: "Scanning for cleanup tasks..."
            )
        }

        // Target GB for this session: 4% of total, clamped
        let taskGB = min(max(totalRecoverableGB * 0.04, 0.5), 2.0)
        let cappedGB = min(taskGB, 3.0)
        let roundBytes = Int64(cappedGB * 1_000_000_000)

        // Checkpoint count based on session size, with slight randomness so
        // tasks feel varied / dopamine-paced. Always clamped to [2, 5].
        let checkpointCount = Self.checkpointCount(forBytes: roundBytes)

        let decisionsPerCheckpoint = 8
        let totalDecisions = checkpointCount * decisionsPerCheckpoint

        // Build checkpoint tasks (itemRefs left empty for dashboard)
        var tasks: [CleanupTask] = []
        let bytesPerCheckpoint = roundBytes / Int64(checkpointCount)
        for i in 1...checkpointCount {
            tasks.append(CleanupTask(
                id: "checkpoint_\(i)",
                icon: "flag.fill",
                title: "Checkpoint \(i)",
                estimatedBytes: bytesPerCheckpoint,
                category: .duplicatePhotos // placeholder, actual items mixed
            ))
        }

        let estimatedSeconds = min(max(totalDecisions * 6, 45), 90)

        let subtitle = "Bee found a quick cleanup for you"

        return TodayCleanupPlan(
            totalRecoverableBytes: snapshot.totalClutterBytes,
            roundBytes: roundBytes,
            tasks: tasks,
            estimatedSeconds: estimatedSeconds,
            beeHealthScore: cleanScore,
            subtitle: subtitle,
            checkpointCount: checkpointCount
        )
    }

    // MARK: - Resolution-tier plan (full item resolution + pacing)

    /// Called once when user taps "Start Quick Cleanup". Walks the store
    /// to build a scored pool, selects items, assigns to checkpoints with
    /// dopamine-optimized pacing, and fills itemRefs on each task.
    ///
    /// `excluding` is the per-task "seen set" — asset IDs already presented
    /// in the current task. Within a single task, this is reset to empty
    /// when a new task starts, so old assets become eligible again.
    func buildResolvedPlan(
        from snapshot: DashboardSnapshot,
        cleanScore: Int,
        store: SimilarPhotosStore,
        excluding: Set<String> = []
    ) -> TodayCleanupPlan {
        // Start from dashboard plan for sizing
        var plan = buildTodayPlan(from: snapshot, cleanScore: cleanScore)
        guard plan.checkpointCount > 0 else { return plan }

        let totalDecisions = plan.checkpointCount * 8

        // [DUP-DIAG] Temporary: trace why duplicates may not be reaching the deck.
        let dupGroupsHigh = store.groups.filter { $0.confidence >= 0.85 }.count
        let dupGroupsLow = store.groups.filter { $0.confidence < 0.85 }.count
        print("[DUP-DIAG] buildResolvedPlan entry — excluding=\(excluding.count) totalGroups=\(store.groups.count) high(>=0.85)=\(dupGroupsHigh) low(<0.85)=\(dupGroupsLow)")

        // 1. Build scored pool
        let pool = buildScoredPool(store: store, excluding: excluding)
        let dupCount = pool.filter { $0.category == .duplicatePhotos }.count
        print("[DUP-DIAG] buildResolvedPlan pool total=\(pool.count) duplicatePhotos=\(dupCount)")

        // Pool exhaustion: with persistent cross-task exclusion the pool
        // shrinks monotonically until the user takes new photos. Bail with a
        // flag the UI can show as an empty state — never hand back an empty
        // or stub deck that looks broken to the user.
        let minimumViableTask = 1 // any remaining eligible item forms a task
        guard pool.count >= minimumViableTask else {
            return TodayCleanupPlan(
                totalRecoverableBytes: plan.totalRecoverableBytes,
                roundBytes: 0,
                tasks: [],
                estimatedSeconds: 0,
                beeHealthScore: plan.beeHealthScore,
                subtitle: "You're all caught up",
                checkpointCount: 0,
                isPoolExhausted: true
            )
        }

        // 2. Select items for session (use whatever is available)
        let selected = selectItems(from: pool, count: totalDecisions)

        // For small pools, reduce checkpoint count so each has enough items
        let effectiveCheckpoints = max(1, min(plan.checkpointCount, selected.count / 2))

        // 3. Assign to checkpoints
        let checkpoints = assignToCheckpoints(
            items: selected,
            count: effectiveCheckpoints
        )

        // 4. Apply pacing + fill itemRefs
        var resolvedTasks: [CleanupTask] = []
        for (i, checkpoint) in checkpoints.enumerated() {
            let paced = applyPacing(to: checkpoint)
            let refs = paced.map { c in
                CheckpointItemRef(
                    assetId: c.assetId,
                    category: c.category,
                    isBest: c.isBest,
                    fileSize: c.fileSize,
                    groupId: c.groupId
                )
            }
            let totalBytes = paced.reduce(Int64(0)) { $0 + $1.fileSize }
            resolvedTasks.append(CleanupTask(
                id: "checkpoint_\(i + 1)",
                icon: "flag.fill",
                title: "Checkpoint \(i + 1)",
                estimatedBytes: totalBytes,
                category: .duplicatePhotos,
                itemRefs: refs
            ))
        }

        // Coins are no longer pre-assigned per checkpoint — they're computed
        // at award time from the user's actual review/selection (see
        // ProgressManager / coin-progression.service). Nothing to score here.
        let taskBytes = resolvedTasks.reduce(Int64(0)) { $0 + $1.estimatedBytes }

        plan = TodayCleanupPlan(
            totalRecoverableBytes: plan.totalRecoverableBytes,
            roundBytes: taskBytes,
            tasks: resolvedTasks,
            estimatedSeconds: plan.estimatedSeconds,
            beeHealthScore: plan.beeHealthScore,
            subtitle: plan.subtitle,
            checkpointCount: effectiveCheckpoints
        )

        return plan
    }

    // MARK: - Step 1: Build Scored Pool

    private func buildScoredPool(
        store: SimilarPhotosStore,
        excluding: Set<String> = []
    ) -> [ScoredCandidate] {
        var candidates: [ScoredCandidate] = []
        // Seed with caller-supplied exclusion set so the same `insert` check
        // also enforces the per-task seen set without a second branch in
        // every loop body.
        var seenIds = excluding
        var categoryCounts: [CleanupTaskCategory: Int] = [:]

        // Collect all file sizes for median calculation
        var allSizes: [Int64] = []

        // Helper to compute novelty
        func novelty(for category: CleanupTaskCategory) -> Double {
            let n = categoryCounts[category, default: 0]
            categoryCounts[category] = n + 1
            return pow(0.9, Double(n))
        }

        // Duplicate photos (confidence >= 0.85)
        // [DUP-DIAG] Temporary: per-group accounting for non-best vs excluded vs added.
        var dupNonBest = 0
        var dupExcluded = 0
        var dupAdded = 0
        for group in store.groups where group.confidence >= 0.85 {
            let gid = group.id.uuidString
            for item in group.items where !item.isBest {
                dupNonBest += 1
                guard seenIds.insert(item.assetId).inserted else { dupExcluded += 1; continue }
                dupAdded += 1
                allSizes.append(item.fileSize)
                candidates.append(ScoredCandidate(
                    assetId: item.assetId,
                    category: .duplicatePhotos,
                    isBest: false,
                    fileSize: item.fileSize,
                    groupId: gid,
                    storageImpact: 0, // filled after median
                    confidenceScore: group.confidence,
                    emotionalRisk: 0.1,
                    noveltyScore: novelty(for: .duplicatePhotos)
                ))
            }
        }
        print("[DUP-DIAG] buildScoredPool dup block — nonBestSeen=\(dupNonBest) excludedBySeenSet=\(dupExcluded) added=\(dupAdded)")

        // Similar photos (confidence < 0.85)
        for group in store.groups where group.confidence < 0.85 {
            let gid = group.id.uuidString
            for item in group.items where !item.isBest {
                guard seenIds.insert(item.assetId).inserted else { continue }
                allSizes.append(item.fileSize)
                candidates.append(ScoredCandidate(
                    assetId: item.assetId,
                    category: .similarPhotos,
                    isBest: false,
                    fileSize: item.fileSize,
                    groupId: gid,
                    storageImpact: 0,
                    confidenceScore: group.confidence,
                    emotionalRisk: 0.5,
                    noveltyScore: novelty(for: .similarPhotos)
                ))
            }
        }

        // Similar screenshots
        for group in store.screenshotGroups {
            let gid = group.id.uuidString
            for item in group.items where !item.isBest {
                guard seenIds.insert(item.assetId).inserted else { continue }
                allSizes.append(item.fileSize)
                candidates.append(ScoredCandidate(
                    assetId: item.assetId,
                    category: .similarScreenshots,
                    isBest: false,
                    fileSize: item.fileSize,
                    groupId: gid,
                    storageImpact: 0,
                    confidenceScore: group.confidence,
                    emotionalRisk: 0.1,
                    noveltyScore: novelty(for: .similarScreenshots)
                ))
            }
        }

        // Flat screenshots
        for asset in store.screenshotScanResult.screenshots {
            guard seenIds.insert(asset.assetId).inserted else { continue }
            allSizes.append(asset.fileSize)
            candidates.append(ScoredCandidate(
                assetId: asset.assetId,
                category: .screenshots,
                isBest: false,
                fileSize: asset.fileSize,
                groupId: nil,
                storageImpact: 0,
                confidenceScore: 0.7,
                emotionalRisk: 0.1,
                noveltyScore: novelty(for: .screenshots)
            ))
        }

        // Blurry photos
        for asset in store.blurryPhotos {
            guard seenIds.insert(asset.assetId).inserted else { continue }
            allSizes.append(asset.fileSize)
            candidates.append(ScoredCandidate(
                assetId: asset.assetId,
                category: .blurryPhotos,
                isBest: false,
                fileSize: asset.fileSize,
                groupId: nil,
                storageImpact: 0,
                confidenceScore: 0.7,
                emotionalRisk: 0.3,
                noveltyScore: novelty(for: .blurryPhotos)
            ))
        }

        // Similar videos
        for group in store.videoGroups {
            let gid = group.id.uuidString
            for item in group.items where !item.isBest {
                guard seenIds.insert(item.assetId).inserted else { continue }
                allSizes.append(item.fileSize)
                candidates.append(ScoredCandidate(
                    assetId: item.assetId,
                    category: .similarVideos,
                    isBest: false,
                    fileSize: item.fileSize,
                    groupId: gid,
                    storageImpact: 0,
                    confidenceScore: group.confidence,
                    emotionalRisk: 0.5,
                    noveltyScore: novelty(for: .similarVideos)
                ))
            }
        }

        // Screen recordings
        for asset in store.screenRecordingScanResult.screenshots {
            guard seenIds.insert(asset.assetId).inserted else { continue }
            allSizes.append(asset.fileSize)
            candidates.append(ScoredCandidate(
                assetId: asset.assetId,
                category: .screenRecordings,
                isBest: false,
                fileSize: asset.fileSize,
                groupId: nil,
                storageImpact: 0,
                confidenceScore: 0.7,
                emotionalRisk: 0.1,
                noveltyScore: novelty(for: .screenRecordings)
            ))
        }

        // Short videos
        for asset in store.shortVideoScanResult.screenshots {
            guard seenIds.insert(asset.assetId).inserted else { continue }
            allSizes.append(asset.fileSize)
            candidates.append(ScoredCandidate(
                assetId: asset.assetId,
                category: .shortRecordings,
                isBest: false,
                fileSize: asset.fileSize,
                groupId: nil,
                storageImpact: 0,
                confidenceScore: 0.7,
                emotionalRisk: 0.3,
                noveltyScore: novelty(for: .shortRecordings)
            ))
        }

        // Long videos
        for asset in store.longVideoScanResult.screenshots {
            guard seenIds.insert(asset.assetId).inserted else { continue }
            allSizes.append(asset.fileSize)
            candidates.append(ScoredCandidate(
                assetId: asset.assetId,
                category: .longVideos,
                isBest: false,
                fileSize: asset.fileSize,
                groupId: nil,
                storageImpact: 0,
                confidenceScore: 0.7,
                emotionalRisk: 0.3,
                noveltyScore: novelty(for: .longVideos)
            ))
        }

        // Compute median file size and fill storageImpact
        allSizes.sort()
        let median: Double = allSizes.isEmpty ? 1 : Double(allSizes[allSizes.count / 2])
        let safeMedian = max(median, 1.0)

        for i in candidates.indices {
            candidates[i] = ScoredCandidate(
                assetId: candidates[i].assetId,
                category: candidates[i].category,
                isBest: candidates[i].isBest,
                fileSize: candidates[i].fileSize,
                groupId: candidates[i].groupId,
                storageImpact: Double(candidates[i].fileSize) / safeMedian,
                confidenceScore: candidates[i].confidenceScore,
                emotionalRisk: candidates[i].emotionalRisk,
                noveltyScore: candidates[i].noveltyScore
            )
        }

        return candidates
    }

    // MARK: - Step 2: Select Items

    private func selectItems(
        from pool: [ScoredCandidate],
        count: Int
    ) -> [ScoredCandidate] {
        // Sort by composite score: high storage impact, low emotional risk, high confidence
        let sorted = pool.sorted { a, b in
            let scoreA = a.storageImpact * (1 - a.emotionalRisk) * a.confidenceScore
            let scoreB = b.storageImpact * (1 - b.emotionalRisk) * b.confidenceScore
            return scoreA > scoreB
        }

        // Relative diversity cap. The 70% rule prevents an all-duplicates
        // task when other categories have real supply — but with persistent
        // cross-task exclusion, a heavy user eventually drains the lighter
        // categories. Forcing weak candidates from a thin category in just
        // to satisfy the cap degrades quality. So: only enforce the cap
        // when the second-largest category has at least 30% of budget
        // available. Otherwise, take the best candidates regardless of
        // category — quality > diversity once supply is one-sided.
        var poolSupply: [CleanupTaskCategory: Int] = [:]
        for c in pool { poolSupply[c.category, default: 0] += 1 }
        let supplySorted = poolSupply.values.sorted(by: >)
        let secondLargest = supplySorted.count >= 2 ? supplySorted[1] : 0
        let supplyThreshold = Int(Double(count) * 0.3)
        let enforceCap = secondLargest >= supplyThreshold

        var selected: [ScoredCandidate] = []
        var categoryCounts: [CleanupTaskCategory: Int] = [:]
        let maxPerCategory = Int(Double(count) * 0.7)

        for candidate in sorted {
            if selected.count >= count { break }
            if enforceCap {
                let catCount = categoryCounts[candidate.category, default: 0]
                if catCount >= maxPerCategory { continue }
            }
            selected.append(candidate)
            categoryCounts[candidate.category, default: 0] += 1
        }

        return selected
    }

    // MARK: - Step 3: Assign to Checkpoints

    private func assignToCheckpoints(
        items: [ScoredCandidate],
        count: Int
    ) -> [[ScoredCandidate]] {
        guard count > 0 else { return [] }

        var checkpoints = Array(repeating: [ScoredCandidate](), count: count)

        // Separate grouped vs flat items
        let grouped = items.filter { $0.groupId != nil }
        let flat = items.filter { $0.groupId == nil }

        // Group items by their groupId
        var groupBuckets: [String: [ScoredCandidate]] = [:]
        for item in grouped {
            groupBuckets[item.groupId!, default: []].append(item)
        }

        // Assign grouped items — keep group members together
        var checkpointIdx = 0
        for (_, groupItems) in groupBuckets {
            // Find checkpoint with most room
            let targetIdx = checkpoints.enumerated()
                .min(by: { $0.element.count < $1.element.count })?.offset ?? checkpointIdx
            checkpoints[targetIdx].append(contentsOf: groupItems)
            checkpointIdx = (targetIdx + 1) % count
        }

        // Assign flat items — fill smallest checkpoints first
        for item in flat {
            let targetIdx = checkpoints.enumerated()
                .min(by: { $0.element.count < $1.element.count })?.offset ?? 0
            checkpoints[targetIdx].append(item)
        }

        return checkpoints
    }

    // MARK: - Step 4: Apply Pacing

    private func applyPacing(to items: [ScoredCandidate]) -> [ScoredCandidate] {
        guard items.count > 1 else { return items }

        // Classify items
        let isGrouped: (ScoredCandidate) -> Bool = { $0.groupId != nil }
        let isStorageSpike: (ScoredCandidate) -> Bool = { $0.storageImpact > 2.0 }

        var groupedItems = items.filter { isGrouped($0) && !isStorageSpike($0) }
        var exploratoryItems = items.filter { !isGrouped($0) && !isStorageSpike($0) }
        var spikes = items.filter { isStorageSpike($0) }

        // Sort grouped by confidence desc (easy wins first)
        groupedItems.sort { $0.confidenceScore > $1.confidenceScore }

        var result: [ScoredCandidate] = []

        // Pacing pattern: easy wins -> exploratory -> grouped -> spike -> exploratory -> grouped payoff
        // Positions 1-2: Easy grouped wins
        for _ in 0..<2 {
            if let item = groupedItems.first {
                result.append(item)
                groupedItems.removeFirst()
            } else if let item = exploratoryItems.first {
                result.append(item)
                exploratoryItems.removeFirst()
            }
        }

        // Positions 3-4: Exploratory
        for _ in 0..<2 {
            if let item = exploratoryItems.first {
                result.append(item)
                exploratoryItems.removeFirst()
            } else if let item = groupedItems.first {
                result.append(item)
                groupedItems.removeFirst()
            }
        }

        // Position 5: Another grouped win
        if let item = groupedItems.first {
            result.append(item)
            groupedItems.removeFirst()
        } else if let item = exploratoryItems.first {
            result.append(item)
            exploratoryItems.removeFirst()
        }

        // Positions 6-7: Storage spikes if available, else exploratory
        for _ in 0..<2 {
            if let item = spikes.first {
                result.append(item)
                spikes.removeFirst()
            } else if let item = exploratoryItems.first {
                result.append(item)
                exploratoryItems.removeFirst()
            } else if let item = groupedItems.first {
                result.append(item)
                groupedItems.removeFirst()
            }
        }

        // Position 8: Final grouped win (payoff)
        if let item = groupedItems.first {
            result.append(item)
            groupedItems.removeFirst()
        } else if let item = exploratoryItems.first {
            result.append(item)
            exploratoryItems.removeFirst()
        }

        // Append any remaining items
        result.append(contentsOf: groupedItems)
        result.append(contentsOf: exploratoryItems)
        result.append(contentsOf: spikes)

        // Break long runs: never >4 consecutive items from the same category
        var final = result
        var i = 0
        while i < final.count {
            var runLength = 1
            while i + runLength < final.count
                    && final[i + runLength].category == final[i].category {
                runLength += 1
            }
            if runLength > 4 {
                // Find next item with different category and swap
                let swapFrom = i + 4
                if let swapTo = (swapFrom..<final.count)
                    .first(where: { final[$0].category != final[i].category }) {
                    final.swapAt(swapFrom, swapTo)
                }
            }
            i += runLength
        }

        return final
    }

}

