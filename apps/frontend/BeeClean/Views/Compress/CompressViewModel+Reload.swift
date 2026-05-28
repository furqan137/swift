import Foundation
import Photos

// MARK: - CompressViewModel: Reload + Asset Mutations
extension CompressViewModel {

    func reloadVideos() async {
        // Explicit user-triggered reload (e.g., after PhotosPicker import).
        // Cancel any in-flight singleton scan first so the new pass isn't
        // short-circuited by `guard !isLoadingVideos`. Then wipe the disk
        // cache and run a fresh load via the same singleton-owned task so
        // a tab switch mid-reload doesn't kill it either.
        videoLoadTask?.cancel()
        videoLoadTask = nil
        isLoadingVideos = false
        hasLoadedVideos = false
        await ScanCache.shared.saveVideoSnapshots([])
        let task = Task { @MainActor [weak self] in
            await self?.loadVideos()
            self?.videoLoadTask = nil
        }
        videoLoadTask = task
        await task.value
    }

    func reloadPhotos() async {
        photoLoadTask?.cancel()
        photoLoadTask = nil
        isLoadingPhotos = false
        hasLoadedPhotos = false
        await ScanCache.shared.savePhotoSnapshots([])
        let task = Task { @MainActor [weak self] in
            await self?.loadPhotos()
            self?.photoLoadTask = nil
        }
        photoLoadTask = task
        await task.value
    }

    // MARK: - Asset removal (post-delete grid sync)
    //
    // Called by `PhotoCompressionDetailView` / `CompressionDetailView` after
    // a successful PHAsset deletion so the grid prunes the row and the
    // running totals reflect freed space immediately. Without this the
    // photo appears to "still be there" after iOS Photos has actually
    // deleted it — that's the bug users keep reporting as
    // "delete didn't work".
    //
    // The PHAsset itself is gone after this point; we also persist the
    // pruned snapshot list so the next cold-launch doesn't try to hydrate
    // a stale identifier that fails the PHFetchResult lookup.
    func removePhoto(localIdentifier: String) {
        guard let idx = photos.firstIndex(where: { $0.id == localIdentifier }) else { return }
        let removed = photos.remove(at: idx)
        photoTotalSize = max(0, photoTotalSize - removed.fileSize)
        photoPotentialSavings = max(0, photoPotentialSavings - removed.potentialSavings)
        Task { await persistPhotoSnapshotsFromCurrent() }
    }

    func removeVideo(localIdentifier: String) {
        guard let idx = videos.firstIndex(where: { $0.id == localIdentifier }) else { return }
        let removed = videos.remove(at: idx)
        videoTotalSize = max(0, videoTotalSize - removed.fileSize)
        videoPotentialSavings = max(0, videoPotentialSavings - removed.potentialSavings)
        Task { await persistVideoSnapshotsFromCurrent() }
    }

    func persistPhotoSnapshotsFromCurrent() async {
        let snapshots = photos.map(CachedPhotoSnapshot.init(from:))
        await ScanCache.shared.savePhotoSnapshots(snapshots)
    }

    func persistVideoSnapshotsFromCurrent() async {
        let snapshots = videos.map(CachedVideoSnapshot.init(from:))
        await ScanCache.shared.saveVideoSnapshots(snapshots)
    }
}

