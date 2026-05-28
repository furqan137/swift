import Foundation

// MARK: - Indexing Progress
struct IndexingProgress {
    var totalAssets: Int = 0
    var processedAssets: Int = 0
    var batchesSent: Int = 0
    var phase: String = "Idle"
    var isComplete: Bool = false
    var error: String?

    var percent: Int {
        guard totalAssets > 0 else { return 0 }
        return Int(Double(processedAssets) / Double(totalAssets) * 100)
    }
}

// MARK: - Indexing Metrics (instrumentation)
struct IndexingMetrics {
    /// Wall-clock when the current run started.
    var runStartedAt: Date?
    /// Total assets the pipeline has successfully upserted during this run.
    var assetsThisRun: Int = 0
    /// Rolling average of per-asset embedding generation time (thumbnail + base64).
    var avgEmbedLatencyMs: Double = 0
    /// Rolling average of per-asset upsert round-trip time.
    var avgUpsertLatencyMs: Double = 0
    /// Count of assets that failed after all retries this run.
    var failedThisRun: Int = 0
    /// Number of times the pipeline has had to resume across app launches.
    var resumeCount: Int = 0
    /// When present, the pipeline finished cleanly at this timestamp.
    var completedAt: Date?

    /// Throughput in assets/second over the current run.
    var assetsPerSecond: Double {
        guard let start = runStartedAt, assetsThisRun > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.01 else { return 0 }
        return Double(assetsThisRun) / elapsed
    }

    /// Failure rate as a fraction (0...1) over the current run.
    var failureRate: Double {
        let attempted = assetsThisRun + failedThisRun
        guard attempted > 0 else { return 0 }
        return Double(failedThisRun) / Double(attempted)
    }
}
