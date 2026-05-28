import Foundation

/// Routes FIND_BY_CONTENT queries through the local CLIP engine with an
/// on-device Vision ML fallback.
///
/// Cascade: Local CLIP → Vision ML (fully on-device).
///
/// Returns `[String]` (asset IDs) — the same shape as all other search
/// paths, so downstream UI (AIResultsGridView, compound intersection) is
/// unaffected.
enum SearchRouter {

    /// Search for photos matching a text query.
    /// Returns asset IDs sorted by relevance (best first).
    ///
    /// This is the single entry point for all FIND_BY_CONTENT routing.
    /// The `visionMLFallback` closure provides on-device Vision ML search
    /// when local CLIP has no index or fails.
    ///
    /// - Parameter restrictToAssetIds: When non-nil, only rank embeddings
    ///   for these asset IDs. Use this in compound queries where person/date/
    ///   location filters have already narrowed the candidate set, so the
    ///   top-K cap doesn't silently discard relevant results.
    static func searchByContent(
        query: String,
        limit: Int,
        restrictToAssetIds: Set<String>? = nil,
        visionMLFallback: () async -> [String]
    ) async -> [String] {
        // Check if we have any local embeddings
        let indexedCount = CLIPEmbeddingStore.shared.count()
        guard indexedCount > 0 else {
            print("[SearchRouter] Local index empty (\(indexedCount) embeddings) → Vision ML fallback")
            return await visionMLFallback()
        }

        do {
            let results = try await CLIPSearchEngine.shared.search(
                query: query,
                topK: limit,
                restrictToAssetIds: restrictToAssetIds
            )
            let ids = results.map(\.assetId)
            print("[SearchRouter] Local CLIP → \(ids.count) results from \(indexedCount) indexed photos")
            return ids
        } catch {
            print("[SearchRouter] Local CLIP failed: \(error) → Vision ML fallback")
            return await visionMLFallback()
        }
    }
}
