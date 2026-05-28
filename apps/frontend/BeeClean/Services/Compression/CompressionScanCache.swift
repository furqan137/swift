import Foundation

// MARK: - Scan Cache
//
// The expensive part of a camera-roll scan is the per-asset PHAssetResource
// round-trip (each one is a synchronous Core Data fetch). For a 20k-asset
// library that's ~8–15 seconds even at 32-way concurrency — unacceptable if
// the user has to wait for it every time they open the Compress tab.
//
// ScanCache persists the scan output to Application Support as JSON. On the
// next app launch / tab switch:
//   1. Load the JSON (async, ~50ms for 20k entries)
//   2. Batch-fetch live PHAssets for the cached IDs in a single call —
//      `PHAsset.fetchAssets(withLocalIdentifiers:)` is one DB round-trip,
//      not N.
//   3. Publish the hydrated array instantly.
//   4. Kick off an *incremental* scan in the background: find PHAsset IDs
//      in the current library that aren't in the cache, process only those,
//      append them, and re-save.
//
// This turns every visit after the first into a sub-100ms experience — the
// grid is already there when the tab transition completes.
final class ScanCache {
    static let shared = ScanCache()
    private init() {}

    private let photosFilename = "scan_cache_photos_v1.json"
    private let videosFilename = "scan_cache_videos_v1.json"

    /// Application Support is the right location for app-private persisted
    /// state that shouldn't be visible in Files.app and shouldn't be purged
    /// by iOS under storage pressure without a clear signal.
    private var cacheDirectory: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("BeeClean", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func photoFileURL() -> URL? {
        cacheDirectory?.appendingPathComponent(photosFilename)
    }

    private func videoFileURL() -> URL? {
        cacheDirectory?.appendingPathComponent(videosFilename)
    }

    // MARK: Load

    /// Decoded cached photo snapshots. Returns an empty array on miss so
    /// callers don't have to nil-check — a fresh install just does a full
    /// scan on first open.
    func loadPhotoSnapshots() async -> [CachedPhotoSnapshot] {
        let fileURL = photoFileURL()
        return await Task.detached(priority: .userInitiated) { () -> [CachedPhotoSnapshot] in
            guard let url = fileURL,
                  let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([CachedPhotoSnapshot].self, from: data)) ?? []
        }.value
    }

    func loadVideoSnapshots() async -> [CachedVideoSnapshot] {
        let fileURL = videoFileURL()
        return await Task.detached(priority: .userInitiated) { () -> [CachedVideoSnapshot] in
            guard let url = fileURL,
                  let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([CachedVideoSnapshot].self, from: data)) ?? []
        }.value
    }

    // MARK: Save

    /// Atomic save via a temp-file rename so a crash mid-write can't leave
    /// a half-written cache on disk.
    func savePhotoSnapshots(_ snapshots: [CachedPhotoSnapshot]) async {
        let url = photoFileURL()
        await Task.detached(priority: .utility) {
            guard let url = url,
                  let data = try? JSONEncoder().encode(snapshots) else { return }
            let tmp = url.appendingPathExtension("tmp")
            try? data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        }.value
    }

    func saveVideoSnapshots(_ snapshots: [CachedVideoSnapshot]) async {
        let url = videoFileURL()
        await Task.detached(priority: .utility) {
            guard let url = url,
                  let data = try? JSONEncoder().encode(snapshots) else { return }
            let tmp = url.appendingPathExtension("tmp")
            try? data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        }.value
    }

    // MARK: Clear (diagnostic / debug)

    func clear() {
        if let url = photoFileURL() { try? FileManager.default.removeItem(at: url) }
        if let url = videoFileURL() { try? FileManager.default.removeItem(at: url) }
    }
}
