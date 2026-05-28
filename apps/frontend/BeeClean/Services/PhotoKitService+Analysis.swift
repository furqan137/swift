import Foundation
import Photos

extension PhotoKitService {
    // MARK: - Main Analysis Function
    func analyzePhotos(limit: Int = 500) async {
        guard !isAnalyzing else { return }

        // Check authorization
        if authorizationStatus != .authorized && authorizationStatus != .limited {
            let granted = await requestAuthorization()
            if !granted {
                analysisProgress.error = "Photo library access denied"
                return
            }
        }

        isAnalyzing = true
        analyzedPhotos = []
        analysisProgress = PhotoAnalysisProgress()
        analysisProgress.currentPhase = "Fetching photos..."

        // Fetch photos on background thread
        let fetchResult = await Task.detached { [weak self] in
            return self?.fetchAllPhotos(limit: limit)
        }.value

        guard let fetchResult = fetchResult else {
            isAnalyzing = false
            return
        }

        let totalCount = fetchResult.count

        analysisProgress.totalPhotos = totalCount
        analysisProgress.currentPhase = "Analyzing \(totalCount) photos..."

        if totalCount == 0 {
            analysisProgress.isComplete = true
            analysisProgress.currentPhase = "No photos found"
            isAnalyzing = false
            return
        }

        // Process in batches
        let batchSize = 20
        var allAnalyzed: [AnalyzedPhoto] = []

        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalCount)

            // Process batch on background thread
            let batchResults = await processBatch(
                fetchResult: fetchResult,
                startIndex: batchStart,
                endIndex: batchEnd
            )

            allAnalyzed.append(contentsOf: batchResults)

            // Update progress
            analysisProgress.processedPhotos = batchEnd
            analysisProgress.currentPhase = "Analyzed \(batchEnd)/\(totalCount) photos"
            analyzedPhotos = allAnalyzed

            // Allow UI updates
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        analysisProgress.isComplete = true
        analysisProgress.currentPhase = "Complete! Analyzed \(totalCount) photos"
        isAnalyzing = false
    }

    // MARK: - Batch Processing
    func processBatch(
        fetchResult: PHFetchResult<PHAsset>,
        startIndex: Int,
        endIndex: Int
    ) async -> [AnalyzedPhoto] {
        let analyzer = self.analyzer
        var results: [AnalyzedPhoto] = []

        for index in startIndex..<endIndex {
            let asset = fetchResult.object(at: index)
            let analyzed = await analyzer.analyzeAsset(asset)
            results.append(analyzed)
        }

        return results
    }

    // MARK: - Find Similar Photos
    func findSimilarPhotos(threshold: Int = 10) -> [[AnalyzedPhoto]] {
        var groups: [[AnalyzedPhoto]] = []
        var processed = Set<String>()

        for photo in analyzedPhotos {
            guard !processed.contains(photo.id) else { continue }

            var similarGroup = [photo]
            processed.insert(photo.id)

            for other in analyzedPhotos {
                guard !processed.contains(other.id) else { continue }

                let distance = PhotoAnalyzer.hammingDistance(photo.dHash64, other.dHash64)
                if distance <= threshold {
                    similarGroup.append(other)
                    processed.insert(other.id)
                }
            }

            if similarGroup.count > 1 {
                groups.append(similarGroup)
            }
        }

        return groups
    }

    // MARK: - Find Blurry Photos
    func findBlurryPhotos(threshold: Double = 100) -> [AnalyzedPhoto] {
        return analyzedPhotos.filter { $0.sharpnessScore < threshold }
    }

    // MARK: - Cancel Analysis
    func cancelAnalysis() {
        isAnalyzing = false
        analysisProgress.currentPhase = "Cancelled"
    }

}
