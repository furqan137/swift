import Foundation
import Accelerate
import CoreML

/// On-device semantic photo search using CLIP embeddings.
///
/// Loads all embeddings from `CLIPEmbeddingStore` into a contiguous Float
/// matrix for fast vectorized dot-product search via Accelerate.
final class CLIPSearchEngine {

    static let shared = CLIPSearchEngine()

    private let store = CLIPEmbeddingStore.shared
    private let dim = CLIPConfig.embeddingDimension

    // Cached embedding matrix (row-major: N x dim)
    private var matrix = [Float]()
    private var assetIds = [String]()
    private var cachedCount = 0
    private let lock = NSLock()

    private var textEncoder: TextEncoder?
    private var ensembler: PromptEnsembler?
    private var storeObserver: Any?

    private init() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: CLIPEmbeddingStore.didWriteNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    deinit {
        if let obs = storeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Public API

    /// Search the local CLIP index for photos matching a text query.
    /// Returns up to `topK` results sorted descending by cosine similarity.
    ///
    /// - Parameter restrictToAssetIds: When non-nil, only rank embeddings
    ///   whose asset ID is in this set. Use this for compound queries where
    ///   earlier filters (person, date, location) have already narrowed the
    ///   candidate set — avoids the top-K cap discarding relevant results.
    func search(
        query: String,
        topK: Int = 50,
        restrictToAssetIds: Set<String>? = nil
    ) async throws -> [(assetId: String, score: Float)] {
        let start = CFAbsoluteTimeGetCurrent()

        // Ensure models are loaded
        try loadModelsIfNeeded()

        // Encode query with prompt ensembling
        let queryVec = try ensembler!.encode(query: query)

        // Load / refresh the embedding cache
        await refreshCacheIfNeeded()

        // Run vectorized search
        let results = lock.withLock {
            if let restrict = restrictToAssetIds {
                searchMatrixRestricted(query: queryVec, topK: topK, allowedIds: restrict)
            } else {
                searchMatrix(query: queryVec, topK: topK)
            }
        }

        let subset = restrictToAssetIds.map { "restricted to \($0.count) candidates" } ?? "full index"
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[CLIPSearch] query=\"\(query)\" topK=\(topK) results=\(results.count) " +
              "vectors=\(assetIds.count) (\(subset)) latency=\(String(format: "%.1f", elapsed))ms")

        return results
    }

    /// Mark the cache as stale. Called when new embeddings are written.
    func invalidateCache() {
        lock.withLock {
            cachedCount = 0
        }
    }

    // MARK: - Model loading

    private func loadModelsIfNeeded() throws {
        guard textEncoder == nil else { return }
        guard let baseURL = Bundle.main.resourceURL else {
            throw NSError(
                domain: "CLIPSearchEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Bundle resource URL is nil"]
            )
        }
        let encoder = try TextEncoder(resourcesAt: baseURL)
        textEncoder = encoder
        ensembler = PromptEnsembler(textEncoder: encoder)
    }

    // MARK: - Cache management

    private func refreshCacheIfNeeded() async {
        let currentStoreCount = store.count()

        let needsRefresh = lock.withLock {
            currentStoreCount != cachedCount
        }

        guard needsRefresh else { return }

        let rows = await store.fetchAll()

        lock.withLock {
            assetIds = rows.map(\.assetId)
            matrix = [Float](repeating: 0, count: rows.count * dim)
            for (i, row) in rows.enumerated() {
                let offset = i * dim
                let count = min(row.embedding.count, dim)
                row.embedding.withUnsafeBufferPointer { src in
                    matrix.withUnsafeMutableBufferPointer { dst in
                        _ = memcpy(dst.baseAddress! + offset, src.baseAddress!, count * MemoryLayout<Float>.size)
                    }
                }
            }
            cachedCount = currentStoreCount
        }
    }

    // MARK: - Vectorized search

    /// Compute dot products of `query` against all rows in the matrix,
    /// then return the top-K results.
    ///
    /// Since both query and stored embeddings are L2-normalized,
    /// dot product == cosine similarity.
    private func searchMatrix(query: [Float], topK: Int) -> [(assetId: String, score: Float)] {
        let n = assetIds.count
        guard n > 0 else { return [] }

        var scores = [Float](repeating: 0, count: n)

        // vDSP_mmul: scores = matrix(n×dim) × query(dim×1)
        // Equivalent to the dot product of each row with the query vector.
        query.withUnsafeBufferPointer { qBuf in
            matrix.withUnsafeBufferPointer { mBuf in
                scores.withUnsafeMutableBufferPointer { sBuf in
                    vDSP_mmul(
                        mBuf.baseAddress!, 1,   // A: matrix (n × dim)
                        qBuf.baseAddress!, 1,   // B: query  (dim × 1)
                        sBuf.baseAddress!, 1,   // C: scores (n × 1)
                        vDSP_Length(n),          // M: rows of A
                        1,                      // N: cols of B
                        vDSP_Length(dim)         // K: cols of A / rows of B
                    )
                }
            }
        }

        // Partial sort: find top-K indices
        let k = min(topK, n)
        var indexed = scores.enumerated().map { ($0.offset, $0.element) }

        // Use partial sort via nth_element approach:
        // For typical topK (50) vs N (50k+), this is faster than full sort.
        indexed.sort { $0.1 > $1.1 }

        return Array(indexed.prefix(k)).map { (assetId: assetIds[$0.0], score: $0.1) }
    }

    /// Restricted variant: only compute dot products for rows whose asset ID
    /// is in `allowedIds`. Builds a smaller sub-matrix on the fly so cblas
    /// operates on just the candidate set.
    private func searchMatrixRestricted(
        query: [Float], topK: Int, allowedIds: Set<String>
    ) -> [(assetId: String, score: Float)] {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif

        // Collect indices that pass the filter
        var filteredIndices = [Int]()
        filteredIndices.reserveCapacity(allowedIds.count)
        for (i, id) in assetIds.enumerated() {
            if allowedIds.contains(id) { filteredIndices.append(i) }
        }
        let n = filteredIndices.count
        guard n > 0 else { return [] }

        // Build contiguous sub-matrix (n × dim)
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

        #if DEBUG
        let t1 = CFAbsoluteTimeGetCurrent()
        #endif

        // vDSP_mmul on the sub-matrix
        var scores = [Float](repeating: 0, count: n)
        query.withUnsafeBufferPointer { qBuf in
            subMatrix.withUnsafeBufferPointer { mBuf in
                scores.withUnsafeMutableBufferPointer { sBuf in
                    vDSP_mmul(
                        mBuf.baseAddress!, 1,
                        qBuf.baseAddress!, 1,
                        sBuf.baseAddress!, 1,
                        vDSP_Length(n), 1, vDSP_Length(dim)
                    )
                }
            }
        }

        #if DEBUG
        let t2 = CFAbsoluteTimeGetCurrent()
        #endif

        let k = min(topK, n)
        var indexed = scores.enumerated().map { ($0.offset, $0.element) }
        indexed.sort { $0.1 > $1.1 }

        let result = Array(indexed.prefix(k)).map {
            (assetId: assetIds[filteredIndices[$0.0]], score: $0.1)
        }

        #if DEBUG
        let t3 = CFAbsoluteTimeGetCurrent()
        let buildMs = (t1 - t0) * 1000
        let gemvMs = (t2 - t1) * 1000
        let totalMs = (t3 - t0) * 1000
        print("[CLIPSearch:restricted] candidates=\(n)/\(assetIds.count) " +
              "submatrix=\(String(format: "%.2f", buildMs))ms " +
              "sgemv=\(String(format: "%.2f", gemvMs))ms " +
              "total=\(String(format: "%.2f", totalMs))ms")
        #endif

        return result
    }
}
