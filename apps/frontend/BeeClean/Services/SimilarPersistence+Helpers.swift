import Foundation
import Photos

extension SimilarPersistence {
    // MARK: - Helpers

    /// Checks which asset IDs still exist in the photo library.
    /// `PHAsset.fetchAssets` is synchronous and can take hundreds of ms on
    /// large libraries — every caller wraps this in their own
    /// `Task.detached(priority: .background)` so the work already runs off
    /// the main thread. Keeping this synchronous eliminates the redundant
    /// inner Task hop AND the "async call in a function that does not
    /// support concurrency" warning that Swift's strict concurrency
    /// checker fires when this is called from a detached closure.
    static func existingAssetIds(_ ids: [String]) -> Set<String> {
        let unique = Array(Set(ids))
        let result = PHAsset.fetchAssets(withLocalIdentifiers: unique, options: nil)
        var existing = Set<String>()
        result.enumerateObjects { asset, _, _ in
            existing.insert(asset.localIdentifier)
        }
        return existing
    }
}

