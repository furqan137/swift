import Foundation
import Photos
import CoreLocation
import MapKit

extension AIService {
    // MARK: - Location Search

    /// Forward-geocode a place name and filter photos within 10km radius.
    func fetchByLocation(query: String, limit: Int) async -> [String] {
        guard !query.isEmpty else { return [] }

        // Forward geocode the query string
        let target: CLLocationCoordinate2D
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(query)
            guard let coord = placemarks.first?.location?.coordinate else { return [] }
            target = coord
        } catch {
            return []
        }

        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let radiusMeters: Double = 10_000 // 10km

        // Fetch all photos and filter by GPS proximity
        return await Task.detached {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: .image, options: options)

            var matches: [(id: String, distance: Double)] = []
            result.enumerateObjects { asset, _, _ in
                guard let assetLocation = asset.location else { return }
                let distance = assetLocation.distance(from: targetLocation)
                if distance <= radiusMeters {
                    matches.append((id: asset.localIdentifier, distance: distance))
                }
            }

            matches.sort { $0.distance < $1.distance }
            return Array(matches.prefix(limit).map(\.id))
        }.value
    }

    // MARK: - On-Device Search Helpers

    nonisolated static func fetchByDate(dateRange: AIDateRange?, limit: Int) -> [String] {
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
            // Include the full end day
            if let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: endDate) {
                predicates.append(NSPredicate(format: "creationDate < %@", endOfDay as NSDate))
            }
        }

        // If no date range at all, show last 7 days
        if predicates.isEmpty {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            predicates.append(NSPredicate(format: "creationDate >= %@", weekAgo as NSDate))
        }

        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let result = PHAsset.fetchAssets(with: options)
        var ids: [String] = []
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    nonisolated static func fetchLargest(mediaType: String?, limit: Int) -> [String] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if mediaType == "video" {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        } else if mediaType == "photo" {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }

        let result = PHAsset.fetchAssets(with: options)
        var assetsWithSize: [(id: String, size: Int64)] = []

        result.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let size = resources.first.flatMap { $0.value(forKey: "fileSize") as? Int64 } ?? 0
            assetsWithSize.append((id: asset.localIdentifier, size: size))
        }

        assetsWithSize.sort { $0.size > $1.size }
        return Array(assetsWithSize.prefix(limit).map(\.id))
    }

}
