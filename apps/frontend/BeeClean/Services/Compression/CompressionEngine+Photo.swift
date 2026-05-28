import Foundation
import Photos
import ImageIO
import CoreServices
import UniformTypeIdentifiers
import UIKit

// MARK: - CompressionEngine: Photo Library Save
extension CompressionEngine {

    // MARK: - Save to Photo Library
    func saveToPhotoLibrary(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Save Photo to Photo Library
    func savePhotoToPhotoLibrary(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

}

// MARK: - CompressionEngine: Photo Compression
extension CompressionEngine {

    // MARK: - Photo Compression
    /// Whether the device can encode HEIC. Cached on first access.
    ///
    /// Marked `nonisolated` because the photo encode pipeline runs on a detached
    /// task (off MainActor) and reads this during format selection. It's a let
    /// computed once at first access — safe for concurrent reads without locks.
    nonisolated private static let supportsHEIC: Bool = {
        let identifiers = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return identifiers.contains("public.heic")
    }()

    /// Loads the full-resolution image data + UTI for a PHAsset.
    private func loadPhotoData(from asset: PHAsset) async throws -> (data: Data, uti: String?) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // PHImageManager may deliver the callback more than once (progress +
        // final) depending on `deliveryMode`. A plain `Bool` flag here is a
        // latent "resume called twice" crash — Swift traps on a second
        // continuation.resume. Guard with an NSLock so the compare-and-set
        // is actually atomic across whatever queue the daemon uses.
        let lock = NSLock()
        var didResume = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                lock.lock()
                if didResume {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()

                if let data = data {
                    continuation.resume(returning: (data, uti))
                } else {
                    let err = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "Could not load image data"
                    continuation.resume(throwing: CompressionError.exportFailed(err))
                }
            }
        }
    }

    /// Result bundle returned from the off-main photo encode helper.
    private struct PhotoEncodeOutput {
        let outputURL: URL
        let compressedSize: Int64
        let codecName: String
        let resolutionLabel: String
    }

    /// Compresses a still photo from a PHAsset using HEIC (or JPEG fallback).
    /// Mirrors the video compression API: same @Published progress/phase/result/error.
    ///
    /// Fast path: the CGImageSource/CGImageDestination calls are synchronous and
    /// can easily take 500ms–1.5s for a 48MP iPhone photo. Previously this ran on
    /// the main thread (because the engine is @MainActor), blocking the UI and
    /// making the progress bar jump in lurches. We now hop into a nonisolated
    /// async helper so the CPU work runs on the cooperative pool and only the
    /// @Published state updates come back to main.
    func compressPhoto(phAsset: PHAsset, level: CompressionLevel) async {
        reset()
        currentAssetId = phAsset.localIdentifier
        currentLevel = level
        isCompressing = true
        phase = .exporting
        progress = 0.02

        let startTime = Date()

        do {
            // ── Step 1: Load encoded image bytes (async via PhotoKit) ──
            let (imageData, _) = try await loadPhotoData(from: phAsset)
            let originalSize = Int64(imageData.count)
            guard originalSize > 0 else {
                throw CompressionError.readingFailed("Photo file is empty (0 bytes).")
            }

            guard !shared.isCancelled else { isCompressing = false; phase = .cancelled; return }

            phase = .analyzing
            progress = 0.15

            // ── Steps 2–5: All CG work runs OFF the main thread ──
            let output = try await encodePhotoDetached(
                imageData: imageData,
                level: level,
                fallbackPixelWidth: phAsset.pixelWidth,
                fallbackPixelHeight: phAsset.pixelHeight
            )

            let compressionTime = Date().timeIntervalSince(startTime)

            phase = .done
            progress = 1.0

            result = CompressionResult(
                outputURL: output.outputURL,
                originalSize: originalSize,
                compressedSize: output.compressedSize,
                compressionTime: compressionTime,
                codec: output.codecName,
                outputResolution: output.resolutionLabel
            )

            isCompressing = false

            recordCompressionAttempt(
                success: true,
                codec: output.codecName,
                originalBytes: originalSize,
                compressedBytes: output.compressedSize,
                compressionTimeSeconds: compressionTime,
                resolution: output.resolutionLabel
            )

        } catch let err as CompressionError {
            if case .cancelled = err {
                phase = .cancelled
            } else {
                phase = .failed
                error = err
            }
            isCompressing = false
            recordCompressionAttempt(
                success: false,
                codec: Self.supportsHEIC ? "HEIC" : "JPEG",
                errorMessage: err.localizedDescription
            )
        } catch {
            phase = .failed
            self.error = .writingFailed(error.localizedDescription)
            isCompressing = false
            recordCompressionAttempt(
                success: false,
                codec: Self.supportsHEIC ? "HEIC" : "JPEG",
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Runs the CGImageSource → CGImageDestination pipeline on the cooperative
    /// thread pool. Marked `nonisolated` so the @MainActor class isolation
    /// doesn't drag this synchronous CPU work back onto the UI thread.
    ///
    /// State ownership:
    ///   • Reads `self.shared` (thread-safe Sendable lock box) for cancellation.
    ///   • Writes @Published state (`phase`, `progress`) only through MainActor.run.
    ///   • Returns a fully-formed result so the caller can publish it atomically.
    private nonisolated func encodePhotoDetached(
        imageData: Data,
        level: CompressionLevel,
        fallbackPixelWidth: Int,
        fallbackPixelHeight: Int
    ) async throws -> PhotoEncodeOutput {
        // Hop off main — Swift doesn't guarantee this for a nonisolated async
        // func called from MainActor, so we explicitly yield into a detached
        // task with an elevated QoS (user is staring at a progress bar).
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [shared] in
                // ── Build source (no decode yet, no full-res cache) ──
                let sourceOpts: [CFString: Any] = [
                    kCGImageSourceShouldCache: false
                ]
                guard let source = CGImageSourceCreateWithData(
                    imageData as CFData,
                    sourceOpts as CFDictionary
                ) else {
                    throw CompressionError.readingFailed("Failed to read image data.")
                }

                let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let pixelW = (sourceProps?[kCGImagePropertyPixelWidth] as? Int) ?? fallbackPixelWidth
                let pixelH = (sourceProps?[kCGImagePropertyPixelHeight] as? Int) ?? fallbackPixelHeight
                let orientation = sourceProps?[kCGImagePropertyOrientation] as? UInt32

                guard pixelW > 0, pixelH > 0 else {
                    throw CompressionError.readingFailed("Photo has invalid dimensions.")
                }

                if shared.isCancelled { throw CompressionError.cancelled }
                await MainActor.run { [weak self] in
                    self?.phase = .preparing
                    self?.progress = 0.30
                }

                // ── Decode (with subsample + thumbnail fast path) ──
                let longest = max(pixelW, pixelH)
                let maxDim = Int(level.maxPhotoDimension)

                let cgImage: CGImage = try {
                    if longest > maxDim {
                        // ImageIO can decode at an intermediate pixel size in a
                        // single pass when we ask for a thumbnail. This is ~2–4x
                        // faster than "decode full, then downscale" on modern
                        // iPhones — the hardware JPEG/HEIC decoder supports it
                        // directly via kCGImageSourceThumbnailMaxPixelSize.
                        let opts: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            // Orientation is reapplied in destProps so the decoded
                            // pixels stay in native coords (skip extra rotate pass).
                            kCGImageSourceCreateThumbnailWithTransform: false,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxDim
                        ]
                        guard let thumb = CGImageSourceCreateThumbnailAtIndex(
                            source, 0, opts as CFDictionary
                        ) else {
                            throw CompressionError.readingFailed("Failed to downscale image.")
                        }
                        return thumb
                    } else {
                        let decodeOpts: [CFString: Any] = [
                            kCGImageSourceShouldCacheImmediately: true
                        ]
                        guard let full = CGImageSourceCreateImageAtIndex(
                            source, 0, decodeOpts as CFDictionary
                        ) else {
                            throw CompressionError.readingFailed("Failed to decode image.")
                        }
                        return full
                    }
                }()

                // Guard against silent corruption: ImageIO can hand back a
                // CGImage with zero dimensions for partially-corrupted HEICs,
                // which would otherwise encode to a 0-byte output without error.
                guard cgImage.width > 0, cgImage.height > 0 else {
                    throw CompressionError.readingFailed(
                        "Decoded image has zero dimensions — file may be corrupted."
                    )
                }

                if shared.isCancelled { throw CompressionError.cancelled }
                await MainActor.run { [weak self] in
                    self?.phase = .compressing
                    self?.progress = 0.65
                }

                // ── Pick output format ──
                let useHEIC = CompressionEngine.supportsHEIC
                let outputUTType: CFString = useHEIC
                    ? ("public.heic" as CFString)
                    : (UTType.jpeg.identifier as CFString)
                let outputExt = useHEIC ? "heic" : "jpg"
                let codecName = useHEIC ? "HEIC" : "JPEG"

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("compressed_\(UUID().uuidString).\(outputExt)")
                try? FileManager.default.removeItem(at: outputURL)

                // ── Encode ──
                guard let dest = CGImageDestinationCreateWithURL(
                    outputURL as CFURL, outputUTType, 1, nil
                ) else {
                    throw CompressionError.writerSetupFailed("Failed to create image destination.")
                }

                var destProps: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: level.photoQuality
                ]
                if let orientation = orientation {
                    destProps[kCGImagePropertyOrientation] = orientation
                }
                if let profile = sourceProps?[kCGImagePropertyProfileName] {
                    destProps[kCGImagePropertyProfileName] = profile
                }

                CGImageDestinationAddImage(dest, cgImage, destProps as CFDictionary)

                await MainActor.run { [weak self] in
                    self?.phase = .finishing
                    self?.progress = 0.90
                }

                guard CGImageDestinationFinalize(dest) else {
                    throw CompressionError.writingFailed("Failed to finalize encoded photo.")
                }

                let compressedSize = (try? FileManager.default.attributesOfItem(
                    atPath: outputURL.path
                )[.size] as? Int64) ?? 0

                let outW = cgImage.width
                let outH = cgImage.height
                let resolutionLabel: String = {
                    let mp = Double(outW * outH) / 1_000_000.0
                    if mp >= 1.0 {
                        return String(format: "%.1fMP", mp)
                    } else {
                        return "\(outW)×\(outH)"
                    }
                }()

                return PhotoEncodeOutput(
                    outputURL: outputURL,
                    compressedSize: compressedSize,
                    codecName: codecName,
                    resolutionLabel: resolutionLabel
                )
            }.value
        } onCancel: {
            shared.isCancelled = true
        }
    }
    
}
