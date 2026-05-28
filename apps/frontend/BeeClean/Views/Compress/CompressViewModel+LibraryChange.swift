import Foundation
import Photos

extension CompressViewModel {

    /// Reconciles `photos` and `videos` against the live PHAsset table. Any
    /// localIdentifier the system can't resolve has been deleted somewhere
    /// (in-app, Photos.app, iCloud sync, Recently Deleted purge) and is
    /// removed from the grid.
    ///
    /// Lag note: `PHAsset.fetchAssets(withLocalIdentifiers:)` is a
    /// synchronous Core Data round-trip whose cost scales with the
    /// number of identifiers. With a 5k+ asset library it can stall
    /// the @MainActor for several hundred ms — exactly the kind of
    /// hitch the user feels when they tab away from Photos.app and
    /// come back to BeeClean. We hop the fetch into a detached task
    /// so the main thread never blocks; the prune diff + assignment
    /// hops back to MainActor for the @Published writes.
    func pruneDeletedAssetsFromGrid() {
        let photoIDs = photos.map(\.id)
        let videoIDs = videos.map(\.id)
        guard !photoIDs.isEmpty || !videoIDs.isEmpty else { return }

        Task { [weak self] in
            let stillAlive: Set<String> = await Task.detached(priority: .utility) {
                var alive = Set<String>()
                if !photoIDs.isEmpty {
                    let r = PHAsset.fetchAssets(withLocalIdentifiers: photoIDs, options: nil)
                    r.enumerateObjects { asset, _, _ in alive.insert(asset.localIdentifier) }
                }
                if !videoIDs.isEmpty {
                    let r = PHAsset.fetchAssets(withLocalIdentifiers: videoIDs, options: nil)
                    r.enumerateObjects { asset, _, _ in alive.insert(asset.localIdentifier) }
                }
                return alive
            }.value

            await MainActor.run {
                guard let self else { return }
                let prunedPhotos = self.photos.filter { stillAlive.contains($0.id) }
                let prunedVideos = self.videos.filter { stillAlive.contains($0.id) }

                let photosChanged = prunedPhotos.count != self.photos.count
                let videosChanged = prunedVideos.count != self.videos.count
                guard photosChanged || videosChanged else { return }

                if photosChanged {
                    self.photos = prunedPhotos
                    self.photoTotalSize = prunedPhotos.reduce(0) { $0 + $1.fileSize }
                    self.photoPotentialSavings = prunedPhotos.reduce(0) { $0 + $1.potentialSavings }
                    Task { await self.persistPhotoSnapshotsFromCurrent() }
                }
                if videosChanged {
                    self.videos = prunedVideos
                    self.videoTotalSize = prunedVideos.reduce(0) { $0 + $1.fileSize }
                    self.videoPotentialSavings = prunedVideos.reduce(0) { $0 + $1.potentialSavings }
                    Task { await self.persistVideoSnapshotsFromCurrent() }
                }
            }
        }
    }

    /// Cheap delta scan. Runs whenever the photo library changes (new
    /// capture, import, edit) so the grid stays in sync without forcing
    /// the user to relaunch. Only inspects IDs we don't already track —
    /// previously-scanned assets are skipped via the existing skipIDs
    /// path inside `loadVideos` / `loadPhotos`.
    ///
    /// Doesn't toggle `isLoadingVideos` / `isLoadingPhotos`, doesn't
    /// clear the grid, doesn't reset `hasLoaded*`. The user keeps seeing
    /// what they already had; new items append in place and re-sort.
    @MainActor
    func incrementalScanForNewAssets() async {
        // Don't race the initial load — Phase 2 streaming and this scan
        // can both add the same items, producing duplicate IDs that break
        // the LazyVGrid layout.
        guard !isLoadingPhotos && !isLoadingVideos else { return }

        // Photos: pull current image-asset IDs and find IDs we don't yet
        // have. If there are none, short-circuit.
        let knownPhotoIDs = Set(photos.map(\.id))
        let newPhotoIDs = await Self.diffNewAssetIDs(
            mediaType: .image,
            knownIDs: knownPhotoIDs
        )
        if !newPhotoIDs.isEmpty {
            await scanAndAppendPhotos(newIDs: newPhotoIDs)
        }

        let knownVideoIDs = Set(videos.map(\.id))
        let newVideoIDs = await Self.diffNewAssetIDs(
            mediaType: .video,
            knownIDs: knownVideoIDs
        )
        if !newVideoIDs.isEmpty {
            await scanAndAppendVideos(newIDs: newVideoIDs)
        }
    }

    /// Off-main fetch that returns localIdentifiers present in the
    /// library but not in `knownIDs`. Cheap — single PHFetchAssets call,
    /// no resource inspection.
    private nonisolated static func diffNewAssetIDs(
        mediaType: PHAssetMediaType,
        knownIDs: Set<String>
    ) async -> [String] {
        await Task.detached(priority: .utility) {
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let results = PHAsset.fetchAssets(with: opts)
            var newIDs: [String] = []
            results.enumerateObjects { asset, _, _ in
                if !knownIDs.contains(asset.localIdentifier) {
                    newIDs.append(asset.localIdentifier)
                }
            }
            return newIDs
        }.value
    }

    /// Scans the given new photo IDs and appends them to the grid.
    /// Mirrors the per-asset analysis in `loadPhotos`'s Phase 2 task
    /// group with FULL fidelity — same thresholds, same smart-tag
    /// multipliers, same resource selection. A previous version cut
    /// corners here, which meant a freshly-captured screenshot showed
    /// a worse savings estimate than the same photo would after a
    /// cold scan. No batched flush — just one append at the end so
    /// the grid doesn't shimmer.
    @MainActor
    private func scanAndAppendPhotos(newIDs: [String]) async {
        let scanned: [PhotoAsset] = await Task.detached(priority: .utility) {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: newIDs, options: nil)
            var assets: [PHAsset] = []
            fetched.enumerateObjects { asset, _, _ in
                // Defensive type filter — `fetchAssets(withLocalIdentifiers:)`
                // doesn't enforce mediaType, only the upstream `diffNewAssetIDs`
                // predicate did. If that ever regresses (or a caller invokes
                // this function with mixed IDs), a video would silently land
                // in the photos array and surface in the Photos compress grid.
                guard asset.mediaType == .image else { return }
                if asset.pixelWidth * asset.pixelHeight >= 10_000 {
                    assets.append(asset)
                }
            }
            // Matches loadPhotos Phase 2 (20KB floor + smart-tag multipliers).
            let minBytes: Int64 = 20_000
            return await withTaskGroup(of: PhotoAsset?.self) { group -> [PhotoAsset] in
                for asset in assets {
                    group.addTask {
                        let resources = PHAssetResource.assetResources(for: asset)
                        guard let resource = resources.first(where: { $0.type == .fullSizePhoto })
                            ?? resources.first(where: { $0.type == .photo })
                            ?? resources.first(where: { $0.type == .alternatePhoto }) else { return nil }
                        let fileSize = resource.value(forKey: "fileSize") as? Int64 ?? 0
                        guard fileSize >= minBytes else { return nil }
                        let locallyAvailable = (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
                        var resolution: CGSize?
                        let w = CGFloat(asset.pixelWidth), h = CGFloat(asset.pixelHeight)
                        if w > 0 && h > 0 { resolution = CGSize(width: w, height: h) }
                        let format = PhotoAsset.detectFormat(from: resource)
                        let subtypes = asset.mediaSubtypes
                        let isScreenshot = subtypes.contains(.photoScreenshot)
                        let isLivePhoto  = subtypes.contains(.photoLive)
                        let isHDR        = subtypes.contains(.photoHDR)
                        let isPortrait   = subtypes.contains(.photoDepthEffect)
                        let isPanorama   = subtypes.contains(.photoPanorama)
                        let isBurst      = asset.burstIdentifier != nil || asset.representsBurst

                        let baseSaving = CompressionLevel.medium.estimatedPhotoSavings(
                            from: fileSize, resolution: resolution, sourceFormat: format
                        )
                        // Mirror of loadPhotos Phase 2 — see there for each
                        // multiplier's rationale.
                        var savingsMultiplier: Float = 1.0
                        if isScreenshot { savingsMultiplier *= 1.70 }
                        if isPortrait   { savingsMultiplier *= 0.85 }
                        if isPanorama   { savingsMultiplier *= 1.15 }
                        if isLivePhoto  { savingsMultiplier *= 0.60 }
                        if isHDR        { savingsMultiplier *= 0.85 }
                        let scaledSaving = Int64(Float(baseSaving) * savingsMultiplier)
                        let potentialSaving = min(scaledSaving, fileSize)

                        return PhotoAsset(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: fileSize,
                            potentialSavings: potentialSaving,
                            creationDate: asset.creationDate ?? Date(),
                            resolution: resolution,
                            format: format,
                            isInCloud: !locallyAvailable,
                            tags: PhotoSmartTags(
                                isScreenshot: isScreenshot,
                                isLivePhoto: isLivePhoto,
                                isBurst: isBurst,
                                isHDR: isHDR,
                                isPortrait: isPortrait,
                                isPanorama: isPanorama,
                                isSelfie: false
                            )
                        )
                    }
                }
                var out: [PhotoAsset] = []
                for await item in group { if let item { out.append(item) } }
                return out
            }
        }.value

        guard !scanned.isEmpty else { return }
        let existingIDs = Set(photos.map(\.id))
        let dedupedScanned = scanned.filter { !existingIDs.contains($0.id) }
        guard !dedupedScanned.isEmpty else { return }
        var merged = photos + dedupedScanned
        merged.sort { $0.potentialSavings > $1.potentialSavings }
        photos = merged
        photoTotalSize = merged.reduce(0) { $0 + $1.fileSize }
        photoPotentialSavings = merged.reduce(0) { $0 + $1.potentialSavings }
        Task { await persistPhotoSnapshotsFromCurrent() }
    }

    /// Video counterpart to `scanAndAppendPhotos`. Mirrors loadVideos
    /// Phase 2 with full fidelity (codec detection, cinematic /
    /// slowmo / 4K multipliers) so a freshly-captured 4K HDR clip
    /// gets the same savings estimate as it would after a cold scan.
    @MainActor
    private func scanAndAppendVideos(newIDs: [String]) async {
        let scanned: [VideoAsset] = await Task.detached(priority: .utility) {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: newIDs, options: nil)
            var assets: [PHAsset] = []
            fetched.enumerateObjects { asset, _, _ in
                guard asset.mediaType == .video else { return }
                guard asset.duration >= 0.5 else { return }
                guard asset.pixelWidth * asset.pixelHeight >= 160 * 120 else { return }
                assets.append(asset)
            }
            // 50KB floor matches loadVideos Phase 2 — see there.
            let minBytes: Int64 = 50_000
            return await withTaskGroup(of: VideoAsset?.self) { group -> [VideoAsset] in
                for asset in assets {
                    group.addTask {
                        let resources = PHAssetResource.assetResources(for: asset)
                        guard let resource = resources.first(where: {
                            $0.type == .video || $0.type == .fullSizeVideo
                        }) ?? resources.first else { return nil }
                        let fileSize = resource.value(forKey: "fileSize") as? Int64 ?? 0
                        guard fileSize >= minBytes else { return nil }
                        let locallyAvailable = (resource.value(forKey: "locallyAvailable") as? Bool) ?? true

                        let duration = max(asset.duration, 0)
                        let subtypes = asset.mediaSubtypes
                        let isHighFrameRate = subtypes.contains(.videoHighFrameRate)
                        let isTimelapse = subtypes.contains(.videoTimelapse)
                        let isCinematic: Bool = {
                            if #available(iOS 16.0, *) {
                                let cinematicBit = PHAssetMediaSubtype(rawValue: 1 << 21)
                                return subtypes.contains(cinematicBit)
                            }
                            return false
                        }()

                        let uti = resource.uniformTypeIdentifier.lowercased()
                        let isAlreadyHEVC = uti == "public.hevc"
                            || uti == "public.hevc-video"
                            || uti.hasSuffix(".hevc")
                            || uti.hasSuffix(".hvc1")
                            || uti.hasSuffix(".hev1")

                        let longestEdge = max(asset.pixelWidth, asset.pixelHeight)
                        let is4K = longestEdge >= 3840

                        var savingsMultiplier: Float = 1.0
                        if isAlreadyHEVC                    { savingsMultiplier *= 0.65 }
                        if isHighFrameRate || isTimelapse   { savingsMultiplier *= 0.75 }
                        if isCinematic                      { savingsMultiplier *= 0.70 }
                        if is4K                             { savingsMultiplier *= 1.10 }
                        if duration < 5                     { savingsMultiplier *= 0.80 }

                        let baseSaving = CompressionLevel.medium.estimatedSavings(from: fileSize)
                        let potentialSaving = min(Int64(Float(baseSaving) * savingsMultiplier), fileSize)

                        var resolution: CGSize?
                        let w = CGFloat(asset.pixelWidth), h = CGFloat(asset.pixelHeight)
                        if w > 0 && h > 0 { resolution = CGSize(width: w, height: h) }
                        var bitrate: Float?
                        if duration > 0 {
                            let raw = Float(fileSize * 8) / Float(duration)
                            if raw.isFinite && raw > 0 { bitrate = raw }
                        }
                        return VideoAsset(
                            id: asset.localIdentifier,
                            asset: asset,
                            fileSize: fileSize,
                            potentialSavings: potentialSaving,
                            duration: duration,
                            creationDate: asset.creationDate ?? Date(),
                            resolution: resolution,
                            bitrate: bitrate,
                            isInCloud: !locallyAvailable,
                            tags: VideoSmartTags(
                                isSlowMo: isHighFrameRate,
                                isTimelapse: isTimelapse,
                                isCinematic: isCinematic,
                                is4K: is4K,
                                isHEVC: isAlreadyHEVC,
                                isHDR: false
                            )
                        )
                    }
                }
                var out: [VideoAsset] = []
                for await item in group { if let item { out.append(item) } }
                return out
            }
        }.value

        guard !scanned.isEmpty else { return }
        let existingIDs = Set(videos.map(\.id))
        let dedupedScanned = scanned.filter { !existingIDs.contains($0.id) }
        guard !dedupedScanned.isEmpty else { return }
        var merged = videos + dedupedScanned
        merged.sort { $0.potentialSavings > $1.potentialSavings }
        videos = merged
        videoTotalSize = merged.reduce(0) { $0 + $1.fileSize }
        videoPotentialSavings = merged.reduce(0) { $0 + $1.potentialSavings }
        Task { await persistVideoSnapshotsFromCurrent() }
    }

}

