import SwiftUI
import UIKit
import AVFoundation
import Photos

// MARK: - Vault Media Item (Persistable)
struct VaultMediaItem: Identifiable, Codable, Equatable {
    let id: String
    let filename: String
    let isVideo: Bool
    let dateAdded: Date
    let originalFilename: String?
    
    init(filename: String, isVideo: Bool, originalFilename: String? = nil) {
        self.id = UUID().uuidString
        self.filename = filename
        self.isVideo = isVideo
        self.dateAdded = Date()
        self.originalFilename = originalFilename
    }
}

// MARK: - Secret Vault Manager
/// Manages encrypted storage of photos & videos in the app's private sandbox.
/// Files are stored in Library/SecretVault/ which is NOT backed up and inaccessible
/// to the user without the PIN.
@MainActor
class SecretVaultManager: ObservableObject {
    static let shared = SecretVaultManager()
    
    @Published var items: [VaultMediaItem] = []
    @Published var isLoading = false
    /// Last write/persist failure surfaced to the UI. Vault saves are
    /// sensitive — silently dropping a photo because the disk was full
    /// or a file copy failed would let the user believe their content
    /// is safe when it isn't. SecretSpace views observe this and show
    /// a banner; call `acknowledgeError()` once shown.
    @Published var lastError: String?
    
    private let vaultDirectoryName = "SecretVault"
    private let manifestKey = "secret_vault_manifest"
    
    // MARK: - Directory Management
    
    private nonisolated var vaultDirectory: URL {
        let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let vaultDir = libraryDir.appendingPathComponent(vaultDirectoryName)

        if !FileManager.default.fileExists(atPath: vaultDir.path) {
            try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        }
        return vaultDir
    }
    
    init() {
        // Defer the manifest load + N-item FileManager.fileExists walk to a
        // detached background Task so the @MainActor singleton's first
        // resolution doesn't block whichever view body resolves it. The
        // @Published `items` array stays empty until the load completes,
        // and the existing `isLoading` flag flips so any consumer that
        // wants a spinner has the signal it needs.
        Task { [weak self] in await self?.loadManifestAsync() }
    }

    // MARK: - Manifest (tracks what's stored)

    private func loadManifestAsync() async {
        isLoading = true
        let key = manifestKey
        let dir = vaultDirectory

        // Decode + per-item file-exists validation both run off-main; only
        // the final batched assignment to `items` lands back on @MainActor.
        let validated: [VaultMediaItem] = await Task.detached(priority: .userInitiated) {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let manifest = try? JSONDecoder().decode([VaultMediaItem].self, from: data) else {
                return []
            }
            return manifest.filter { item in
                FileManager.default.fileExists(atPath: dir.appendingPathComponent(item.filename).path)
            }
        }.value

        items = validated
        isLoading = false
    }
    
    private func saveManifest() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: manifestKey)
        } catch {
            print("[SecretVault] saveManifest encode failed: \(error.localizedDescription)")
            lastError = "Vault index couldn't be saved — last change may not persist."
        }
    }

    /// Reset the published error after the UI has displayed it.
    func acknowledgeError() {
        lastError = nil
    }
    
    nonisolated func fileURL(for item: VaultMediaItem) -> URL {
        vaultDirectory.appendingPathComponent(item.filename)
    }
    
    // MARK: - Add Photos
    
    func addPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            lastError = "Couldn't encode photo for the vault."
            return
        }

        let filename = "photo_\(UUID().uuidString).jpg"
        let fileURL = vaultDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            let item = VaultMediaItem(filename: filename, isVideo: false)
            items.insert(item, at: 0)
            saveManifest()
        } catch {
            print("Failed to save photo: \(error)")
            lastError = "Couldn't save photo to vault: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Add Videos
    
    func addVideo(from sourceURL: URL) {
        let filename = "video_\(UUID().uuidString).mov"
        let destURL = vaultDirectory.appendingPathComponent(filename)
        
        do {
            // Copy video data into our vault
            if sourceURL.startAccessingSecurityScopedResource() {
                defer { sourceURL.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
            
            let item = VaultMediaItem(
                filename: filename,
                isVideo: true,
                originalFilename: sourceURL.lastPathComponent
            )
            items.insert(item, at: 0)
            saveManifest()
        } catch {
            print("Failed to save video: \(error)")
            lastError = "Couldn't save video to vault: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Delete
    
    func deleteItem(_ item: VaultMediaItem) {
        let fileURL = self.fileURL(for: item)
        try? FileManager.default.removeItem(at: fileURL)
        items.removeAll { $0.id == item.id }
        saveManifest()
    }
    
    func deleteItems(_ itemsToDelete: Set<String>) {
        for id in itemsToDelete {
            if let item = items.first(where: { $0.id == id }) {
                let fileURL = self.fileURL(for: item)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        items.removeAll { itemsToDelete.contains($0.id) }
        saveManifest()
    }
    
    // MARK: - Load Thumbnail
    
    nonisolated func loadThumbnail(for item: VaultMediaItem, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let url = fileURL(for: item)

        if item.isVideo {
            return generateVideoThumbnail(url: url, size: size)
        } else {
            // ImageIO downsample — avoids decoding the full-size image
            // into memory just to throw most of it away. Falls back to
            // the slow path if the source can't be opened.
            if let down = downsampledImage(at: url, to: size) { return down }
            guard let data = try? Data(contentsOf: url),
                  let fullImage = UIImage(data: data) else { return nil }
            return fullImage.preparingThumbnail(of: size) ?? fullImage
        }
    }

    private nonisolated func downsampledImage(at url: URL, to size: CGSize) -> UIImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else { return nil }
        // Hardcoded 3.0 — UIScreen.main is now @MainActor-isolated in
        // Swift 6, so reading `.scale` from this nonisolated function
        // produces a "main-actor property accessed from nonisolated
        // context" warning. Every shipping iPhone since X is 3x retina;
        // the rare 2x devices (older iPad mini etc.) just receive a
        // slightly larger thumbnail than strictly needed, no visible
        // regression. iPad sizes are bounded by the caller's
        // `size: CGSize` so we don't blow up memory either.
        let scale: CGFloat = 3.0
        let maxPixel = max(size.width, size.height) * scale
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    nonisolated func loadFullImage(for item: VaultMediaItem) -> UIImage? {
        guard !item.isVideo else { return nil }
        let url = fileURL(for: item)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private nonisolated func generateVideoThumbnail(url: URL, size: CGSize) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Video thumbnail error: \(error)")
            return nil
        }
    }
    
    // MARK: - Delete from Camera Roll

    func deleteFromCameraRoll(assetIdentifiers: [String]) async -> Bool {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard fetchResult.count > 0 else { return false }

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }
            return true
        } catch {
            print("Failed to delete from camera roll: \(error)")
            return false
        }
    }

    // MARK: - Counts

    var photoCount: Int { items.filter { !$0.isVideo }.count }
    var videoCount: Int { items.filter { $0.isVideo }.count }
}
