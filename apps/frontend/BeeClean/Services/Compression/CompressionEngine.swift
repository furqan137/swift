import Foundation
@preconcurrency import AVFoundation
import Photos
import Combine
import VideoToolbox
import UIKit

// MARK: - Compression Engine
/// High-performance video compression using HEVC (H.265) with smart resolution scaling,
/// hardware-accelerated encoding via VideoToolbox, and intelligent bitrate targeting.
@MainActor
class CompressionEngine: ObservableObject {
    @Published var progress: Float = 0
    @Published var isCompressing = false
    @Published var phase: CompressionPhase = .idle
    @Published var result: CompressionResult?
    @Published var error: CompressionError?
    
    // Marked `internal` (default) instead of `private` so that the Photo +
    // Video extensions in the same module can read/write engine state without
    // duplicating it. Extensions can't reach `private` members across files
    // and the module-level access is what we want here.
    let shared = CompressionSharedState()
    var currentAssetId: String?
    var currentLevel: CompressionLevel = .medium
    /// Throttle main-thread progress publishes during the encode loop. Without
    /// this we'd hit ~3000 publishes for a 60-second 30fps video and visibly
    /// jank the UI. ~10 Hz is plenty for a smooth progress bar.
    var lastPublishedProgress: Float = -1
    var lastProgressPublishAt: CFTimeInterval = 0
    
    func cancel() {
        shared.isCancelled = true
        phase = .cancelled
    }

    // MARK: - Temp-file housekeeping
    //
    // Every compression pass writes `compressed_<uuid>.<ext>` files into
    // `temporaryDirectory`. The success / cancel path's `defer { remove }`
    // cleans them up — but if the app is force-killed (user from the app
    // switcher, OS under memory pressure) the defer never runs and the
    // file orphans. Over months of use these can quietly accumulate into
    // GBs of dead bytes in `/tmp` that the OS only reclaims under disk
    // pressure.
    //
    // Called from `BeeCleanApp` at launch — runs on a detached background
    // task so a slow filesystem doesn't delay the first frame.
    nonisolated static func sweepOrphanedTempFiles() {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            guard let entries = try? fm.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            let cutoff = Date().addingTimeInterval(-3600) // 1 hour
            for url in entries where url.lastPathComponent.hasPrefix("compressed_") {
                // Don't delete an in-flight encode — only sweep files
                // older than the cutoff so we never race a live writer.
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let mtime, mtime > cutoff { continue }
                try? fm.removeItem(at: url)
            }
        }
    }
    
    func reset() {
        progress = 0
        isCompressing = false
        phase = .idle
        result = nil
        error = nil
        shared.isCancelled = false
        shared.encounteredError = false
        lastPublishedProgress = -1
        lastProgressPublishAt = 0
    }

}

// MARK: - CompressionEngine: Stats Funnel
extension CompressionEngine {

    // MARK: - Stats

    /// Single funnel for every compression attempt — success or failure — so
    /// the call sites stay short and the stats schema stays consistent.
    /// Replaced 6 nearly-identical 9-line blocks scattered through the engine.
    func recordCompressionAttempt(
        success: Bool,
        codec: String,
        originalBytes: Int64 = 0,
        compressedBytes: Int64 = 0,
        durationSeconds: Double? = nil,
        compressionTimeSeconds: Double? = nil,
        resolution: String? = nil,
        errorMessage: String? = nil
    ) {
        StatsService.shared.logCompression(
            assetId: currentAssetId ?? "unknown",
            originalBytes: originalBytes,
            compressedBytes: compressedBytes,
            compressionLevel: currentLevel.rawValue,
            codec: codec,
            durationSeconds: durationSeconds,
            compressionTimeSeconds: compressionTimeSeconds,
            resolution: resolution,
            success: success,
            errorMessage: errorMessage
        )
    }
    
}

// MARK: - CompressionEngine: Encoder Capability + Math
extension CompressionEngine {

    // MARK: - Check HEVC support
    static var supportsHEVC: Bool = {
        let encoder = VTCopySupportedPropertyDictionaryForEncoder(
            width: 1920, height: 1080,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            encoderIDOut: nil,
            supportedPropertiesOut: nil
        )
        return encoder == noErr
    }()
    
    // MARK: - Calculate output dimensions
    /// Scales the video down to fit within maxResolution while preserving aspect ratio.
    /// Only downscales — never upscales.
    /// Uses NATURAL dimensions (pre-transform) since AVAssetReaderTrackOutput delivers
    /// pixel buffers in the track's native coordinate system. The orientation transform
    /// is preserved separately as metadata on the writer input.
    func outputDimensions(
        from naturalSize: CGSize,
        maxRes: CGFloat
    ) -> (width: Int, height: Int) {
        var w = naturalSize.width
        var h = naturalSize.height

        let longestEdge = max(w, h)

        // Only downscale, never upscale
        if longestEdge > maxRes {
            let scale = maxRes / longestEdge
            w = (w * scale).rounded(.down)
            h = (h * scale).rounded(.down)
        }

        // Ensure dimensions are even (required by H.264/HEVC encoders)
        let outW = Int(w) & ~1  // Round down to nearest even
        let outH = Int(h) & ~1

        return (max(outW, 2), max(outH, 2))
    }
    
    // MARK: - Calculate smart bitrate
    /// Calculates a target bitrate based on resolution, frame rate, and compression level.
    /// Uses a pixels-per-second model for consistent quality across different resolutions.
    func smartBitrate(
        width: Int,
        height: Int,
        frameRate: Float,
        originalBitrate: Float,
        level: CompressionLevel,
        isHEVC: Bool
    ) -> Float {
        let pixels = Float(width * height)
        let fps = max(frameRate, 24)
        
        // Base bits-per-pixel-per-frame for the level
        // HEVC is ~40% more efficient than H.264 at the same quality
        let bppBase: Float
        switch level {
        case .low:    bppBase = isHEVC ? 0.04 : 0.06
        case .medium: bppBase = isHEVC ? 0.07 : 0.10
        case .high:   bppBase = isHEVC ? 0.11 : 0.16
        }
        
        let calculatedBitrate = pixels * fps * bppBase
        
        // Never exceed original bitrate
        let capped = min(calculatedBitrate, originalBitrate * 0.95)
        
        // Floor at 200kbps to avoid garbage output
        return max(capped, 200_000)
    }
    
}



// MARK: - CompressionEngine: Delete + Helpers
extension CompressionEngine {

    // MARK: - Delete Original from Photo Library
    //
    // Returns a structured result so callers can distinguish "user denied
    // the system confirmation dialog" from "permission missing" from
    // "iOS rejected the change request". Previously returned a bare Bool
    // which made every failure look identical and silenced the real
    // reason — that's why deletions appeared to "do nothing" in the UI.
    enum DeleteOutcome {
        case success
        case failed(reason: String)
    }

    func deleteOriginal(asset: PHAsset) async -> DeleteOutcome {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else {
                    let reason = error?.localizedDescription
                        ?? "Photo library refused the delete (the system "
                        + "confirmation may have been cancelled)."
                    print("[CompressionEngine] deleteOriginal failed: \(reason)")
                    continuation.resume(returning: .failed(reason: reason))
                }
            }
        }
    }
    
    // MARK: - Helpers
    func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
    
    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
