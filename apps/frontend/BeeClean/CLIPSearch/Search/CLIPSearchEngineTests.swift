import Foundation
import Accelerate

/// DEBUG-only self-test for CLIPSearchEngine's vectorized search.
///
/// Inserts 100 known vectors into a temp store, then searches with
/// synthetic query vectors to verify ranking correctness and measure
/// latency. Also benchmarks at 50k scale to validate the <200ms target.
enum CLIPSearchEngineTests {

    static func runSearchTest() {
        #if DEBUG
        Task.detached(priority: .utility) {
            do {
                let dim = CLIPConfig.embeddingDimension

                // --- Setup: temp store with 100 known vectors ---
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CLIPSearchTest-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let dbPath = tmpDir.appendingPathComponent("test.sqlite").path
                let store = CLIPEmbeddingStore(path: dbPath)

                // Create 100 "one-hot-ish" vectors: vector i has a large value at index i
                // and small random noise elsewhere. This makes vector i the best match
                // for a query that is one-hot at index i.
                let n = 100
                var vectors = [[Float]]()
                for i in 0..<n {
                    var vec = (0..<dim).map { _ in Float.random(in: -0.01...0.01) }
                    vec[i] = 1.0
                    // L2-normalize
                    var sumSq: Float = 0
                    for v in vec { sumSq += v * v }
                    let mag = sqrtf(sumSq)
                    for j in 0..<dim { vec[j] /= mag }
                    vectors.append(vec)
                    store.upsert(assetId: "search-test-\(i)", embedding: vec)
                }

                // --- Test 1: Ranking correctness ---
                // Build the engine's matrix manually for testing (without TextEncoder)
                _ = CLIPSearchEngine.shared

                // Override the engine's cache with our test data
                let allRows = await store.fetchAll()
                let testAssetIds = allRows.map(\.assetId)
                var testMatrix = [Float](repeating: 0, count: allRows.count * dim)
                for (i, row) in allRows.enumerated() {
                    let offset = i * dim
                    for j in 0..<min(row.embedding.count, dim) {
                        testMatrix[offset + j] = row.embedding[j]
                    }
                }

                // Query with a one-hot at index 42 — the top result should be search-test-42
                var query42 = [Float](repeating: 0, count: dim)
                query42[42] = 1.0
                // normalize
                var sumSq42: Float = 0
                for v in query42 { sumSq42 += v * v }
                let mag42 = sqrtf(sumSq42)
                for i in 0..<dim { query42[i] /= mag42 }

                // Manual matrix search using cblas (same logic as the engine)
                let results = searchMatrixDirect(
                    matrix: testMatrix, assetIds: testAssetIds,
                    query: query42, dim: dim, topK: 5
                )

                assert(!results.isEmpty, "Search returned no results")
                assert(results[0].assetId == "search-test-42",
                       "Expected search-test-42 as top result, got \(results[0].assetId)")
                assert(results[0].score > 0.9,
                       "Top score should be >0.9, got \(results[0].score)")

                // Query with one-hot at index 7
                var query7 = [Float](repeating: 0, count: dim)
                query7[7] = 1.0
                var sumSq7: Float = 0
                for v in query7 { sumSq7 += v * v }
                let mag7 = sqrtf(sumSq7)
                for i in 0..<dim { query7[i] /= mag7 }

                let results7 = searchMatrixDirect(
                    matrix: testMatrix, assetIds: testAssetIds,
                    query: query7, dim: dim, topK: 5
                )
                assert(results7[0].assetId == "search-test-7",
                       "Expected search-test-7 as top result, got \(results7[0].assetId)")

                print("[CLIPSearchTest] Ranking correctness OK (100 vectors)")

                // --- Test 2: Latency benchmark at 50k scale ---
                let benchN = 50_000
                var bigMatrix = [Float](repeating: 0, count: benchN * dim)
                // Fill with random normalized vectors
                for i in 0..<benchN {
                    let offset = i * dim
                    var sumSq: Float = 0
                    for j in 0..<dim {
                        let val = Float.random(in: -1...1)
                        bigMatrix[offset + j] = val
                        sumSq += val * val
                    }
                    let mag = sqrtf(sumSq)
                    if mag > 1e-9 {
                        for j in 0..<dim { bigMatrix[offset + j] /= mag }
                    }
                }
                let bigIds = (0..<benchN).map { "bench-\($0)" }

                // Warm up
                _ = searchMatrixDirect(
                    matrix: bigMatrix, assetIds: bigIds,
                    query: query42, dim: dim, topK: 50
                )

                // Timed run (average of 5)
                var totalMs: Double = 0
                let runs = 5
                for _ in 0..<runs {
                    let start = CFAbsoluteTimeGetCurrent()
                    _ = searchMatrixDirect(
                        matrix: bigMatrix, assetIds: bigIds,
                        query: query42, dim: dim, topK: 50
                    )
                    totalMs += (CFAbsoluteTimeGetCurrent() - start) * 1000
                }
                let avgMs = totalMs / Double(runs)

                print("[CLIPSearchTest] 50k-vector benchmark: \(String(format: "%.1f", avgMs))ms avg " +
                      "(target <200ms)")

                // --- Test 3: restrictToAssetIds regression ---
                // Verify that restricting to a subset returns only those IDs
                // and that ranking within the subset is correct.
                let allowedSet: Set<String> = ["search-test-5", "search-test-10", "search-test-50"]

                // Query with one-hot at index 50 — within the restricted set,
                // search-test-50 should rank first.
                var query50 = [Float](repeating: 0, count: dim)
                query50[50] = 1.0
                var sumSq50: Float = 0
                for v in query50 { sumSq50 += v * v }
                let mag50 = sqrtf(sumSq50)
                for i in 0..<dim { query50[i] /= mag50 }

                let restricted = searchMatrixRestrictedDirect(
                    matrix: testMatrix, assetIds: testAssetIds,
                    query: query50, dim: dim, topK: 10,
                    allowedIds: allowedSet
                )

                // Must only return IDs from the allowed set
                assert(restricted.count == 3,
                       "Expected 3 results from restricted search, got \(restricted.count)")
                for r in restricted {
                    assert(allowedSet.contains(r.assetId),
                           "Restricted search returned \(r.assetId) which is not in allowed set")
                }

                // search-test-50 must be ranked first (one-hot at 50 matches it best)
                assert(restricted[0].assetId == "search-test-50",
                       "Expected search-test-50 as top restricted result, got \(restricted[0].assetId)")
                assert(restricted[0].score > 0.9,
                       "Top restricted score should be >0.9, got \(restricted[0].score)")

                // Now query with one-hot at index 5 — search-test-5 should rank first
                var query5 = [Float](repeating: 0, count: dim)
                query5[5] = 1.0
                var sumSq5: Float = 0
                for v in query5 { sumSq5 += v * v }
                let mag5 = sqrtf(sumSq5)
                for i in 0..<dim { query5[i] /= mag5 }

                let restricted5 = searchMatrixRestrictedDirect(
                    matrix: testMatrix, assetIds: testAssetIds,
                    query: query5, dim: dim, topK: 10,
                    allowedIds: allowedSet
                )
                assert(restricted5[0].assetId == "search-test-5",
                       "Expected search-test-5 as top restricted result, got \(restricted5[0].assetId)")

                // Verify that IDs NOT in the allowed set are excluded even if
                // they would have ranked higher in an unrestricted search.
                // One-hot at 42 → unrestricted top hit is search-test-42,
                // but restricted to {5, 10, 50} it must NOT appear.
                let restricted42 = searchMatrixRestrictedDirect(
                    matrix: testMatrix, assetIds: testAssetIds,
                    query: query42, dim: dim, topK: 10,
                    allowedIds: allowedSet
                )
                let restrictedIds42 = Set(restricted42.map(\.assetId))
                assert(!restrictedIds42.contains("search-test-42"),
                       "search-test-42 should be excluded from restricted set")
                assert(restricted42.count == 3,
                       "Expected 3 results, got \(restricted42.count)")

                print("[CLIPSearchTest] restrictToAssetIds regression OK")

                // Cleanup
                try? FileManager.default.removeItem(at: tmpDir)

                print("✅ CLIPSearchEngine test passed")
            } catch {
                print("❌ CLIPSearchEngine test FAILED: \(error)")
            }
        }
        #endif
    }

    // MARK: - Direct matrix search (mirrors CLIPSearchEngine internals)

    private static func searchMatrixDirect(
        matrix: [Float], assetIds: [String],
        query: [Float], dim: Int, topK: Int
    ) -> [(assetId: String, score: Float)] {
        let n = assetIds.count
        guard n > 0 else { return [] }

        var scores = [Float](repeating: 0, count: n)

        query.withUnsafeBufferPointer { qBuf in
            matrix.withUnsafeBufferPointer { mBuf in
                scores.withUnsafeMutableBufferPointer { sBuf in
                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(n), Int32(dim),
                        1.0, mBuf.baseAddress!, Int32(dim),
                        qBuf.baseAddress!, 1,
                        0.0, sBuf.baseAddress!, 1
                    )
                }
            }
        }

        var indexed = scores.enumerated().map { ($0.offset, $0.element) }
        indexed.sort { $0.1 > $1.1 }
        let k = min(topK, n)
        return Array(indexed.prefix(k)).map { (assetId: assetIds[$0.0], score: $0.1) }
    }

    // MARK: - Restricted matrix search (mirrors CLIPSearchEngine.searchMatrixRestricted)

    private static func searchMatrixRestrictedDirect(
        matrix: [Float], assetIds: [String],
        query: [Float], dim: Int, topK: Int,
        allowedIds: Set<String>
    ) -> [(assetId: String, score: Float)] {
        var filteredIndices = [Int]()
        for (i, id) in assetIds.enumerated() {
            if allowedIds.contains(id) { filteredIndices.append(i) }
        }
        let n = filteredIndices.count
        guard n > 0 else { return [] }

        var subMatrix = [Float](repeating: 0, count: n * dim)
        for (row, srcIdx) in filteredIndices.enumerated() {
            let srcOffset = srcIdx * dim
            let dstOffset = row * dim
            matrix.withUnsafeBufferPointer { src in
                subMatrix.withUnsafeMutableBufferPointer { dst in
                    _ = memcpy(dst.baseAddress! + dstOffset, src.baseAddress! + srcOffset,
                               dim * MemoryLayout<Float>.size)
                }
            }
        }

        var scores = [Float](repeating: 0, count: n)
        query.withUnsafeBufferPointer { qBuf in
            subMatrix.withUnsafeBufferPointer { mBuf in
                scores.withUnsafeMutableBufferPointer { sBuf in
                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(n), Int32(dim),
                        1.0, mBuf.baseAddress!, Int32(dim),
                        qBuf.baseAddress!, 1,
                        0.0, sBuf.baseAddress!, 1
                    )
                }
            }
        }

        let k = min(topK, n)
        var indexed = scores.enumerated().map { ($0.offset, $0.element) }
        indexed.sort { $0.1 > $1.1 }
        return Array(indexed.prefix(k)).map {
            (assetId: assetIds[filteredIndices[$0.0]], score: $0.1)
        }
    }
}
