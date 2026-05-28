import Foundation
import Photos

/// Base class for all media swipe view models (screenshots, photos, recordings).
/// Subclasses only need to provide init data and a post-delete refresh action.
@MainActor
class MediaSwipeViewModel: ObservableObject {

    // MARK: - Published State
    @Published private(set) var items: [ScreenshotAsset] = []
    @Published var markedForDeletion: Set<String> = []
    @Published var currentIndex: Int = 0
    @Published private(set) var isDeleting = false
    @Published private(set) var deleteProgress: DeleteProgress = .init()

    /// Human-readable label for this media type ("screenshots", "photos", "recordings")
    let mediaLabel: String

    /// Accent color for the review stats pill
    let accentColor: String // Color name from Color extension

    /// Called after assets are deleted to refresh upstream data
    private let onDeleted: @Sendable (Set<String>) async -> Void

    /// Optional on-device "kept" persistence namespace. When set, swipeRight
    /// (Keep) writes the asset ID to `LocalKeptStore` and any asset already
    /// present in that namespace is filtered out of `items` on init so the
    /// user never sees the same kept photo/video twice across sessions.
    private let keptNamespace: LocalKeptStore.Namespace?

    /// Leaf category for the Progress chart timeline filter. Each
    /// MediaSwipeViewModel subclass is bound to exactly one category
    /// (BlurryPhotoSwipeViewModel = `.blurredPhotos`, ScreenshotSwipeViewModel
    /// = `.screenshots`, etc), so it's passed at init and forwarded
    /// to HiveStatsManager.recordCleanup on delete. Nil only on the
    /// base class as a back-compat default — subclasses should
    /// always override.
    private let sourceCategory: SavedFindSourceCategory?

    private var swipeHistory: [SwipeAction] = []

    private struct SwipeAction {
        let index: Int
        let wasMarked: Bool
    }

    // MARK: - Init
    init(
        items: [ScreenshotAsset],
        startIndex: Int = 0,
        mediaLabel: String,
        accentColor: String = "categoryOrange",
        keptNamespace: LocalKeptStore.Namespace? = nil,
        sourceCategory: SavedFindSourceCategory? = nil,
        onDeleted: @escaping @Sendable (Set<String>) async -> Void
    ) {
        // Filter out assets the user has previously chosen to keep.
        let filtered: [ScreenshotAsset]
        if let ns = keptNamespace {
            let kept = LocalKeptStore.shared.ids(in: ns)
            filtered = kept.isEmpty ? items : items.filter { !kept.contains($0.assetId) }
        } else {
            filtered = items
        }
        self.items = filtered
        self.currentIndex = min(startIndex, max(filtered.count - 1, 0))
        self.mediaLabel = mediaLabel
        self.accentColor = accentColor
        self.keptNamespace = keptNamespace
        self.sourceCategory = sourceCategory
        self.onDeleted = onDeleted
    }

    // MARK: - Computed
    var hasMore: Bool { currentIndex < items.count }

    var currentItem: ScreenshotAsset? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var totalMarked: Int { markedForDeletion.count }

    var totalBytesMarked: Int64 {
        items
            .filter { markedForDeletion.contains($0.assetId) }
            .reduce(Int64(0)) { $0 + $1.fileSize }
    }

    var isComplete: Bool { currentIndex >= items.count }

    var canUndo: Bool { !swipeHistory.isEmpty }

    // MARK: - Actions

    func swipeLeft() {
        guard currentIndex < items.count else { return }
        let asset = items[currentIndex]
        markedForDeletion.insert(asset.assetId)
        swipeHistory.append(SwipeAction(index: currentIndex, wasMarked: true))
        currentIndex += 1
    }

    func swipeRight() {
        guard currentIndex < items.count else { return }
        let asset = items[currentIndex]
        swipeHistory.append(SwipeAction(index: currentIndex, wasMarked: false))
        if let ns = keptNamespace {
            LocalKeptStore.shared.add(asset.assetId, to: ns)
        }
        currentIndex += 1
    }

    func undoLast() {
        guard let last = swipeHistory.popLast() else { return }
        currentIndex = last.index
        guard last.index < items.count else { return }
        let asset = items[last.index]
        if last.wasMarked {
            markedForDeletion.remove(asset.assetId)
        } else if let ns = keptNamespace {
            // Undoing a Keep — roll the id back out of the on-device kept set
            // so the asset reappears next session.
            LocalKeptStore.shared.remove(asset.assetId, from: ns)
        }
    }

    func toggleMarkInReview(_ assetId: String) {
        if markedForDeletion.contains(assetId) {
            markedForDeletion.remove(assetId)
        } else {
            markedForDeletion.insert(assetId)
        }
    }

    // MARK: - Deletion

    private static let deleteChunkSize = 200

    func deleteMarked() async -> Bool {
        let ids = Array(markedForDeletion)
        guard !ids.isEmpty else { return false }

        isDeleting = true

        let chunks = stride(from: 0, to: ids.count, by: Self.deleteChunkSize).map { start in
            Array(ids[start..<min(start + Self.deleteChunkSize, ids.count)])
        }

        deleteProgress = DeleteProgress(
            totalToDelete: ids.count,
            totalChunks: chunks.count
        )

        var allDeleted: Set<String> = []

        for (index, chunk) in chunks.enumerated() {
            deleteProgress.currentChunk = index + 1

            // `PHAsset.fetchAssets(withLocalIdentifiers:)` is a sync
            // Core Data round-trip. With 5k+ asset libraries it stalls
            // the @MainActor for 200+ ms per chunk and the deletion UI
            // visibly froze between chunks. Hop the fetch into a
            // detached task so the main thread stays free; the actual
            // photo-library write below already runs on its own queue
            // inside `performChanges`.
            let fetchResult = await Task.detached(priority: .userInitiated) {
                PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: nil)
            }.value
            guard fetchResult.count > 0 else {
                deleteProgress.failed += chunk.count
                continue
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(fetchResult)
                }
                allDeleted.formUnion(chunk)
                deleteProgress.deleted += fetchResult.count
            } catch {
                deleteProgress.failed += chunk.count
            }
        }

        if !allDeleted.isEmpty {
            // Compute bytes BEFORE we drain the items array so the
            // sum is accurate.
            let bytesFreed = items
                .filter { allDeleted.contains($0.assetId) }
                .reduce(Int64(0)) { $0 + $1.fileSize }

            markedForDeletion.subtract(allDeleted)
            items.removeAll { allDeleted.contains($0.assetId) }
            await onDeleted(allDeleted)
            BeeViewModel.shared.registerCleanup(count: allDeleted.count, source: .photoDelete)
            HiveStatsManager.shared.recordCleanup(
                action: "deletion",
                itemCount: allDeleted.count,
                bytesSaved: bytesFreed,
                category: sourceCategory
            )
        }

        isDeleting = false
        return !allDeleted.isEmpty
    }
}
