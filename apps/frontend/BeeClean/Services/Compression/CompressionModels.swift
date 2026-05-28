import Foundation
import CoreGraphics

// MARK: - Compression Level
enum CompressionLevel: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    /// Target bitrate as a fraction of the original
    var bitrateMultiplier: Float {
        switch self {
        case .low:    return 0.12   // Aggressive compression
        case .medium: return 0.30   // Balanced sweet-spot
        case .high:   return 0.55   // Near-original quality
        }
    }

    /// Maximum resolution (longest edge) for this level
    var maxResolution: CGFloat {
        switch self {
        case .low:    return 720    // Downscale to 720p
        case .medium: return 1080   // Cap at 1080p
        case .high:   return 2160   // Allow up to 4K
        }
    }

    /// Audio bitrate in bits/sec
    var audioBitrate: Int {
        switch self {
        case .low:    return 64_000   // 64 kbps — saves space
        case .medium: return 128_000  // 128 kbps — good quality
        case .high:   return 192_000  // 192 kbps — near-transparent
        }
    }

    /// Audio channel count
    var audioChannels: Int {
        switch self {
        case .low:    return 1  // Mono — saves ~50% audio size
        case .medium: return 2  // Stereo
        case .high:   return 2
        }
    }

    var label: String {
        switch self {
        case .low:    return "Max Compression"
        case .medium: return "Balanced"
        case .high:   return "High Quality"
        }
    }

    var subtitle: String {
        switch self {
        case .low:    return "Smallest file size"
        case .medium: return "Best balance"
        case .high:   return "Near original quality"
        }
    }

    /// User-facing percentage for the level picker (how much to compress by)
    var displayPercent: Int {
        switch self {
        case .low:    return 90
        case .medium: return 65
        case .high:   return 40
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down.to.line"
        case .medium: return "scalemass"
        case .high:   return "sparkles"
        }
    }

    func estimatedSize(from originalSize: Int64) -> Int64 {
        // Rough estimate using bitrateMultiplier — actual depends on content/resolution
        let videoEstimate = Float(originalSize) * bitrateMultiplier
        // Audio is roughly 5-10% of a typical video file; estimate conservatively
        let audioOverhead = Float(originalSize) * 0.05
        return max(Int64(videoEstimate + audioOverhead), 1024)
    }

    /// More accurate estimate when video resolution and bitrate are known
    func estimatedSize(from originalSize: Int64, resolution: CGSize?, bitrate: Float?, fps: Float = 30) -> Int64 {
        guard let resolution = resolution, let bitrate = bitrate, bitrate > 0 else {
            return estimatedSize(from: originalSize)
        }
        let w = Float(resolution.width)
        let h = Float(resolution.height)
        let maxRes = Float(maxResolution)
        let longest = max(w, h)

        // Calculate output dimensions (mirrors outputDimensions logic)
        var outW = w
        var outH = h
        if longest > maxRes {
            let scale = maxRes / longest
            outW = (w * scale).rounded(.down)
            outH = (h * scale).rounded(.down)
        }

        // HEVC bpp (assume HEVC since most modern devices support it)
        let bpp: Float
        switch self {
        case .low:    bpp = 0.04
        case .medium: bpp = 0.07
        case .high:   bpp = 0.11
        }

        let targetBitrate = min(outW * outH * fps * bpp, bitrate * 0.95)
        let safeBitrate = max(targetBitrate, 200_000)

        let durationSec = Float(originalSize * 8) / bitrate
        let videoBits = safeBitrate * durationSec
        let audioBits = Float(audioBitrate) * durationSec

        return max(Int64((videoBits + audioBits) / 8), 1024)
    }

    func estimatedSavings(from originalSize: Int64) -> Int64 {
        originalSize - estimatedSize(from: originalSize)
    }

    func estimatedSavings(from originalSize: Int64, resolution: CGSize?, bitrate: Float?, fps: Float = 30) -> Int64 {
        originalSize - estimatedSize(from: originalSize, resolution: resolution, bitrate: bitrate, fps: fps)
    }

    // MARK: - Photo-specific tuning

    /// Maximum longest-edge dimension for the encoded photo (in pixels).
    var maxPhotoDimension: CGFloat {
        switch self {
        case .low:    return 2048   // ~3MP — shareable, big saves
        case .medium: return 3072   // ~7MP — Instagram-tier
        case .high:   return 4096   // ~12MP — print quality
        }
    }

    /// HEIC/JPEG lossy quality (0.0–1.0) for the encoded photo.
    var photoQuality: CGFloat {
        switch self {
        case .low:    return 0.40
        case .medium: return 0.65
        case .high:   return 0.85
        }
    }

    /// User-facing photo savings %.
    var photoDisplayPercent: Int {
        switch self {
        case .low:    return 80
        case .medium: return 60
        case .high:   return 35
        }
    }

    /// Rough size estimate for a recompressed photo using a flat multiplier.
    func estimatedPhotoSize(from originalSize: Int64) -> Int64 {
        let multiplier: Float
        switch self {
        case .low:    multiplier = 0.20
        case .medium: multiplier = 0.40
        case .high:   multiplier = 0.65
        }
        return max(Int64(Float(originalSize) * multiplier), 8_192)
    }

    /// Better estimate for photos when pixel dimensions and source format are known.
    /// HEIC sources already compress well, so re-encoding saves less than re-encoding a JPEG.
    func estimatedPhotoSize(from originalSize: Int64, resolution: CGSize?, sourceFormat: String?) -> Int64 {
        guard let resolution = resolution, resolution.width > 0, resolution.height > 0 else {
            return estimatedPhotoSize(from: originalSize)
        }

        let longest = Float(max(resolution.width, resolution.height))
        let maxDim = Float(maxPhotoDimension)
        let scale = longest > maxDim ? (maxDim / longest) : 1.0
        let pixelRatio = scale * scale  // area scales with square of edge ratio

        // Base recompression multiplier — how much smaller bytes-per-pixel becomes
        // after the lossy re-encode at this quality level. HEIC sources already
        // use efficient coding, so the win comes mostly from downscaling + lower q.
        let isAlreadyEfficient = (sourceFormat?.uppercased() == "HEIC" || sourceFormat?.uppercased() == "HEIF")
        let perPixelMult: Float
        switch self {
        case .low:    perPixelMult = isAlreadyEfficient ? 0.55 : 0.35
        case .medium: perPixelMult = isAlreadyEfficient ? 0.75 : 0.55
        case .high:   perPixelMult = isAlreadyEfficient ? 0.92 : 0.78
        }

        let estimated = Float(originalSize) * pixelRatio * perPixelMult
        return max(Int64(estimated), 8_192)
    }

    func estimatedPhotoSavings(from originalSize: Int64) -> Int64 {
        max(originalSize - estimatedPhotoSize(from: originalSize), 0)
    }

    func estimatedPhotoSavings(from originalSize: Int64, resolution: CGSize?, sourceFormat: String?) -> Int64 {
        max(originalSize - estimatedPhotoSize(from: originalSize, resolution: resolution, sourceFormat: sourceFormat), 0)
    }
}

// MARK: - Compression Result
struct CompressionResult {
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let compressionTime: TimeInterval
    let codec: String
    let outputResolution: String

    var savings: Int64 { max(originalSize - compressedSize, 0) }
    var didGrow: Bool { compressedSize >= originalSize }
    var savingsPercent: Int {
        guard originalSize > 0, !didGrow else { return 0 }
        return Int((Double(originalSize - compressedSize) / Double(originalSize)) * 100)
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: savings, countStyle: .file)
    }

    var formattedTime: String {
        if compressionTime < 60 {
            return String(format: "%.1fs", compressionTime)
        } else {
            let minutes = Int(compressionTime) / 60
            let seconds = Int(compressionTime) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Compression Phase
enum CompressionPhase: String {
    case idle = "Ready"
    case preparing = "Preparing..."
    case exporting = "Loading from library..."
    case analyzing = "Analyzing video..."
    case compressing = "Compressing..."
    case finishing = "Finishing up..."
    case done = "Complete"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

// MARK: - Compression Error
enum CompressionError: LocalizedError {
    case noVideoTrack
    case readerSetupFailed(String)
    case writerSetupFailed(String)
    case readingFailed(String)
    case writingFailed(String)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:              return "No video track found."
        case .readerSetupFailed(let m):  return "Reader setup failed: \(m)"
        case .writerSetupFailed(let m):  return "Writer setup failed: \(m)"
        case .readingFailed(let m):      return "Reading failed: \(m)"
        case .writingFailed(let m):      return "Writing failed: \(m)"
        case .exportFailed(let m):       return "Export failed: \(m)"
        case .cancelled:                 return "Compression was cancelled."
        }
    }
}

// MARK: - Thread-safe shared state
final class CompressionSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _encounteredError = false

    var isCancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); defer { lock.unlock() }; _cancelled = newValue }
    }

    var encounteredError: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _encounteredError }
        set { lock.lock(); defer { lock.unlock() }; _encounteredError = newValue }
    }
}
