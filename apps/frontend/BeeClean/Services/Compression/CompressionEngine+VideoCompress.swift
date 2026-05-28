import Foundation
@preconcurrency import AVFoundation
import VideoToolbox
import UIKit

extension CompressionEngine {
    // MARK: - Compress Video (URL)
    /// Compresses a video file at the given URL. Works with any local video file,
    /// not just PHAssets — enabling mock/test video compression.
    func compressVideo(inputURL: URL, level: CompressionLevel) async {
        // Only reset if not already started (PHAsset wrapper calls reset itself)
        if !isCompressing {
            reset()
            isCompressing = true
        }

        let startTime = Date()

        do {
            let originalSize = fileSize(at: inputURL)
            guard originalSize > 0 else {
                throw CompressionError.readingFailed("Video file is empty (0 bytes).")
            }

            phase = .analyzing

            // ── Step 1: Load AVAsset + track properties ──
            let asset = AVURLAsset(url: inputURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw CompressionError.noVideoTrack
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audioTrack = audioTracks.first

            let naturalSize = try await videoTrack.load(.naturalSize)
            guard naturalSize.width > 0, naturalSize.height > 0 else {
                throw CompressionError.noVideoTrack
            }
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let duration = try await asset.load(.duration)
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds.isFinite, totalSeconds > 0 else {
                throw CompressionError.readingFailed("Video has invalid duration.")
            }

            guard !shared.isCancelled else {
                isCompressing = false; phase = .cancelled; return
            }

            // ── Step 2: Determine codec ──
            let useHEVC = Self.supportsHEVC
            let codecType: AVVideoCodecType = useHEVC ? .hevc : .h264
            let codecName = useHEVC ? "HEVC" : "H.264"

            // ── Step 3: Calculate output dimensions (in natural/encode space) ──
            let dims = outputDimensions(
                from: naturalSize,
                maxRes: level.maxResolution
            )

            // ── Fast path: pass-through for already-optimal HEVC sources ──
            // When the source is HEVC, already ≤ target resolution, and its
            // bitrate sits within 10% of what we'd target anyway, a re-encode
            // would burn 5–15 seconds of CPU for single-digit % savings —
            // often even GROWING the file once encoder overhead is added.
            // The honest move is to just copy the file. User gets a result
            // in ~50 ms and a pristine original-quality stream.
            //
            // We intentionally keep the gate tight (HEVC only, both res and
            // bitrate must match) so we never accidentally short-circuit a
            // case where the user would have seen meaningful savings.
            let sourceIsHEVC = try await videoTrack.load(.formatDescriptions).contains { desc in
                let sub = CMFormatDescriptionGetMediaSubType(desc)
                return sub == kCMVideoCodecType_HEVC || sub == kCMVideoCodecType_HEVCWithAlpha
            }
            let longestSourceEdge = max(naturalSize.width, naturalSize.height)
            let fitsTargetRes = longestSourceEdge <= level.maxResolution
            let estimatedTargetBitrate = smartBitrate(
                width: Int(naturalSize.width),
                height: Int(naturalSize.height),
                frameRate: nominalFrameRate,
                originalBitrate: estimatedDataRate,
                level: level,
                isHEVC: true
            )
            let fitsTargetBitrate = estimatedDataRate > 0
                && estimatedDataRate <= estimatedTargetBitrate * 1.10

            if sourceIsHEVC && fitsTargetRes && fitsTargetBitrate {
                let resolutionLabel: String = {
                    let longest = Int(longestSourceEdge)
                    if longest >= 3840 { return "4K" }
                    else if longest >= 1920 { return "1080p" }
                    else if longest >= 1280 { return "720p" }
                    else if longest >= 854 { return "480p" }
                    else { return "\(Int(naturalSize.width))×\(Int(naturalSize.height))" }
                }()
                try await runVideoPassThrough(
                    inputURL: inputURL,
                    originalSize: originalSize,
                    durationSeconds: totalSeconds,
                    resolutionLabel: resolutionLabel,
                    startTime: startTime
                )
                return
            }

            // Adjust the orientation transform for the new (possibly scaled) dimensions.
            // tx/ty encode positional offsets that depend on frame size, so they must
            // be scaled proportionally when the encode resolution changes.
            let dimScale: CGFloat = naturalSize.width > 0
                ? CGFloat(dims.width) / naturalSize.width
                : 1.0
            var adjustedTransform = preferredTransform
            adjustedTransform.tx *= dimScale
            adjustedTransform.ty *= dimScale

            // ── Step 4: Calculate target bitrate ──
            let safeBitrate = estimatedDataRate > 0
                ? estimatedDataRate
                : Float(originalSize * 8) / max(Float(totalSeconds), 1.0)

            let targetBitrate = smartBitrate(
                width: dims.width,
                height: dims.height,
                frameRate: nominalFrameRate,
                originalBitrate: safeBitrate,
                level: level,
                isHEVC: useHEVC
            )

            let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
            // Key frame interval: 2 seconds worth of frames
            let keyFrameInterval = Int(frameRate * 2)

            let resolutionLabel: String = {
                let longest = max(dims.width, dims.height)
                if longest >= 3840 { return "4K" }
                else if longest >= 1920 { return "1080p" }
                else if longest >= 1280 { return "720p" }
                else if longest >= 854 { return "480p" }
                else { return "\(dims.width)×\(dims.height)" }
            }()

            phase = .preparing

            // ── Step 5: Output URL ──
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("compressed_\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: outputURL)

            // Capture thread-safe state
            let state = self.shared

            // ── Steps 6-8: Setup Reader/Writer inside a scope so the raw
            //    non-Sendable locals don't leak into @Sendable closures. ──
            // Wrap non-Sendable AV types for safe capture in @Sendable closures
            struct AVBridge: @unchecked Sendable {
                let writer: AVAssetWriter
                let reader: AVAssetReader
                let videoWriterInput: AVAssetWriterInput
                let videoReaderOutput: AVAssetReaderTrackOutput
                let audioWriterInput: AVAssetWriterInput?
                let audioReaderOutput: AVAssetReaderTrackOutput?
            }

            let av: AVBridge = try {
                // ── Step 6: Setup Reader ──
                let reader = try AVAssetReader(asset: asset)

                let videoReaderOutput = AVAssetReaderTrackOutput(
                    track: videoTrack,
                    outputSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    ]
                )
                videoReaderOutput.alwaysCopiesSampleData = false

                guard reader.canAdd(videoReaderOutput) else {
                    throw CompressionError.readerSetupFailed("Cannot add video reader output.")
                }
                reader.add(videoReaderOutput)

                // Audio reader — decompress to PCM
                var audioReaderOutput: AVAssetReaderTrackOutput?
                if let audioTrack = audioTrack {
                    let pcmSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    let audioOutput = AVAssetReaderTrackOutput(
                        track: audioTrack,
                        outputSettings: pcmSettings
                    )
                    audioOutput.alwaysCopiesSampleData = false
                    if reader.canAdd(audioOutput) {
                        reader.add(audioOutput)
                        audioReaderOutput = audioOutput
                    }
                }

                // ── Step 7: Setup Writer ──
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                writer.shouldOptimizeForNetworkUse = false  // Skip moov-atom rewrite for speed

                // Video compression properties — tuned per codec
                var compressionProps: [String: Any] = [
                    AVVideoAverageBitRateKey: NSNumber(value: targetBitrate),
                    AVVideoExpectedSourceFrameRateKey: NSNumber(value: frameRate),
                    AVVideoMaxKeyFrameIntervalKey: NSNumber(value: keyFrameInterval)
                ]

                if useHEVC {
                    // HEVC-specific: Allow frame reordering for B-frames → better compression
                    compressionProps[AVVideoAllowFrameReorderingKey] = true
                } else {
                    // H.264: Use High profile for best quality
                    compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
                }

                let videoWriterSettings: [String: Any] = [
                    AVVideoCodecKey: codecType,
                    AVVideoWidthKey: dims.width,
                    AVVideoHeightKey: dims.height,
                    AVVideoCompressionPropertiesKey: compressionProps,
                    AVVideoScalingModeKey: AVVideoScalingModeResizeAspect
                ]

                let videoWriterInput = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: videoWriterSettings
                )
                videoWriterInput.expectsMediaDataInRealTime = false
                videoWriterInput.transform = adjustedTransform

                guard writer.canAdd(videoWriterInput) else {
                    throw CompressionError.writerSetupFailed("Cannot add video writer input.")
                }
                writer.add(videoWriterInput)

                // Audio writer — re-encode to AAC with level-appropriate settings
                var audioWriterInput: AVAssetWriterInput?
                if audioReaderOutput != nil {
                    let aacSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVEncoderBitRateKey: level.audioBitrate,
                        AVNumberOfChannelsKey: level.audioChannels,
                        AVSampleRateKey: 48_000.0
                    ]
                    let audioInput = AVAssetWriterInput(
                        mediaType: .audio,
                        outputSettings: aacSettings
                    )
                    audioInput.expectsMediaDataInRealTime = false
                    if writer.canAdd(audioInput) {
                        writer.add(audioInput)
                        audioWriterInput = audioInput
                    }
                }

                // ── Step 8: Start reading + writing ──
                guard writer.startWriting() else {
                    let msg = writer.error?.localizedDescription ?? "Unknown error starting writer"
                    throw CompressionError.writerSetupFailed(msg)
                }

                guard reader.startReading() else {
                    let msg = reader.error?.localizedDescription ?? "Unknown error starting reader"
                    writer.cancelWriting()
                    throw CompressionError.readerSetupFailed(msg)
                }

                writer.startSession(atSourceTime: .zero)

                return AVBridge(
                    writer: writer, reader: reader,
                    videoWriterInput: videoWriterInput, videoReaderOutput: videoReaderOutput,
                    audioWriterInput: audioWriterInput, audioReaderOutput: audioReaderOutput
                )
            }()

            // ── Step 9: Process tracks on background queues ──
            // Only `av` (Sendable bridge) is visible here — raw AV locals are out of scope.
            phase = .compressing

            // Access all AV objects through `av` (which is @unchecked Sendable)
            // so @Sendable closures only capture a Sendable value.

            let compressedURL: URL = try await withCheckedThrowingContinuation { continuation in
                let videoQueue = DispatchQueue(label: "com.beeclean.compress.video", qos: .userInteractive)
                let audioQueue = DispatchQueue(label: "com.beeclean.compress.audio", qos: .userInteractive)
                let group = DispatchGroup()

                // — Video Track —
                group.enter()
                av.videoWriterInput.requestMediaDataWhenReady(on: videoQueue) { [av] in
                    while av.videoWriterInput.isReadyForMoreMediaData {
                        if state.isCancelled {
                            av.videoWriterInput.markAsFinished()
                            group.leave()
                            return
                        }

                        guard av.writer.status == .writing else {
                            av.videoWriterInput.markAsFinished()
                            state.encounteredError = true
                            group.leave()
                            return
                        }

                        guard let sampleBuffer = av.videoReaderOutput.copyNextSampleBuffer() else {
                            av.videoWriterInput.markAsFinished()
                            group.leave()
                            return
                        }

                        // Progress — throttled to ~10 Hz, and only published
                        // when the value actually moves by >=1%, so we don't
                        // flood the main thread mid-encode.
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let currentSec = CMTimeGetSeconds(pts)
                        if totalSeconds > 0 {
                            let pct = min(Float(currentSec / totalSeconds), 0.99)
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { return }
                                let now = CACurrentMediaTime()
                                if now - self.lastProgressPublishAt < 0.1
                                    && abs(pct - self.lastPublishedProgress) < 0.01 {
                                    return
                                }
                                self.lastProgressPublishAt = now
                                self.lastPublishedProgress = pct
                                self.progress = pct
                            }
                        }

                        if !av.videoWriterInput.append(sampleBuffer) {
                            av.videoWriterInput.markAsFinished()
                            state.encounteredError = true
                            group.leave()
                            return
                        }
                    }
                }

                // — Audio Track —
                // Capture only the Sendable AVBridge in the @Sendable closure;
                // bind the (non-Sendable) audio input/output locally per loop
                // tick so we never repeatedly force-unwrap in the hot path.
                if av.audioWriterInput != nil, av.audioReaderOutput != nil {
                    group.enter()
                    let starter = av.audioWriterInput!  // safe: just-checked above; used only to schedule
                    starter.requestMediaDataWhenReady(on: audioQueue) { [av] in
                        guard let audioInput = av.audioWriterInput,
                              let audioOutput = av.audioReaderOutput else {
                            group.leave()
                            return
                        }
                        while audioInput.isReadyForMoreMediaData {
                            if state.isCancelled {
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }

                            guard av.writer.status == .writing else {
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }

                            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }

                            if !audioInput.append(sampleBuffer) {
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }

                // — Completion —
                group.notify(queue: .main) { [av] in
                    if state.isCancelled {
                        av.reader.cancelReading()
                        av.writer.cancelWriting()
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: CompressionError.cancelled)
                        return
                    }

                    if av.reader.status == .failed {
                        let msg = av.reader.error?.localizedDescription ?? "Unknown reader error"
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: CompressionError.readingFailed(msg))
                        return
                    }

                    if av.writer.status == .failed || state.encounteredError {
                        let msg = av.writer.error?.localizedDescription ?? "Writer error"
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: CompressionError.writingFailed(msg))
                        return
                    }

                    av.writer.finishWriting { [av] in
                        if av.writer.status == .completed {
                            continuation.resume(returning: outputURL)
                        } else {
                            let msg = av.writer.error?.localizedDescription ?? "Failed to finalize"
                            try? FileManager.default.removeItem(at: outputURL)
                            continuation.resume(throwing: CompressionError.writingFailed(msg))
                        }
                    }
                }
            }

            // ── Step 10: Build result ──
            let compressedSize = fileSize(at: compressedURL)
            let compressionTime = Date().timeIntervalSince(startTime)

            // Sanity: a 0-byte output means the encoder produced nothing real.
            // Treat as a failure so the user isn't told "success" with garbage.
            guard compressedSize > 0 else {
                try? FileManager.default.removeItem(at: compressedURL)
                throw CompressionError.writingFailed(
                    "Compressed video is 0 bytes — encode produced no output."
                )
            }

            // Update phase on main actor
            phase = .done
            progress = 1.0

            result = CompressionResult(
                outputURL: compressedURL,
                originalSize: originalSize,
                compressedSize: compressedSize,
                compressionTime: compressionTime,
                codec: codecName,
                outputResolution: resolutionLabel
            )

            isCompressing = false

            recordCompressionAttempt(
                success: true,
                codec: codecName,
                originalBytes: originalSize,
                compressedBytes: compressedSize,
                durationSeconds: totalSeconds,
                compressionTimeSeconds: compressionTime,
                resolution: resolutionLabel
            )

        } catch let err as CompressionError {
            phase = .failed
            error = err
            isCompressing = false
            recordCompressionAttempt(
                success: false,
                codec: "unknown",
                errorMessage: err.localizedDescription
            )
        } catch {
            phase = .failed
            self.error = .writingFailed(error.localizedDescription)
            isCompressing = false
            recordCompressionAttempt(
                success: false,
                codec: "unknown",
                errorMessage: error.localizedDescription
            )
        }
    }

}

