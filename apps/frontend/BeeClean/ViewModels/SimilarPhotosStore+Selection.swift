import Foundation

// MARK: - Selection (photos, screenshots, videos)
extension SimilarPhotosStore {

    // MARK: Photos

    func toggleSelection(groupId: UUID, assetId: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }),
              let ii = groups[gi].items.firstIndex(where: { $0.assetId == assetId })
        else { return }
        groups[gi].items[ii].isSelectedForDelete.toggle()
    }

    func selectAllExceptBest(groupId: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in groups[gi].items.indices {
            groups[gi].items[ii].isSelectedForDelete = !groups[gi].items[ii].isBest
        }
    }

    /// Select every item in the group, Best included. Best is a
    /// recommendation, not a lock — the user explicitly asked for the
    /// inline-row "Select All" to include it.
    func selectAll(groupId: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in groups[gi].items.indices {
            groups[gi].items[ii].isSelectedForDelete = true
        }
    }

    func deselectAll(groupId: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in groups[gi].items.indices {
            groups[gi].items[ii].isSelectedForDelete = false
        }
    }

    // MARK: Screenshots

    func toggleScreenshotGroupSelection(groupId: UUID, assetId: String) {
        guard let gi = screenshotGroups.firstIndex(where: { $0.id == groupId }),
              let ii = screenshotGroups[gi].items.firstIndex(where: { $0.assetId == assetId })
        else { return }
        screenshotGroups[gi].items[ii].isSelectedForDelete.toggle()
    }

    func selectAllExceptBestScreenshot(groupId: UUID) {
        guard let gi = screenshotGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in screenshotGroups[gi].items.indices {
            screenshotGroups[gi].items[ii].isSelectedForDelete = !screenshotGroups[gi].items[ii].isBest
        }
    }

    func selectAllScreenshot(groupId: UUID) {
        guard let gi = screenshotGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in screenshotGroups[gi].items.indices {
            screenshotGroups[gi].items[ii].isSelectedForDelete = true
        }
    }

    func deselectAllScreenshot(groupId: UUID) {
        guard let gi = screenshotGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in screenshotGroups[gi].items.indices {
            screenshotGroups[gi].items[ii].isSelectedForDelete = false
        }
    }

    // MARK: Videos

    func toggleVideoGroupSelection(groupId: UUID, assetId: String) {
        guard let gi = videoGroups.firstIndex(where: { $0.id == groupId }),
              let ii = videoGroups[gi].items.firstIndex(where: { $0.assetId == assetId })
        else { return }
        videoGroups[gi].items[ii].isSelectedForDelete.toggle()
    }

    func selectAllExceptBestVideo(groupId: UUID) {
        guard let gi = videoGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in videoGroups[gi].items.indices {
            videoGroups[gi].items[ii].isSelectedForDelete = !videoGroups[gi].items[ii].isBest
        }
    }

    func selectAllVideo(groupId: UUID) {
        guard let gi = videoGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in videoGroups[gi].items.indices {
            videoGroups[gi].items[ii].isSelectedForDelete = true
        }
    }

    func deselectAllVideo(groupId: UUID) {
        guard let gi = videoGroups.firstIndex(where: { $0.id == groupId }) else { return }
        for ii in videoGroups[gi].items.indices {
            videoGroups[gi].items[ii].isSelectedForDelete = false
        }
    }

    // MARK: - Global selection (top-right "Select All / Deselect All" pill)
    //
    // For similar/duplicate flows the global pill never selects Best — Best
    // is the recommended-keep tile, and a one-tap "select everything" that
    // queues the keepers for delete would be a footgun. The per-group pill
    // in `GroupInlineRow` still includes Best (legacy contract), but the
    // top-bar pill stays Best-safe across every group.

    var allNonBestPhotosSelected: Bool {
        guard !groups.isEmpty else { return false }
        var sawAnyNonBest = false
        for group in groups {
            for item in group.items where !item.isBest {
                sawAnyNonBest = true
                if !item.isSelectedForDelete { return false }
            }
        }
        // No non-best items in any group → nothing is selected, so the
        // top pill should still read "Select All" rather than flipping
        // to "Deselect All" (the previous behaviour, which returned
        // `true` for vacuous-truth reasons).
        return sawAnyNonBest
    }

    func selectAllNonBestPhotos() {
        for gi in groups.indices {
            for ii in groups[gi].items.indices where !groups[gi].items[ii].isBest {
                groups[gi].items[ii].isSelectedForDelete = true
            }
        }
    }

    func deselectAllPhotos() {
        for gi in groups.indices {
            for ii in groups[gi].items.indices {
                groups[gi].items[ii].isSelectedForDelete = false
            }
        }
    }

    /// Duplicate flow operates on the high-confidence subset of `groups`.
    /// Same Best-safe semantics as the photos pill — returns true only
    /// when at least one non-best item exists AND every such item is
    /// selected, so the top pill correctly stays at "Select All" when
    /// nothing has been chosen yet.
    var allNonBestDuplicatesSelected: Bool {
        let dups = duplicateGroups
        guard !dups.isEmpty else { return false }
        var sawAnyNonBest = false
        for group in dups {
            for item in group.items where !item.isBest {
                sawAnyNonBest = true
                if !item.isSelectedForDelete { return false }
            }
        }
        return sawAnyNonBest
    }

    func selectAllNonBestDuplicates() {
        let dupIds = Set(duplicateGroups.map(\.id))
        for gi in groups.indices where dupIds.contains(groups[gi].id) {
            for ii in groups[gi].items.indices where !groups[gi].items[ii].isBest {
                groups[gi].items[ii].isSelectedForDelete = true
            }
        }
    }

    func deselectAllDuplicates() {
        let dupIds = Set(duplicateGroups.map(\.id))
        for gi in groups.indices where dupIds.contains(groups[gi].id) {
            for ii in groups[gi].items.indices {
                groups[gi].items[ii].isSelectedForDelete = false
            }
        }
    }

    var allNonBestScreenshotsSelected: Bool {
        guard !screenshotGroups.isEmpty else { return false }
        var sawAnyNonBest = false
        for group in screenshotGroups {
            for item in group.items where !item.isBest {
                sawAnyNonBest = true
                if !item.isSelectedForDelete { return false }
            }
        }
        return sawAnyNonBest
    }

    func selectAllNonBestScreenshots() {
        for gi in screenshotGroups.indices {
            for ii in screenshotGroups[gi].items.indices where !screenshotGroups[gi].items[ii].isBest {
                screenshotGroups[gi].items[ii].isSelectedForDelete = true
            }
        }
    }

    func deselectAllScreenshots() {
        for gi in screenshotGroups.indices {
            for ii in screenshotGroups[gi].items.indices {
                screenshotGroups[gi].items[ii].isSelectedForDelete = false
            }
        }
    }

    var allNonBestVideosSelected: Bool {
        guard !videoGroups.isEmpty else { return false }
        var sawAnyNonBest = false
        for group in videoGroups {
            for item in group.items where !item.isBest {
                sawAnyNonBest = true
                if !item.isSelectedForDelete { return false }
            }
        }
        return sawAnyNonBest
    }

    func selectAllNonBestVideos() {
        for gi in videoGroups.indices {
            for ii in videoGroups[gi].items.indices where !videoGroups[gi].items[ii].isBest {
                videoGroups[gi].items[ii].isSelectedForDelete = true
            }
        }
    }

    func deselectAllVideos() {
        for gi in videoGroups.indices {
            for ii in videoGroups[gi].items.indices {
                videoGroups[gi].items[ii].isSelectedForDelete = false
            }
        }
    }
}
