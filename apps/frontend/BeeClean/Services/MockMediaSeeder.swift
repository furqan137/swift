//
//  MockMediaSeeder.swift
//  BeeClean
//
//  Simulator-only test helper that seeds the iOS Simulator's Photos library
//  with procedurally-generated images and short videos so every Home-screen
//  category has data to render without needing TestFlight or a manual import.
//
//  The seeder is wrapped in `#if DEBUG && targetEnvironment(simulator)` so it
//  never ships in a release build and never runs on a physical device — we
//  don't want to spam a real user's Camera Roll with junk photos.
//
//  Strategy per category:
//   • Normal photos        → random gradients at 4032×3024 (back-camera ratio)
//   • Screenshots          → flat-color images at 1170×2532 (iPhone 13/14)
//   • Similar Photos       → clusters of 4 nearly-identical gradient frames
//                            (slight color jitter so dHash flags them similar)
//   • Exact duplicates     → pairs of byte-identical PNGs
//   • Screen Recordings    → 6-second videos saved with an `RPReplay`-prefixed
//                            filename so PhotoKitService.isScreenRecording fires
//   • Short Videos         → 8-second solid-color clips at 720p
//   • Long Videos          → 65-second solid-color clips at 720p
//
//  Each piece is inserted via `PHPhotoLibrary.performChanges` with a custom
//  `PHAssetResourceCreationOptions.originalFilename` so the existing scan
//  pipeline can classify them through its normal filename + resolution +
//  duration heuristics.
//

import Foundation
import Photos
import UIKit
// `@preconcurrency` silences Swift 6's non-Sendable-capture warnings on
// AVFoundation pull-based encoding APIs (`requestMediaDataWhenReady(on:)`
// takes a @Sendable closure, but `AVAssetWriter` / `AVAssetWriterInput` /
// `AVAssetWriterInputPixelBufferAdaptor` / `CVPixelBuffer` are not
// Sendable). The closure runs on a dedicated serial dispatch queue so the
// shared state is safe in practice — Apple just hasn't backported the
// Sendable conformances. This is a debug-only seeder, never ships.
@preconcurrency import AVFoundation
import CoreMedia
import CoreImage

#if DEBUG && targetEnvironment(simulator)

@MainActor
final class MockMediaSeeder: ObservableObject {

    static let shared = MockMediaSeeder()
    private init() {}

    // MARK: - Public progress surface

    @Published private(set) var isSeeding = false
    @Published private(set) var statusLine: String = ""
    @Published private(set) var lastResult: SeedResult?

    struct SeedResult: Equatable {
        var normalPhotos: Int = 0
        var screenshots: Int = 0
        var similarPhotos: Int = 0
        var duplicatePhotos: Int = 0
        var screenRecordings: Int = 0
        var shortVideos: Int = 0
        var longVideos: Int = 0

        var totalAssets: Int {
            normalPhotos + screenshots + similarPhotos + duplicatePhotos
                + screenRecordings + shortVideos + longVideos
        }

        var summary: String {
            "Photos \(normalPhotos) · Screenshots \(screenshots) · Similar \(similarPhotos) · Duplicates \(duplicatePhotos) · ScrRec \(screenRecordings) · Short \(shortVideos) · Long \(longVideos)"
        }
    }

    // MARK: - Volume knobs
    //
    // Conservative defaults so the seed run finishes in ~60s even on a
    // first-generation simulator. Bump these locally if you want a heavier
    // library for stress testing — the scan pipeline scales fine.
    struct Config {
        var normalPhotoCount: Int = 12
        var screenshotCount: Int = 8
        var similarClusterCount: Int = 3      // each cluster = 4 frames
        var duplicatePairCount: Int = 2       // each pair = 2 frames
        var screenRecordingCount: Int = 2
        var shortVideoCount: Int = 2
        var longVideoCount: Int = 1

        static let `default` = Config()
    }

    // MARK: - Entry point

    /// Seeds the simulator Photos library. Idempotent in spirit — the library
    /// will accumulate duplicates if called repeatedly, so callers should
    /// surface a confirmation in the UI.
    func seed(config: Config = .default) async {
        guard !isSeeding else { return }
        isSeeding = true
        defer {
            isSeeding = false
            statusLine = ""
        }

        // Authorization gate. On the simulator a fresh boot will throw the
        // standard system prompt the first time we hit performChanges; we
        // request explicitly here so the user sees one alert instead of
        // seven.
        statusLine = "Requesting Photos permission…"
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            statusLine = "Permission denied — cannot seed"
            return
        }

        var result = SeedResult()

        statusLine = "Generating normal photos…"
        result.normalPhotos = await seedNormalPhotos(count: config.normalPhotoCount)

        statusLine = "Generating screenshots…"
        result.screenshots = await seedScreenshots(count: config.screenshotCount)

        statusLine = "Generating similar-photo clusters…"
        result.similarPhotos = await seedSimilarClusters(
            clusterCount: config.similarClusterCount,
            framesPerCluster: 4
        )

        statusLine = "Generating duplicate pairs…"
        result.duplicatePhotos = await seedDuplicatePairs(pairCount: config.duplicatePairCount)

        statusLine = "Generating screen recordings…"
        result.screenRecordings = await seedScreenRecordings(count: config.screenRecordingCount)

        statusLine = "Generating short videos…"
        result.shortVideos = await seedShortVideos(count: config.shortVideoCount)

        statusLine = "Generating long videos…"
        result.longVideos = await seedLongVideos(count: config.longVideoCount)

        lastResult = result
        statusLine = "Done — \(result.totalAssets) assets added"
    }

    // MARK: - Photo seeders

    private func seedNormalPhotos(count: Int) async -> Int {
        var inserted = 0
        for index in 0..<count {
            let image = Self.renderGradient(
                size: CGSize(width: 1600, height: 1200),
                seed: index * 31
            )
            let name = "MOCK_PHOTO_\(index).jpg"
            if await Self.savePhoto(image, filename: name, encoding: .jpeg) {
                inserted += 1
            }
        }
        return inserted
    }

    private func seedScreenshots(count: Int) async -> Int {
        // 1170×2532 = iPhone 13 / 14 native resolution. PhotoKitService's
        // iPhone screen-resolution catalog matches on this exact pair so the
        // fallback screenshot detector will pick them up even if iOS's smart
        // album doesn't classify them as screenshots in the simulator.
        let screenSize = CGSize(width: 1170, height: 2532)
        var inserted = 0
        for index in 0..<count {
            let image = Self.renderScreenshot(size: screenSize, seed: index * 47 + 7)
            let name = "Screenshot_\(index).png"
            if await Self.savePhoto(image, filename: name, encoding: .png) {
                inserted += 1
            }
        }
        return inserted
    }

    private func seedSimilarClusters(clusterCount: Int, framesPerCluster: Int) async -> Int {
        var inserted = 0
        for cluster in 0..<clusterCount {
            // One base seed per cluster; tiny per-frame jitter keeps the
            // frames close enough that dHash should mark them as a similar
            // group but not as exact duplicates.
            let baseSeed = (cluster + 1) * 100
            for frame in 0..<framesPerCluster {
                let image = Self.renderGradient(
                    size: CGSize(width: 1200, height: 1200),
                    seed: baseSeed + frame
                )
                let name = "MOCK_SIMILAR_\(cluster)_\(frame).jpg"
                if await Self.savePhoto(image, filename: name, encoding: .jpeg) {
                    inserted += 1
                }
            }
        }
        return inserted
    }

    private func seedDuplicatePairs(pairCount: Int) async -> Int {
        var inserted = 0
        for pair in 0..<pairCount {
            // Render once, save the same PNG bytes twice — guaranteed dHash
            // match.
            let image = Self.renderGradient(
                size: CGSize(width: 1200, height: 1200),
                seed: pair * 999 + 11
            )
            guard let png = image.pngData() else { continue }
            for copy in 0..<2 {
                let name = "MOCK_DUP_\(pair)_\(copy).png"
                if await Self.savePhotoData(png, filename: name) {
                    inserted += 1
                }
            }
        }
        return inserted
    }

    // MARK: - Video seeders

    private func seedScreenRecordings(count: Int) async -> Int {
        // Use the `RPReplay_Final` filename prefix that iOS ReplayKit stamps
        // on captures so PhotoKitService.isScreenRecording matches.
        // 1170×2532 also triggers the secondary content-fallback check.
        var inserted = 0
        for index in 0..<count {
            let url = await Self.makeSolidColorVideo(
                size: CGSize(width: 1170, height: 2532),
                duration: 6.0,
                color: UIColor(hue: CGFloat(index) * 0.13, saturation: 0.7, brightness: 0.8, alpha: 1),
                filename: "rpreplay_mock_\(index).mp4"
            )
            guard let url else { continue }
            let original = "RPReplay_Final\(Int(Date().timeIntervalSince1970))_\(index).mp4"
            if await Self.saveVideo(url: url, originalFilename: original) {
                inserted += 1
            }
            try? FileManager.default.removeItem(at: url)
        }
        return inserted
    }

    private func seedShortVideos(count: Int) async -> Int {
        // Short = ≤60s in PhotoKitService.fetchShortVideos. 8s easily clears.
        var inserted = 0
        for index in 0..<count {
            let url = await Self.makeSolidColorVideo(
                size: CGSize(width: 1280, height: 720),
                duration: 8.0,
                color: UIColor(hue: CGFloat(index) * 0.21, saturation: 0.65, brightness: 0.7, alpha: 1),
                filename: "short_mock_\(index).mp4"
            )
            guard let url else { continue }
            if await Self.saveVideo(url: url, originalFilename: "ShortVid_\(index).mp4") {
                inserted += 1
            }
            try? FileManager.default.removeItem(at: url)
        }
        return inserted
    }

    private func seedLongVideos(count: Int) async -> Int {
        // Long = >60s. 65s is enough without making the seed run painful.
        var inserted = 0
        for index in 0..<count {
            let url = await Self.makeSolidColorVideo(
                size: CGSize(width: 1280, height: 720),
                duration: 65.0,
                color: UIColor(hue: CGFloat(index) * 0.34, saturation: 0.55, brightness: 0.6, alpha: 1),
                filename: "long_mock_\(index).mp4"
            )
            guard let url else { continue }
            if await Self.saveVideo(url: url, originalFilename: "LongVid_\(index).mp4") {
                inserted += 1
            }
            try? FileManager.default.removeItem(at: url)
        }
        return inserted
    }

    // MARK: - PhotoKit insertion helpers

    private enum Encoding {
        case jpeg
        case png
    }

    private static func savePhoto(_ image: UIImage, filename: String, encoding: Encoding) async -> Bool {
        let data: Data?
        switch encoding {
        case .jpeg:
            data = image.jpegData(compressionQuality: 0.85)
        case .png:
            data = image.pngData()
        }
        guard let data else { return false }
        return await savePhotoData(data, filename: filename)
    }

    private static func savePhotoData(_ data: Data, filename: String) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                request.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if let error {
                    print("[MockMediaSeeder] photo insert failed for \(filename): \(error)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    private static func saveVideo(url: URL, originalFilename: String) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            } completionHandler: { success, error in
                if let error {
                    print("[MockMediaSeeder] video insert failed for \(originalFilename): \(error)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Image generation

    /// Procedural gradient image. The `seed` controls hue + diagonal direction
    /// so successive frames in a "similar" cluster look almost-but-not-quite
    /// identical.
    private static func renderGradient(size: CGSize, seed: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let baseHue = (CGFloat(seed % 360)) / 360.0
            let topColor = UIColor(hue: baseHue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor
            let botColor = UIColor(
                hue: fmod(baseHue + 0.18, 1.0),
                saturation: 0.85,
                brightness: 0.45,
                alpha: 1
            ).cgColor
            let colorspace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: colorspace,
                colors: [topColor, botColor] as CFArray,
                locations: [0.0, 1.0]
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            // Stamp the seed in big text so visually-skimming the Camera Roll
            // makes it obvious these are mock photos and how they were
            // grouped.
            let label = "MOCK \(seed)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: size.height * 0.12),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let textSize = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attrs
            )
        }
    }

    /// Screenshot-shaped flat panel — a colored backdrop with a fake "status
    /// bar" and fake content rows. Doesn't need to fool a human, just needs
    /// pixel dimensions that match iPhone screen resolutions.
    private static func renderScreenshot(size: CGSize, seed: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Background — light pastel.
            let bgHue = (CGFloat(seed % 360)) / 360.0
            UIColor(hue: bgHue, saturation: 0.25, brightness: 0.95, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Status bar
            UIColor.black.withAlphaComponent(0.05).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.04))

            // Card rows
            for row in 0..<8 {
                let y = size.height * (0.10 + 0.10 * CGFloat(row))
                let rect = CGRect(
                    x: size.width * 0.06,
                    y: y,
                    width: size.width * 0.88,
                    height: size.height * 0.07
                )
                UIColor.white.withAlphaComponent(0.85).setFill()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 18)
                path.fill()
            }

            // Big "MOCK SCREENSHOT" stamp.
            let label = "MOCK SCREENSHOT #\(seed)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: size.height * 0.04),
                .foregroundColor: UIColor.black.withAlphaComponent(0.4)
            ]
            let textSize = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height * 0.93),
                withAttributes: attrs
            )
        }
    }

    // MARK: - Video generation

    /// Writes a single-color video to a temp URL using AVAssetWriter.
    /// Returns the URL on success, or nil on failure.
    ///
    /// Single-color is deliberate: we just need a valid container at the
    /// requested resolution/duration; no frame variation is needed for the
    /// short/long/screen-recording categories to classify correctly.
    private static func makeSolidColorVideo(
        size: CGSize,
        duration: TimeInterval,
        color: UIColor,
        filename: String
    ) async -> URL? {
        let tmpDir = FileManager.default.temporaryDirectory
        let outURL = tmpDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        } catch {
            print("[MockMediaSeeder] AVAssetWriter init failed: \(error)")
            return nil
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)

        guard writer.startWriting() else {
            print("[MockMediaSeeder] AVAssetWriter startWriting failed: \(String(describing: writer.error))")
            return nil
        }
        writer.startSession(atSourceTime: .zero)

        // Build a single pre-painted pixel buffer and append it for every
        // frame — cheaper than re-rendering 30fps × duration frames.
        guard let buffer = Self.makeColorPixelBuffer(size: size, color: color) else {
            writer.cancelWriting()
            return nil
        }

        let fps: Int32 = 30
        let totalFrames = Int(duration * Double(fps))
        let bundle = WriterBundle(writer: writer, input: input, adaptor: adaptor, buffer: buffer)

        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "mock.seeder.video", qos: .userInitiated)
            // Frame counter lives on the bundle so it's mutable from inside
            // the @Sendable closure without triggering capture warnings.
            bundle.input.requestMediaDataWhenReady(on: queue) {
                while bundle.input.isReadyForMoreMediaData && bundle.frameIndex < totalFrames {
                    let presentTime = CMTime(value: CMTimeValue(bundle.frameIndex), timescale: fps)
                    if !bundle.adaptor.append(bundle.buffer, withPresentationTime: presentTime) {
                        bundle.input.markAsFinished()
                        bundle.writer.finishWriting {
                            continuation.resume()
                        }
                        return
                    }
                    bundle.frameIndex += 1
                }
                if bundle.frameIndex >= totalFrames {
                    bundle.input.markAsFinished()
                    bundle.writer.finishWriting {
                        continuation.resume()
                    }
                }
            }
        }

        guard writer.status == .completed else {
            print("[MockMediaSeeder] writer finished with status \(writer.status.rawValue), error: \(String(describing: writer.error))")
            return nil
        }
        return outURL
    }

    private static func makeColorPixelBuffer(size: CGSize, color: UIColor) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let base = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let rgb = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue))
        guard let ctx = CGContext(
            data: base,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: rgb,
            bitmapInfo: bitmap.rawValue
        ) else { return nil }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - WriterBundle
//
// `@unchecked Sendable` box for the AVFoundation video-writer references
// used inside the pull-based `requestMediaDataWhenReady(on:)` closure.
// AVAssetWriter et al. aren't (yet) marked Sendable by Apple, but capture
// inside that closure is safe because all access funnels through the
// dedicated serial dispatch queue that the API itself owns.
private final class WriterBundle: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let buffer: CVPixelBuffer
    var frameIndex: Int = 0

    init(
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        buffer: CVPixelBuffer
    ) {
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.buffer = buffer
    }
}

#endif
