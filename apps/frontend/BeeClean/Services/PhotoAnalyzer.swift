import Foundation
import Photos
import UIKit
@preconcurrency import AVFoundation

// MARK: - Continuation One-Shot Guard
//
// Wraps a Bool with NSLock so a single callback closure that may fire
// multiple times (PHImageManager, AVAssetImageGenerator, etc.) can claim
// "I'm the one resuming the continuation" exactly once. Resuming a
// CheckedContinuation twice is a hard runtime trap; using a class instead
// of a value type ensures both closure invocations share the same state.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    /// Atomically flips `taken false → true` and returns whether the caller
    /// is the first to claim it. Subsequent calls return `false` and the
    /// caller must NOT touch the continuation.
    func tryClaim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

// MARK: - Analyzed Photo Model
struct AnalyzedPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let assetIdentifier: String
    let dHash64: UInt64
    let sharpnessScore: Double
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64?
    /// Provenance: which app saved this asset (Snapchat / WhatsApp /
    /// Instagram / etc.) Populated in two passes:
    ///   • Tier 1 — filename match inside PhotoAnalyzer.analyzeAsset.
    ///   • Tier 2 — EXIF Software tag in PhotoSourceDetector background pass.
    /// `nil` means "detection hasn't classified this asset yet" — the badge
    /// view simply renders nothing. `.camera` is the explicit "user's own
    /// capture" sentinel (no badge).
    var sourceApp: PhotoSource?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AnalyzedPhoto, rhs: AnalyzedPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Progress State
struct PhotoAnalysisProgress: Sendable {
    var totalPhotos: Int = 0
    var processedPhotos: Int = 0
    var currentPhase: String = "Initializing"
    var isComplete: Bool = false
    var error: String?

    var progress: Double {
        guard totalPhotos > 0 else { return 0 }
        return Double(processedPhotos) / Double(totalPhotos)
    }

    var percentComplete: Int {
        Int(progress * 100)
    }
}

// MARK: - Photo Analyzer (Background Processing)
final class PhotoAnalyzer: Sendable {

    /// Sentinel sharpness score indicating the asset's image could not be
    /// decoded (iCloud-only with no network, corrupt, unsupported format, etc.).
    /// Assets with this score are KEPT in the analyzedIndex so they surface
    /// in Other Photos / Other Videos, but are excluded from similarity
    /// clustering and blurry detection.
    static let metadataOnlySharpness: Double = -1

    static func isMetadataOnly(_ photo: AnalyzedPhoto) -> Bool {
        photo.sharpnessScore < 0
    }

    /// Always returns an AnalyzedPhoto for the asset — never nil.
    /// - Happy path: fastFormat decode → real dHash + sharpness.
    /// - Degraded path: retry highQualityFormat (forces iCloud download if needed).
    /// - Fallback: metadata-only AnalyzedPhoto with sentinel sharpness so the
    ///   asset still enters analyzedIndex and shows up in Other Photos/Videos.
    ///
    /// This is the single most important invariant in the scan pipeline:
    /// every PHAsset the library yields MUST produce an AnalyzedPhoto, or
    /// that asset silently disappears from the user's view.
    ///
    /// `networkAccess: false` skips iCloud downloads — for the first scan
    /// pass we want fast local-only analysis. iCloud-only assets fall back
    /// to a metadata-only sentinel and are re-analyzed in a background
    /// pass after the local-pass results have already lit up the UI.
    func analyzeAsset(_ asset: PHAsset, networkAccess: Bool = true) async -> AnalyzedPhoto {
        // Tier 1 source detection — filename pattern match. Cheap (~1ms);
        // shared by every return path in this function so the badge + per-
        // source dashboard cards light up on the same scan that produces
        // the hash/sharpness data. Tier 2 EXIF enrichment in
        // PhotoSourceDetector backfills Instagram (and any source the
        // filename pass missed) on a background pass after the scan ships.
        let sourceApp = PhotoKitService.detectSourceFromFilename(asset)

        // Videos go through a multi-frame hashing path so two clips with
        // identical opening frames but divergent content (a common camera-roll
        // pattern: two recordings that start with the same scene cut) don't
        // collide as duplicates. The photo path stays on the cheap single-frame
        // dHash since it's already optimal for stills.
        if asset.mediaType == .video {
            return await analyzeVideoAsset(asset, sourceApp: sourceApp)
        }

        // dHash downsamples to 9×8, sharpness to 128×128 — match the
        // larger consumer (sharpness) exactly. Trimmed from 160→128 to
        // save another ~36% on decode pixel count per asset, which
        // compounds across thousands of analyzeAsset calls during a
        // full library scan. No accuracy regression — sharpness was
        // already downsampling 160→128 internally before this anyway.
        let targetSize = CGSize(width: 128, height: 128)

        if let cg = await requestCGImage(asset: asset, targetSize: targetSize, deliveryMode: .fastFormat, networkAccess: networkAccess) {
            return realAnalyzedPhoto(asset: asset, cgImage: cg, sourceApp: sourceApp)
        }

        // iCloud-only assets or transient decode failures — retry once with
        // high-quality delivery which forces a network download if required.
        // Skipped on local-only passes; the iCloud retry pass runs in the
        // background after the local-pass results have already shipped.
        if let cg = await requestCGImage(asset: asset, targetSize: targetSize, deliveryMode: .highQualityFormat, networkAccess: networkAccess) {
            return realAnalyzedPhoto(asset: asset, cgImage: cg, sourceApp: sourceApp)
        }

        // Image truly unavailable — return metadata-only so the asset still
        // appears in Other Photos/Videos instead of vanishing.
        return AnalyzedPhoto(
            id: asset.localIdentifier,
            assetIdentifier: asset.localIdentifier,
            dHash64: 0,
            sharpnessScore: Self.metadataOnlySharpness,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: getAssetFileSize(asset),
            sourceApp: sourceApp
        )
    }

    // MARK: - Video: multi-frame fingerprinting
    //
    // Sampling 5 frames evenly across the duration and combining their dHashes
    // by per-bit majority vote turns the 64-bit fingerprint into a "signature
    // of the whole clip" rather than just its first frame. Two clips that
    // start identically but diverge (vacation reshoot, retake, B-roll variant)
    // now have different majority bits across the middle/end frames and stop
    // colliding as duplicates. Two clips that ARE the same content recorded
    // separately still produce nearly identical majority signatures and
    // continue to cluster as duplicates.
    //
    // We pick 5 frames because: (a) it's enough to distinguish typical
    // diverging clips at scene cuts, (b) AVAssetImageGenerator amortizes
    // setup cost — 5 frames is barely slower than 1 since the asset is
    // already loaded, (c) majority over an odd count avoids tie-breaks.
    private static let videoFrameSampleCount: Int = 5

    private func analyzeVideoAsset(_ asset: PHAsset, sourceApp: PhotoSource? = nil) async -> AnalyzedPhoto {
        let duration = asset.duration
        guard duration > 0,
              let avAsset = await requestAVAsset(asset)
        else {
            return await analyzeVideoFallbackToFirstFrame(asset, sourceApp: sourceApp)
        }

        let cgImages = await sampleFrames(from: avAsset, count: Self.videoFrameSampleCount, duration: duration)
        guard !cgImages.isEmpty else {
            return await analyzeVideoFallbackToFirstFrame(asset, sourceApp: sourceApp)
        }

        // Per-bit majority across sampled frames. Sharpness uses the max
        // (best representative frame) so a clip with one in-focus moment and
        // 4 motion-blurred frames isn't penalized as blurry.
        let frameHashes = cgImages.map { computeDHash64(cgImage: $0) }
        let frameSharpness = cgImages.map { computeSharpnessScore(cgImage: $0) }
        let composite = majorityBits(frameHashes)
        let sharpness = frameSharpness.max() ?? 0

        return AnalyzedPhoto(
            id: asset.localIdentifier,
            assetIdentifier: asset.localIdentifier,
            dHash64: composite,
            sharpnessScore: sharpness,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: getAssetFileSize(asset),
            sourceApp: sourceApp
        )
    }

    /// Last-resort path: AVAsset wasn't available (iCloud-only video with no
    /// network, restricted resource). Fall back to PHImageManager's
    /// thumbnail which is the same single-frame signal we used to use, so
    /// nothing regresses for the unhappy path.
    private func analyzeVideoFallbackToFirstFrame(_ asset: PHAsset, sourceApp: PhotoSource? = nil) async -> AnalyzedPhoto {
        // Match the photo path's 128×128 — sharpness internal grid is
        // 128×128, dHash is 9×8, anything bigger is wasted decode work.
        let targetSize = CGSize(width: 128, height: 128)
        if let cg = await requestCGImage(asset: asset, targetSize: targetSize, deliveryMode: .fastFormat) {
            return realAnalyzedPhoto(asset: asset, cgImage: cg, sourceApp: sourceApp)
        }
        if let cg = await requestCGImage(asset: asset, targetSize: targetSize, deliveryMode: .highQualityFormat) {
            return realAnalyzedPhoto(asset: asset, cgImage: cg, sourceApp: sourceApp)
        }
        return AnalyzedPhoto(
            id: asset.localIdentifier,
            assetIdentifier: asset.localIdentifier,
            dHash64: 0,
            sharpnessScore: Self.metadataOnlySharpness,
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: getAssetFileSize(asset),
            sourceApp: sourceApp
        )
    }

    private func requestAVAsset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    private func sampleFrames(from avAsset: AVAsset, count: Int, duration: TimeInterval) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        // Allow a wide tolerance — we don't need frame-accurate seeking for
        // perceptual hashing, and tight tolerances make seeks 5–10× slower.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        // Skip the absolute boundaries (often black frames from fade-in/fade-out
        // that would make every clip look identical at the edges). Use 10%–90%
        // of duration so the samples actually represent the clip's content.
        let inset = duration * 0.10
        let usable = max(0.001, duration - 2 * inset)
        let step = count > 1 ? usable / Double(count - 1) : 0
        let times: [NSValue] = (0..<count).map { i in
            NSValue(time: CMTime(seconds: inset + step * Double(i), preferredTimescale: 600))
        }
        return await withCheckedContinuation { continuation in
            // AVAssetImageGenerator dispatches the per-time closure on a
            // private serial-but-not-strictly-ordered queue, and the callback
            // can fire concurrently if multiple frames decode at once. The
            // previous `nonisolated(unsafe) var` was a compiler shrug — at
            // runtime two callbacks could race the `seenCount += 1` (lost
            // increments → continuation never resumes → caller hangs forever)
            // OR both observe `seenCount == expectedCount` and resume the
            // continuation twice (hard trap on Swift 6).
            //
            // A class wrapped in NSLock keeps the mutation atomic, and
            // ResumeOnce makes the resume idempotent so even if a race somehow
            // double-counts, the second resume is silently dropped.
            let state = FrameSampleState(expected: times.count)
            let resumed = ResumeOnce()

            generator.generateCGImagesAsynchronously(forTimes: times) { _, image, _, result, _ in
                let isComplete = state.record(image: result == .succeeded ? image : nil)
                if isComplete && resumed.tryClaim() {
                    continuation.resume(returning: state.snapshot())
                }
            }
        }
    }

    /// Thread-safe accumulator for AVAssetImageGenerator frame callbacks.
    /// Class (not struct) so all callbacks share the same instance regardless
    /// of which queue dispatches them; NSLock around every mutation/read.
    private final class FrameSampleState: @unchecked Sendable {
        private let lock = NSLock()
        private var collected: [CGImage] = []
        private var seenCount = 0
        private let expected: Int

        init(expected: Int) {
            self.expected = expected
            collected.reserveCapacity(expected)
        }

        /// Returns true once the final frame has been recorded.
        func record(image: CGImage?) -> Bool {
            lock.lock(); defer { lock.unlock() }
            seenCount += 1
            if let image = image { collected.append(image) }
            return seenCount >= expected
        }

        func snapshot() -> [CGImage] {
            lock.lock(); defer { lock.unlock() }
            return collected
        }
    }

    /// Per-bit majority across N hashes. Bit i of the result is 1 iff > N/2
    /// of the inputs have bit i set. With odd N (5) there are no ties.
    private func majorityBits(_ hashes: [UInt64]) -> UInt64 {
        guard !hashes.isEmpty else { return 0 }
        if hashes.count == 1 { return hashes[0] }

        var result: UInt64 = 0
        let half = hashes.count / 2
        for bit in 0..<64 {
            var count = 0
            let mask: UInt64 = 1 << UInt64(bit)
            for h in hashes where (h & mask) != 0 {
                count += 1
            }
            if count > half {
                result |= mask
            }
        }
        return result
    }

    private func realAnalyzedPhoto(asset: PHAsset, cgImage: CGImage, sourceApp: PhotoSource? = nil) -> AnalyzedPhoto {
        AnalyzedPhoto(
            id: asset.localIdentifier,
            assetIdentifier: asset.localIdentifier,
            dHash64: computeDHash64(cgImage: cgImage),
            sharpnessScore: computeSharpnessScore(cgImage: cgImage),
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: getAssetFileSize(asset),
            sourceApp: sourceApp
        )
    }

    private func requestCGImage(
        asset: PHAsset,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        networkAccess: Bool = true
    ) async -> CGImage? {
        // PHImageManager will fire the result handler MULTIPLE times when the
        // delivery mode allows progressive results (`.opportunistic` is the
        // SDK default; even `.fastFormat`/`.highQualityFormat` can fire
        // twice for cancelled requests). Resuming a CheckedContinuation a
        // second time is a hard runtime trap ("SWIFT TASK CONTINUATION
        // MISUSE"), which crashed the scan path on iCloud-backed assets.
        //
        // Guard with an actor-isolated atomic flag that swaps `false → true`
        // exactly once. The very first non-degraded callback resumes; any
        // later degraded/final/cancel callback is dropped.
        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = networkAccess
            options.isSynchronous = false

            let resumed = ResumeOnce()

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if image == nil, let error = info?[PHImageErrorKey] as? NSError {
                    // Per-asset failure log — gated behind `BCLog.debug`
                    // so production builds skip the call entirely. On
                    // iCloud-heavy libraries this used to fire thousands
                    // of times per scan and each `print` round-tripped
                    // into the unified-logging daemon, producing visible
                    // scan-progress hitches.
                    BCLog.debug("[PhotoAnalyzer] ⚠ \(deliveryMode == .fastFormat ? "fast" : "HQ") decode failed for \(asset.localIdentifier): \(error.localizedDescription)")
                }
                // Wait for the final (non-degraded) callback before resuming.
                // PHImageResultIsDegradedKey == true means a low-res preview;
                // a higher-quality result is still on the way.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded && image != nil {
                    return
                }
                if resumed.tryClaim() {
                    continuation.resume(returning: image)
                }
            }
        }
        return image?.cgImage
    }

    func computeDHash64(cgImage: CGImage) -> UInt64 {
        let width = 9
        let height = 8

        guard let grayscale = resizeToGrayscale(cgImage: cgImage, width: width, height: height) else {
            return 0
        }

        var hash: UInt64 = 0
        var bitIndex = 0

        for row in 0..<height {
            for col in 0..<(width - 1) {
                let leftPixel = grayscale[row * width + col]
                let rightPixel = grayscale[row * width + col + 1]

                if leftPixel > rightPixel {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }

        return hash
    }

    func computeSharpnessScore(cgImage: CGImage) -> Double {
        let targetSize = 128

        guard let grayscale = resizeToGrayscale(cgImage: cgImage, width: targetSize, height: targetSize) else {
            return 0
        }

        // Dual-signal sharpness — Laplacian variance + Tenengrad (Sobel
        // gradient energy), both center-weighted, combined to catch every
        // class of blur the user can throw at us.
        //
        // Why two signals: Laplacian alone misses smooth motion blur. A
        // panned shot of a moving subject has low edge intensity (Laplacian
        // is small) but high directional gradient (Sobel is too because the
        // gradient itself is smeared). Combining them — and taking the
        // signal that says "blurry" most loudly — flags both classic
        // out-of-focus AND motion-blur cases that pure Laplacian missed.
        //
        // Bokeh handling: both metrics are computed over a center 50%×50%
        // region (where the subject actually is). A portrait-mode photo's
        // sharp face dominates the center pool while the soft background
        // averages out at the edges — neither metric punishes intentional
        // bokeh. A photo that's blurry-center / sharp-edges (rare; usually
        // a missed-focus shot) is correctly flagged because both center
        // metrics drop.
        let centerStart = targetSize / 4
        let centerEnd = (targetSize * 3) / 4

        var laplacianCenterSum: Double = 0
        var sobelCenterSum: Double = 0
        var centerCount = 0

        for y in 1..<(targetSize - 1) {
            for x in 1..<(targetSize - 1) {
                let isCenter = (y >= centerStart && y < centerEnd
                                && x >= centerStart && x < centerEnd)
                guard isCenter else { continue }

                let c = Double(grayscale[y * targetSize + x])
                let tl = Double(grayscale[(y - 1) * targetSize + (x - 1)])
                let t  = Double(grayscale[(y - 1) * targetSize + x])
                let tr = Double(grayscale[(y - 1) * targetSize + (x + 1)])
                let l  = Double(grayscale[y * targetSize + (x - 1)])
                let r  = Double(grayscale[y * targetSize + (x + 1)])
                let bl = Double(grayscale[(y + 1) * targetSize + (x - 1)])
                let b  = Double(grayscale[(y + 1) * targetSize + x])
                let br = Double(grayscale[(y + 1) * targetSize + (x + 1)])

                // Laplacian (4-point) — picks up edge intensity, classic
                // out-of-focus indicator.
                let laplacian = t + b + l + r - 4 * c
                laplacianCenterSum += laplacian * laplacian

                // Sobel — gradient magnitude squared (sum of horizontal
                // and vertical gradients). Tenengrad's strength: motion-
                // blurred regions have washed-out gradients across the
                // direction of motion, giving a measurably lower score
                // than a sharp scene of the same content.
                let gx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let gy = (bl + 2 * b + br) - (tl + 2 * t + tr)
                sobelCenterSum += (gx * gx) + (gy * gy)

                centerCount += 1
            }
        }

        guard centerCount > 0 else { return 0 }
        let laplacianScore = laplacianCenterSum / Double(centerCount)

        // Sobel gradients are typically 4–8× larger than Laplacian variance
        // on natural images. Scale Tenengrad down so both signals live on
        // the same numeric range as the existing thresholds in
        // SimilarPhotosStore+Computed (< 30 = very blurry, < 80 = blurry).
        // 0.18 was calibrated on a real iPhone library so a sharp photo
        // produces tenengrad ≈ laplacian.
        let tenengradScore = (sobelCenterSum / Double(centerCount)) * 0.18

        // MIN combine — the most pessimistic signal wins. If EITHER metric
        // says "blurry," the photo is blurry. This is the recall-favoured
        // combine rule the user asked for: "scan for ALL blurry photos."
        // A photo with high Laplacian but low Tenengrad (motion-blurred
        // detail-rich scene) is now correctly caught; same for the reverse
        // (out-of-focus textured background that fools Sobel).
        return min(laplacianScore, tenengradScore)
    }

    private func resizeToGrayscale(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixels
    }

    private func getAssetFileSize(_ asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { return nil }

        if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            return fileSize
        }
        return nil
    }

    static func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        let xor = hash1 ^ hash2
        return xor.nonzeroBitCount
    }
}
