import Foundation
@preconcurrency import AVFoundation
import Photos
import VideoToolbox
import UIKit

// MARK: - CompressionEngine: Video Pipeline
extension CompressionEngine {

    // MARK: - Export PHAsset to local URL
    func exportPHAsset(_ phAsset: PHAsset) async throws -> URL {
        // Move off main thread — PHAssetResource.assetResources triggers a
        // synchronous Core Data fetch that can block and cause watchdog kills.
        let resources = await Task.detached {
            PHAssetResource.assetResources(for: phAsset)
        }.value
        guard !resources.isEmpty else {
            throw CompressionError.exportFailed("No resources available for this video.")
        }
        // Prefer fullSizeVideo (edited) → video (original), matching the
        // scan's resource preference. Fall back to any resource only as a
        // last resort — avoids exporting a thumbnail or adjustment sidecar.
        guard let videoResource = resources.first(where: {
            $0.type == .fullSizeVideo
        }) ?? resources.first(where: {
            $0.type == .video
        }) ?? resources.first else {
            throw CompressionError.exportFailed("No video resource found.")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = videoResource.originalFilename
        let exportURL = tempDir.appendingPathComponent("export_\(UUID().uuidString)_\(fileName)")
        try? FileManager.default.removeItem(at: exportURL)
        
        let manager = PHAssetResourceManager.default()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        
        return try await withCheckedThrowingContinuation { continuation in
            manager.writeData(for: videoResource, toFile: exportURL, options: options) { error in
                if let error = error {
                    continuation.resume(throwing: CompressionError.exportFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: exportURL)
                }
            }
        }
    }
    
    // MARK: - Compress Video (PHAsset)
    func compressVideo(phAsset: PHAsset, level: CompressionLevel) async {
        reset()
        currentAssetId = phAsset.localIdentifier
        currentLevel = level
        isCompressing = true
        phase = .exporting

        do {
            let inputURL = try await exportPHAsset(phAsset)

            guard !shared.isCancelled else {
                cleanup(inputURL); isCompressing = false; phase = .cancelled; return
            }

            await compressVideo(inputURL: inputURL, level: level)

        } catch let err as CompressionError {
            phase = .failed
            error = err
            isCompressing = false
        } catch {
            phase = .failed
            self.error = .exportFailed(error.localizedDescription)
            isCompressing = false
        }
    }

    // MARK: - Video pass-through (HEVC fast path)
    /// Copies the source file bit-for-bit into the temp compressed-output
    /// slot and publishes a synthetic `CompressionResult`. Used when the
    /// source is already optimally encoded — see the gate in `compressVideo`.
    ///
    /// The copy happens on a background task so the @MainActor engine
    /// doesn't stall on APFS I/O for large files. Progress jumps through
    /// the standard phases so the UI animation still feels like a real
    /// compression (just much faster).
    func runVideoPassThrough(
        inputURL: URL,
        originalSize: Int64,
        durationSeconds: Double,
        resolutionLabel: String,
        startTime: Date
    ) async throws {
        phase = .preparing
        progress = 0.30

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        phase = .compressing
        progress = 0.55

        // APFS uses copy-on-write clones for same-volume copies, so this
        // is near-instant even for multi-GB files. Still hop off main so
        // hilariously large files don't jank the UI.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
        }.value

        phase = .finishing
        progress = 0.95

        let copiedSize = fileSize(at: outputURL)
        let compressionTime = Date().timeIntervalSince(startTime)

        phase = .done
        progress = 1.0

        result = CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: copiedSize,
            compressionTime: compressionTime,
            codec: "HEVC ✓",
            outputResolution: resolutionLabel
        )
        isCompressing = false

        recordCompressionAttempt(
            success: true,
            codec: "HEVC-passthrough",
            originalBytes: originalSize,
            compressedBytes: copiedSize,
            durationSeconds: durationSeconds,
            compressionTimeSeconds: compressionTime,
            resolution: resolutionLabel
        )
    }

}
