import Foundation
import Photos
import Vision

extension AIService {
    // MARK: - Vision Content Search

    /// Maps user-friendly search terms to Apple Vision classifier labels they should match.
    /// VNClassifyImageRequest uses a fixed taxonomy (e.g. "espresso", "cup_or_mug") that
    /// doesn't always match how people describe things ("coffee", "drink").
    private nonisolated static let synonymMap: [String: Set<String>] = [
        "coffee":    ["espresso", "cup", "mug", "coffee mug", "cup or mug", "latte", "cappuccino", "mocha", "drink", "beverage", "cafe", "coffeehouse", "coffee shop"],
        "tea":       ["cup", "mug", "cup or mug", "teapot", "drink", "beverage", "tea"],
        "food":      ["pizza", "burrito", "sandwich", "salad", "soup", "sushi", "meal", "plate", "dining", "restaurant", "dish", "dessert", "cake", "bread", "fruit", "meat", "rice", "food", "grocery", "kitchen"],
        "dog":       ["dog", "puppy", "canine", "labrador", "golden retriever", "german shepherd", "poodle", "bulldog", "terrier", "husky", "beagle", "corgi", "animal"],
        "cat":       ["cat", "kitten", "tabby", "persian", "siamese", "feline", "animal"],
        "car":       ["car", "sedan", "suv", "truck", "vehicle", "sports car", "convertible", "minivan", "pickup", "automobile", "parking"],
        "flower":    ["flower", "rose", "daisy", "tulip", "sunflower", "bouquet", "blossom", "petal", "plant", "garden", "floral"],
        "sunset":    ["sunset", "sunrise", "sky", "horizon", "dusk", "dawn", "golden hour", "cloud", "sun"],
        "beach":     ["beach", "ocean", "sea", "sand", "coast", "shore", "wave", "surfing", "seashore", "tropical"],
        "mountain":  ["mountain", "hill", "peak", "cliff", "valley", "ridge", "hiking", "trail", "landscape"],
        "tree":      ["tree", "forest", "woods", "palm", "oak", "pine", "branch", "leaf", "plant", "nature"],
        "baby":      ["baby", "infant", "toddler", "child", "newborn"],
        "drink":     ["drink", "beverage", "cocktail", "wine", "beer", "juice", "smoothie", "cup", "glass", "bottle", "espresso", "latte", "bar"],
        "book":      ["book", "reading", "library", "novel", "magazine", "text", "bookshelf"],
        "snow":      ["snow", "winter", "ice", "frost", "blizzard", "skiing", "snowboard", "cold"],
        "rain":      ["rain", "rainy", "storm", "umbrella", "wet", "puddle", "cloud"],
        "party":     ["party", "celebration", "birthday", "cake", "balloon", "confetti", "gathering", "festival"],
        "gym":       ["gym", "workout", "exercise", "fitness", "weight", "dumbbell", "treadmill", "sport"],
        "pizza":     ["pizza", "pepperoni", "cheese", "slice", "food", "meal", "italian"],
        "cake":      ["cake", "dessert", "frosting", "birthday", "bakery", "pastry", "cupcake", "sweet"],
        "nature":    ["nature", "landscape", "outdoor", "forest", "mountain", "lake", "river", "park", "tree", "green"],
        "water":     ["water", "ocean", "sea", "lake", "river", "pool", "waterfall", "wave"],
        "sky":       ["sky", "cloud", "sunset", "sunrise", "blue", "atmosphere"],
        "night":     ["night", "dark", "moon", "star", "evening", "nighttime", "city light"],
        "city":      ["city", "building", "skyline", "urban", "downtown", "street", "architecture", "skyscraper"],
    ]

    /// Expand query terms with synonym matches from the Vision classifier taxonomy.
    nonisolated static func expandTerms(_ terms: [String]) -> Set<String> {
        var expanded = Set(terms)
        for term in terms {
            if let synonyms = synonymMap[term] {
                expanded.formUnion(synonyms)
            }
        }
        return expanded
    }

    nonisolated static func fetchByContent(query: String, dateRange: AIDateRange?, limit: Int) async -> [String] {
        // Always search a broad window for the on-device fallback — the AI often adds
        // a narrow dateRange even when the user didn't mention one, which kills results.
        // We ignore the AI's dateRange for candidate selection and search the most recent
        // photos. If the AI did supply a date range we'll boost matches inside it.
        let candidateAssets = fetchAssetsByDate(dateRange: nil, limit: 2000)
        print("[AISearch] Content search for \"\(query)\" — \(candidateAssets.count) candidates")

        let stopWords: Set<String> = [
            "my", "the", "a", "an", "of", "from", "with", "in", "on", "at", "to", "for",
            "find", "show", "get", "pictures", "photos", "images", "me", "i", "that", "those",
            "some", "all", "any", "this", "these", "took", "taken", "please", "can", "you"
        ]
        let rawTerms = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }

        guard !rawTerms.isEmpty else {
            return Array(candidateAssets.prefix(limit).map { $0.localIdentifier })
        }

        // Expand with synonyms so "coffee" also matches Vision labels like "espresso", "cup_or_mug"
        let queryTerms = expandTerms(rawTerms)
        print("[AISearch] Expanded terms: \(queryTerms.sorted())")

        // Score candidates with controlled concurrency.
        //
        // Previously this used `DispatchQueue.concurrentPerform` + a
        // semaphore + an NSLock around `scoreAsset`, where `scoreAsset`
        // itself called `requestImage(isSynchronous: true)`. On a
        // 4500-photo library with iCloud-optimized assets, every one
        // of those synchronous calls blocked a GCD thread waiting on
        // the network round-trip — `concurrentPerform` allocates a
        // bounded set of threads, so once 4 of them were stuck on
        // iCloud the search hung for tens of seconds and tripped the
        // app's watchdog.
        //
        // The async refactor:
        //   • `scoreAsset` is now async. The PHImageManager callback is
        //     bridged via `withCheckedContinuation` + `ResumeOnce` so
        //     opportunistic delivery (degraded → full) doesn't double-
        //     resume the continuation (Swift hard-traps on that).
        //   • A `TaskGroup` with a concurrency ceiling of 4 replaces
        //     the semaphore. Suspended tasks don't pin threads, so a
        //     slow iCloud download holds zero scheduler resources while
        //     it waits — the other slots stay free for fast assets.
        //   • The lock-protected results array becomes a per-task
        //     return value collected in the group's `next()` loop.
        let concurrency = min(4, candidateAssets.count)
        var items: [(id: String, score: Double)] = []
        var failCount = 0
        items.reserveCapacity(candidateAssets.count)

        await withTaskGroup(of: (id: String, score: Double).self) { group in
            var iterator = candidateAssets.makeIterator()
            // Prime the group with `concurrency` initial tasks.
            for _ in 0..<concurrency {
                guard let asset = iterator.next() else { break }
                group.addTask {
                    let score = await scoreAsset(asset: asset, queryTerms: queryTerms)
                    return (asset.localIdentifier, score)
                }
            }
            // As each completes, queue the next so we always have at
            // most `concurrency` in flight.
            while let result = await group.next() {
                if result.score > 0 {
                    items.append(result)
                } else if result.score < 0 {
                    failCount += 1
                }
                if let asset = iterator.next() {
                    group.addTask {
                        let score = await scoreAsset(asset: asset, queryTerms: queryTerms)
                        return (asset.localIdentifier, score)
                    }
                }
            }
        }

        items.sort { $0.score > $1.score }
        print("[AISearch] Results: \(items.count) matches, \(failCount) failed to load image")
        if let top = items.first {
            print("[AISearch] Top score: \(String(format: "%.4f", top.score))")
        }
        return Array(items.prefix(limit).map(\.id))
    }

    /// Fetch PHAsset objects (not just IDs) by date range, for direct classification.
    nonisolated static func fetchAssetsByDate(dateRange: AIDateRange?, limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        var predicates: [NSPredicate] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        if let start = dateRange?.start, let startDate = formatter.date(from: start) {
            predicates.append(NSPredicate(format: "creationDate >= %@", startDate as NSDate))
        }
        if let end = dateRange?.end, let endDate = formatter.date(from: end) {
            if let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate) {
                predicates.append(NSPredicate(format: "creationDate < %@", endOfDay as NSDate))
            }
        }

        // Images only for content search (skip videos)
        predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))

        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    /// Score a photo against query terms using VNClassifyImageRequest + OCR.
    /// Returns > 0 for matches, 0 for no match, -1 if the image couldn't be loaded.
    ///
    /// Async variant of the previous synchronous scoring path. The
    /// PHImageManager.requestImage callback is bridged via
    /// `withCheckedContinuation` + a one-shot resume guard so
    /// opportunistic delivery (degraded → full callbacks) doesn't
    /// double-resume the continuation (Swift hard-traps on that).
    /// A suspended scoreAsset doesn't pin a thread while it waits on
    /// an iCloud download — that's the whole point of moving off
    /// `isSynchronous: true`.
    nonisolated static func scoreAsset(asset: PHAsset, queryTerms: Set<String>) async -> Double {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        // CRITICAL: allow network so iCloud-optimized photos can download thumbnails.
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // Race the image request against a 20-second timeout to prevent
        // indefinite hangs on slow iCloud downloads. Content search has
        // a shorter timeout (20s vs 30s for indexing) because users are
        // actively waiting for results.
        let cgImageOpt: CGImage? = await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                // PHImageManager can deliver multiple callbacks (degraded then
                // final). `ResumeOnce` ensures the continuation resumes
                // exactly once — Swift traps on a second resume.
                let resumed = ResumeOnce()
                return await withCheckedContinuation { continuation in
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: CGSize(width: 299, height: 299),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, info in
                        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        // Wait for the final non-degraded callback. With
                        // `.highQualityFormat` we usually get a single final
                        // callback, but `.opportunistic` semantics still apply
                        // for some asset types — this guard is the same
                        // pattern PhotoAnalyzer.swift already uses.
                        if isDegraded { return }
                        guard resumed.tryClaim() else { return }
                        if image == nil, let err = info?[PHImageErrorKey] as? NSError {
                            BCLog.debug("[AISearch] Image load failed for \(asset.localIdentifier): \(err.localizedDescription)")
                        }
                        continuation.resume(returning: image?.cgImage)
                    }
                }
            }

            // Timeout task - fires after 20 seconds
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }

            // Return the first result (either image or timeout)
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }

        guard let cgImage = cgImageOpt else { return -1 }

        var totalScore: Double = 0

        // 1. VNClassifyImageRequest — scene/object classification.
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([classifyRequest])
            if let results = classifyRequest.results {
                #if DEBUG
                if asset.localIdentifier.hashValue % 50 == 0 {
                    let top5 = results.prefix(5).map { "\($0.identifier): \(String(format: "%.3f", $0.confidence))" }
                    BCLog.debug("[AISearch] Labels for \(asset.localIdentifier.prefix(20)): \(top5.joined(separator: ", "))")
                }
                #endif
                for obs in results {
                    // Normalize: "cup_or_mug" → "cup or mug"
                    let rawLabel = obs.identifier.lowercased()
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")

                    var matched = false
                    for term in queryTerms {
                        if rawLabel.contains(term) || term.contains(rawLabel) {
                            matched = true
                            break
                        }
                    }
                    if !matched {
                        let words = rawLabel.components(separatedBy: " ")
                            .filter { $0.count > 2 && $0 != "or" && $0 != "and" }
                        for word in words {
                            if queryTerms.contains(word) {
                                matched = true
                                break
                            }
                        }
                    }
                    if matched {
                        totalScore += Double(obs.confidence)
                    }
                }
            }
        } catch {
            BCLog.debug("[AISearch] VNClassify failed: \(error.localizedDescription)")
        }

        // 2. VNRecognizeTextRequest — OCR for text in the photo.
        //    Catches brand names, signs, labels (e.g. "Starbucks" on a
        //    coffee cup).
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let textHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try textHandler.perform([textRequest])
            if let textResults = textRequest.results {
                let detectedText = textResults
                    .compactMap { $0.topCandidates(1).first?.string.lowercased() }
                    .joined(separator: " ")
                if !detectedText.isEmpty {
                    for term in queryTerms {
                        if detectedText.contains(term) {
                            // OCR match is a strong signal.
                            totalScore += 0.5
                        }
                    }
                }
            }
        } catch {
            BCLog.debug("[AISearch] VNRecognizeText failed: \(error.localizedDescription)")
        }

        return totalScore
    }

    func buildConversationHistory() -> [AIConversationEntry]? {
        let relevant = messages.suffix(20).filter { $0.role == .user || $0.role == .assistant }
        guard !relevant.isEmpty else { return nil }
        // Exclude the last user message (it's sent as `message`)
        let historyMessages = relevant.dropLast()
        guard !historyMessages.isEmpty else { return nil }
        return historyMessages.map {
            AIConversationEntry(role: $0.role.rawValue, content: $0.content)
        }
    }

    func buildContext() async -> AIContext {
        let photoKit = PhotoKitService.shared
        let stats = await Task.detached { () -> (Int, Int, Int, Int64) in
            let photos = photoKit.fetchAllPhotos()
            let videos = photoKit.fetchAllVideos()
            let screenshots = photoKit.fetchScreenshots()

            // Sum video bytes for storage estimate
            var totalBytes: Int64 = 0
            videos.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                if let size = resources.first?.value(forKey: "fileSize") as? Int64 {
                    totalBytes += size
                }
            }

            return (photos.count, videos.count, screenshots.count, totalBytes)
        }.value

        let (photoCount, videoCount, screenshotCount, videoBytes) = stats
        let storageMB = Int(videoBytes / (1024 * 1024))

        // Pull cleanup stats from persistence directly
        let summary = SimilarPersistence.loadScanSummary()

        return AIContext(
            totalPhotos: photoCount,
            totalVideos: videoCount,
            totalScreenshots: screenshotCount,
            storageUsedMB: storageMB > 0 ? storageMB : nil,
            duplicateGroupsCount: summary.duplicateGroupsCount > 0 ? summary.duplicateGroupsCount : nil,
            duplicateToCleanCount: summary.duplicateToCleanCount > 0 ? summary.duplicateToCleanCount : nil,
            similarGroupsCount: summary.similarGroupsCount > 0 ? summary.similarGroupsCount : nil,
            screenRecordingCount: summary.screenRecordingCount > 0 ? summary.screenRecordingCount : nil,
            screenRecordingTotalBytes: summary.screenRecordingTotalBytes > 0 ? Int(summary.screenRecordingTotalBytes) : nil,
            shortVideoCount: summary.shortVideoCount > 0 ? summary.shortVideoCount : nil,
            shortVideoTotalBytes: summary.shortVideoTotalBytes > 0 ? Int(summary.shortVideoTotalBytes) : nil,
            capabilities: AICapabilities(
                canSearchByPerson: false,
                canSearchByDate: true,
                canSearchByLocation: true,
                canFindDuplicates: true,
                canFindLargeFiles: true
            )
        )
    }
}
