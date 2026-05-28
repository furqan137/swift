import Foundation
import Photos

struct DeletionService {
    private static let chunkSize = 200

    static func deleteAssets(_ ids: [String]) -> AsyncStream<DeleteProgress> {
        AsyncStream { continuation in
            Task {
                let chunks = stride(from: 0, to: ids.count, by: chunkSize).map { start in
                    Array(ids[start..<min(start + chunkSize, ids.count)])
                }

                var progress = DeleteProgress(
                    totalToDelete: ids.count,
                    totalChunks: chunks.count
                )
                continuation.yield(progress)

                for (index, chunk) in chunks.enumerated() {
                    progress.currentChunk = index + 1

                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: nil)
                    guard fetchResult.count > 0 else {
                        progress.failed += chunk.count
                        continuation.yield(progress)
                        continue
                    }

                    // Single-retry on transient errors. iCloud Photos sync
                    // hiccups (network blips, just-unlocked device, brief
                    // permission-prompt overlap) routinely fail the first
                    // call and succeed the second. We retry exactly once
                    // after a 500ms backoff. If the second attempt fails,
                    // mark the chunk failed — don't loop forever and don't
                    // hide a real authorization error from the user.
                    var deleted = false
                    for attempt in 0..<2 {
                        do {
                            try await PHPhotoLibrary.shared().performChanges {
                                PHAssetChangeRequest.deleteAssets(fetchResult)
                            }
                            deleted = true
                            break
                        } catch {
                            if attempt == 0 {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                        }
                    }
                    if deleted {
                        progress.deleted += fetchResult.count
                    } else {
                        // Use `fetchResult.count`, NOT `chunk.count`.
                        // Ids in the requested chunk that PhotoKit couldn't
                        // resolve (already-deleted, invalid, or not present
                        // in the current library) were never candidates for
                        // this delete call — they aren't failures, they
                        // simply weren't attempted. Counting them as
                        // failed inflates the failure metric.
                        progress.failed += fetchResult.count
                    }
                    continuation.yield(progress)
                }

                continuation.finish()
            }
        }
    }
}
