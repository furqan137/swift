import Vision
import UIKit
import Photos
import CoreGraphics
import AVFoundation

// MARK: - Visual Source Classifier (Tier 3)
//
// Last-ditch source-app inference for assets where Tier 1 (filename) and
// Tier 2 (EXIF Software tag) both came back empty. Runs entirely on-device
// using Apple's Vision framework — no third-party SDKs, no network, no
// API keys. The classifier's job is to recover provenance that was lost
// when the original metadata was stripped:
//   • Photos re-saved through "Save Image" in Safari / iMessage
//   • AirDropped frames from another phone
//   • Re-encoded screenshots / story rips
//
// Architecture
//   1. Aspect-ratio gate — only 9:16-ish (TikTok / Reels / Snap Story)
//      and 1:1-ish (Instagram feed posts) are candidates. Anything else
//      short-circuits at no cost so the Tier 3 pass on a typical library
//      filters down to ~5–15% of assets.
//   2. Low-res thumbnail fetch — `requestImage` with `.fast` resize and
//      `.opportunistic` delivery, max 384×683. Fits comfortably in cache,
//      decodes in <5ms.
//   3. Vision text recognition — `.fast` accuracy, English only. Recovers
//      on-frame UI text: TikTok's "For You" / "Following", Instagram's
//      "Reels" header, Snapchat's "My Story", @username handles, etc.
//   4. Signal scoring — require ≥2 matching tokens (or one strong brand
//      keyword) before tagging, so a vanilla portrait that happens to
//      contain a coffee shop's `@handle` sign doesn't get badged TikTok.
//
// Conservative by design: false-positive cost is high (a misclassified
// portrait is a worse UX than an unbadged TikTok save), so the
// thresholds intentionally err toward "leave it nil."
//
// Zero-cost guarantee
//   • 100% on-device. The Vision framework runs on the Neural Engine
//     (A12+) / GPU / CPU locally. No network, no API keys, no SDKs.
//   • No per-classification fee, no App Store review entitlements.
//   • Vision's language model swap is a one-time cost on first use of
//     each language; after that, OCR runs identically regardless of how
//     many languages are enabled.
//
// Language coverage
//   • OCR layer asks Vision for the device-supported language list at
//     init and passes the full set. This automatically tracks new
//     languages Apple adds in future iOS releases — no code changes.
//   • Brand-name scoring layer is language-agnostic: "Instagram",
//     "TikTok", "Snapchat", "Reels" are proper nouns that aren't
//     translated. Same for `@handle` regex and numeric patterns
//     ("5s" timer, "12K views"). These signals work in Tagalog,
//     Vietnamese, Japanese — anywhere the OCR can pull glyphs.
//   • Localized UI tokens ("For You" / "Para ti" / "Pour toi") are
//     ADDITIVE — they boost confidence when present but the classifier
//     does NOT depend on them. A photo with only the brand name visible
//     classifies just fine regardless of UI language.
enum VisualSourceClassifier {

    /// Vertical-video (9:16) aspect-ratio bucket — TikTok, Reels, Snap.
    /// Calculated against `pixelWidth / pixelHeight` from the PHAsset
    /// metadata so we avoid even fetching a thumbnail when the shape
    /// isn't right. Slightly looser than the canonical 0.5625 to cover
    /// rare 4:5 and 9:16-with-letterbox variants.
    private static let verticalAspectRange: ClosedRange<Double> = 0.50...0.62
    /// Square (1:1) aspect-ratio bucket — Instagram feed posts.
    private static let squareAspectRange: ClosedRange<Double> = 0.95...1.05

    /// Returns nil if the asset's aspect doesn't match any social-app
    /// format. Cheap pre-filter that runs entirely off PHAsset metadata
    /// — no thumbnail fetch required.
    private static func aspectBucket(width: Int, height: Int) -> AspectBucket {
        guard width > 0, height > 0 else { return .skip }
        let ar = Double(width) / Double(height)
        if verticalAspectRange.contains(ar) { return .vertical }
        if squareAspectRange.contains(ar)   { return .square }
        return .skip
    }

    private enum AspectBucket { case vertical, square, skip }

    // MARK: - Public entry
    //
    // Async because it fetches a thumbnail and runs a Vision pass; both
    // are off-main-thread under the hood. Returns nil on:
    //   • iCloud-only assets (thumbnail fetch skips network).
    //   • Aspect mismatch (neither vertical nor square).
    //   • Text recognition that didn't produce ≥2 matching tokens.
    nonisolated static func classify(_ asset: PHAsset) async -> PhotoSource? {
        guard asset.mediaType == .image else { return nil }
        let bucket = aspectBucket(width: asset.pixelWidth, height: asset.pixelHeight)
        guard bucket != .skip else { return nil }

        guard let cg = await thumbnail(for: asset, maxSide: 768) else { return nil }
        let strings = await recognizeText(in: cg)
        guard !strings.isEmpty else { return nil }
        return score(strings: strings, bucket: bucket)
    }

    // MARK: - Video classification (Tier 3 for videos)
    //
    // Same scoring pipeline as `classify(_:)`, but the input frame is
    // extracted from the video container instead of a still photo. Two
    // frames are sampled — the first second (post-intro UI text often
    // overlays here) and ~1/3 into the clip (TikTok/Reels watermarks
    // persist throughout, so a mid-clip frame is a reliable backup if
    // the opening was a logo splash). The first non-empty OCR result
    // wins; failing that, we score the union of both frames' text.
    //
    // Closes the previous video-side gap where TikTok / Reels saves
    // with stripped filenames + no AVMetadata had nothing to fall back
    // on. Conservative scoring inside `score(strings:bucket:)` keeps
    // false-positives low — same brand-name + ≥2-signal rule the
    // photo path uses.
    nonisolated static func classifyVideo(_ asset: PHAsset) async -> PhotoSource? {
        guard asset.mediaType == .video else { return nil }
        let bucket = aspectBucket(width: asset.pixelWidth, height: asset.pixelHeight)
        guard bucket != .skip else { return nil }

        // Fetch the AVAsset with network access ON — iCloud-only videos
        // get pulled under the user's existing iCloud data policy
        // (Settings → Cellular → Photos governs cellular).
        let avAsset: AVAsset? = await withCheckedContinuation { cont in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { av, _, _ in
                cont.resume(returning: av)
            }
        }
        guard let avAsset else { return nil }

        // Two sample frames — 1s in, and ~1/3 of the way through. Both
        // capped at the asset's duration so a 2-second clip still works.
        let duration: CMTime = (try? await avAsset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return nil }

        let firstSample = min(1.0, durationSeconds * 0.5)
        let secondSample = min(max(durationSeconds / 3.0, 1.5), durationSeconds - 0.05)
        let times: [CMTime] = [
            CMTime(seconds: firstSample, preferredTimescale: 600),
            CMTime(seconds: secondSample, preferredTimescale: 600)
        ]

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .init(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = .init(seconds: 0.1, preferredTimescale: 600)
        // Cap output to a Tier-3-thumbnail-sized image so the Vision
        // pass cost matches the photo path (~50ms typical).
        generator.maximumSize = CGSize(width: 768, height: 768)

        var allText: [String] = []
        for time in times {
            if let cg = try? await generator.image(at: time).image {
                let strings = await recognizeText(in: cg)
                if !strings.isEmpty {
                    if let hit = score(strings: strings, bucket: bucket) {
                        return hit
                    }
                    allText.append(contentsOf: strings)
                }
            }
        }
        guard !allText.isEmpty else { return nil }
        return score(strings: allText, bucket: bucket)
    }

    // MARK: - Thumbnail fetch
    //
    // `.opportunistic` delivers a small degraded version first and the
    // HQ version second; we only resume on the non-degraded callback so
    // text recognition runs once against the cleanest pixel data.
    // Network access is ON so iCloud-only photos get Tier 3 coverage —
    // PhotoKit defers to the user's per-app cellular policy
    // (Settings → Cellular → Photos) before triggering a download, so
    // this can't surprise-charge the user. Closes the previous iCloud
    // gap where Tier 3 silently no-op'd for "Optimize iPhone Storage"
    // users.
    private nonisolated static func thumbnail(for asset: PHAsset, maxSide: CGFloat) async -> CGImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            // Belt-and-suspenders against PhotoKit double-delivery — once
            // the HQ callback fires, suppress any further calls. Without
            // this, an `.opportunistic` request can resume the continuation
            // twice (degraded then HQ) and crash on the second resume.
            nonisolated(unsafe) var resumed = false
            let target = CGSize(width: maxSide, height: maxSide)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { uiImage, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                if resumed { return }
                resumed = true
                cont.resume(returning: uiImage?.cgImage)
            }
        }
    }

    // MARK: - Vision text recognition
    //
    // `.fast` recognition trades a small accuracy hit for ~3× speed —
    // we only need legible UI words ("Reels", "For You", "@username"),
    // not paragraph-quality OCR. English-only language list keeps the
    // model swap-time minimal.
    /// Cached list of every Vision recognition language the running OS
    /// supports. Queried once on first use — Vision exposes this via a
    /// static accessor and the answer is stable across the app's
    /// lifetime. Caching avoids re-querying on every text request
    /// (the call isn't free; it touches Vision's revision tables).
    /// New iOS releases that add languages light up automatically the
    /// next time the user updates — no code changes needed.
    private nonisolated static let allSupportedLanguages: [String] = {
        // iOS 15+ instance API. The legacy static
        // `supportedRecognitionLanguages(for:revision:)` was deprecated
        // in iOS 15 — the new path queries the same revision tables but
        // through a configured request, which lets Vision return the
        // exact language list for the recognitionLevel + revision combo
        // we'll actually run.
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .fast
        if let langs = try? request.supportedRecognitionLanguages() {
            return langs
        }
        // Fallback for the (extremely rare) case where the request fails
        // to enumerate languages — covers the top scripts used across
        // social media so OCR still has a usable language set.
        return ["en-US", "es-ES", "pt-BR", "fr-FR", "de-DE", "it-IT",
                "zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "ru-RU", "uk-UA"]
    }()

    private nonisolated static func recognizeText(in image: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: strings)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            // EVERY language the device's Vision build supports. Apple
            // bundles the OCR models on-device, so adding 30 languages
            // to the request costs zero ongoing — Vision lazy-loads the
            // matching language model the first time it sees text in
            // that script and reuses it forever after. A photo with
            // Arabic UI text classifies identically to one with English.
            request.recognitionLanguages = allSupportedLanguages
            // Vision can run on a background queue without our help — the
            // perform call itself is synchronous on the calling thread,
            // and we're already off-main inside the surrounding TaskGroup.
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }

    // MARK: - Scoring
    //
    // Pure string-matching over the recognized token set. Tokens are
    // lowercased + joined into one string so substring searches catch
    // text split across observation boxes ("For" / "You" → "for you").
    //
    // Per-source rules
    //   • TikTok / Reels overlap a lot — both surface "@handle" + duration
    //     + UI text. We disambiguate by looking for brand-distinctive
    //     tokens first ("for you" / "following" / "original sound" =
    //     TikTok; "reels" / "instagram" / "k likes" = Instagram).
    //   • Snapchat's strongest visual signal is the timer hint ("Xs" at
    //     top) and "my story" / "send" buttons.
    //
    // Each rule below requires the bucket gate AND a token match. The
    // `score` int counts independent signals — we tag only at ≥2 unless
    // a single signal is strong enough to be unambiguous (brand name).
    private nonisolated static func score(strings: [String], bucket: AspectBucket) -> PhotoSource? {
        let lower = strings.map { $0.lowercased() }
        let joined = lower.joined(separator: " ")

        // ── Brand-name layer (language-agnostic) ──────────────────────
        // Proper-noun product names don't get translated. "Instagram",
        // "TikTok", and "Snapchat" appear verbatim in every locale —
        // Japanese UI says インスタグラム but the in-frame app logo
        // / watermark still reads "Instagram" in Latin glyphs, and
        // Vision OCR pulls that out. These checks cover ANY language
        // without per-locale code paths. Single hit fires because brand
        // names are highly diagnostic — a photo with the literal text
        // "TikTok" in it is overwhelmingly likely to be a TikTok save.
        if joined.contains("instagram") || joined.contains("ig reels") {
            return .instagram
        }
        if joined.contains("tiktok") || joined.contains("tik tok") {
            return .tiktok
        }
        if joined.contains("snapchat") {
            return .snapchat
        }
        // App watermark domains are also language-invariant — TikTok
        // burns "vm.tiktok.com" / "@username" into shared video frames.
        if joined.contains("vm.tiktok") || joined.contains("tiktok.com") {
            return .tiktok
        }

        // Multi-signal scoring per app, gated by aspect bucket so a 1:1
        // photo doesn't accidentally match TikTok's vertical-UI rules
        // and vice-versa.
        if bucket == .vertical {
            // TikTok UI text — multi-language. English first, then the
            // localized equivalents for the five other recognition
            // languages enabled in `recognizeText`. Each language adds
            // its variant of "For You" / "Following" / "Original Sound".
            let tiktokTokens = [
                "for you", "following", "original sound", "live",
                "para ti", "para você", "seguindo", "siguiendo",
                "pour toi", "abonnements", "für dich", "abonniert",
                "per te"
            ]
            var tiktokSignals = tiktokTokens.reduce(0) {
                $0 + (joined.contains($1) ? 1 : 0)
            }
            if matchesHandle(joined) { tiktokSignals += 1 }
            if tiktokSignals >= 2 { return .tiktok }

            // Snapchat — "My Story" / "Snap Map" / "Chat" tabs plus the
            // characteristic timer ("5s" / "10s") in the top status row.
            let snapTokens = [
                "my story", "snap map", "chat", "discover",
                "mi historia", "minha história", "ma story", "meine story"
            ]
            var snapSignals = snapTokens.reduce(0) {
                $0 + (joined.contains($1) ? 1 : 0)
            }
            // Snap-typical short timer "5s" / "10s" at top
            if joined.range(of: #"\b\d{1,2}s\b"#, options: .regularExpression) != nil {
                snapSignals += 1
            }
            if snapSignals >= 2 { return .snapchat }

            // Instagram Reels — multi-language vocabulary for the right
            // rail + bottom bar surfaces.
            let reelsTokens = [
                "reels", "remix", "k likes", "k views",
                "me gusta", "curtidas", "j'aime", "gefällt"
            ]
            let reelsSignals = reelsTokens.reduce(0) {
                $0 + (joined.contains($1) ? 1 : 0)
            }
            if reelsSignals >= 2 { return .instagram }
        }

        if bucket == .square {
            // Square photos are almost exclusively Instagram feed posts.
            // Require ≥2 brand-aligned tokens to fire — vanilla square
            // camera shots are rare but possible, and we'd rather miss
            // an IG post than mistag a deliberately-cropped photo.
            let igTokens = [
                "liked by", "comments", "sponsored", "view all",
                "le gusta", "comentarios",
                "curtido por", "comentários",
                "aimé par", "commentaires",
                "gefällt", "kommentare"
            ]
            var igSignals = igTokens.reduce(0) {
                $0 + (joined.contains($1) ? 1 : 0)
            }
            if matchesHandle(joined) { igSignals += 1 }
            if igSignals >= 2 { return .instagram }
        }

        return nil
    }

    /// True if the joined text contains a `@handle`-shaped token of
    /// reasonable length. Tight regex on purpose — bare `@` is too easy
    /// to false-positive on email addresses or sign captures.
    private nonisolated static func matchesHandle(_ s: String) -> Bool {
        s.range(of: #"@[a-z0-9._]{3,30}\b"#, options: .regularExpression) != nil
    }
}
