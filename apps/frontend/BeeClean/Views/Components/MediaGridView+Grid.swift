import SwiftUI

extension MediaGridView {
    // MARK: - Stats Header

    var statsHeader: some View {
        HStack(spacing: 16) {
            statPill(
                value: "\(items.count)",
                label: config.countLabel,
                color: config.accentColor
            )
            statPill(
                value: formatBytes(config.totalBytes()),
                label: "Total Size",
                color: .categoryBlue
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Grid
    //
    // Layout strategy: let `LazyVGrid` allocate column width and force every
    // cell into a perfect square via `.aspectRatio(1, contentMode: .fit)`.
    // The previous version derived `cellSize` from a `GeometryReader`'s
    // floating-point width and then applied `.frame(cellSize, cellSize)` to
    // each cell — which can drift by a fractional point from LazyVGrid's
    // own column width. That mismatch caused visibly inconsistent cell
    // sizes ("wonky"), especially across rows where cumulative rounding
    // amplifies. Driving width from the grid + locking aspect to 1:1 is
    // the canonical SwiftUI pattern for pixel-perfect uniform grids and
    // matches Apple Photos / Cleanup-style tile galleries.

    var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(for: item, index: index)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 100)
        }
    }

    @ViewBuilder
    func cell(for item: ScreenshotAsset, index: Int) -> some View {
        let isSelected = selectedIds.contains(item.assetId)
        // 2-col video tiles get a softer 14pt corner; 3-col photo tiles
        // keep the tighter 10pt that reads as a denser gallery.
        let cornerRadius: CGFloat = config.showVideoBadge ? 14 : 10
        Button {
            // Tap-to-select. If we're still in browse mode, flip into
            // select mode FIRST so the Select-All pill, Cancel pill,
            // and bottom action bar all swap in alongside the tile's
            // selection chip. Without this flip, browse-mode taps
            // silently mutated `selectedIds` while the rest of the
            // chrome stayed in browse state — user read it as "I
            // tapped a photo and only half the UI responded."
            //
            // Long-press still opens the zoomable preview (see the
            // `.simultaneousGesture(LongPressGesture)` below) for the
            // browse-mode "I just want to look" path.
            if !isSelecting {
                isSelecting = true
            }
            toggleSelection(item.assetId)
        } label: {
            ZStack(alignment: .topTrailing) {
                // Square thumbnail — `.aspectRatio(1, .fit)` clamps the
                // cell to a 1:1 box at whatever width LazyVGrid hands it,
                // so every tile is identical regardless of column-width
                // rounding. Higher target resolution for 2-col video tiles
                // (~190pt wide × 3x retina ≈ 570px).
                PhotoThumbnailView(
                    assetIdentifier: item.assetId,
                    size: config.showVideoBadge
                        ? CGSize(width: 540, height: 540)
                        : CGSize(width: 360, height: 360)
                )
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isSelected ? config.accentColor : Color.clear,
                            lineWidth: 3
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(isSelected ? 0.35 : 0))
                )
                // Storage-size badge — shown on every populated tile
                // (Screenshots, Blurry, Other, plus Recordings / Long Videos).
                // BitePal espresso ink pill with Poppins-Bold white text at
                // bottom-leading so users can scan the grid and instantly
                // see which items are the heaviest before tapping in.
                .overlay(alignment: .bottomLeading) {
                    if item.fileSize > 0 {
                        Text(formatBytes(item.fileSize))
                            .font(.custom("Poppins-Bold", size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "1C1917").opacity(0.85))
                            )
                            .padding(6)
                    }
                }

                // Top-right overlay stack: source-app badge always shown
                // (renders nothing for `nil` / `.camera`), selection chip
                // drops below it when the grid enters select mode. VStack
                // keeps them in the corner without overlap regardless of
                // tile size. Source resolution prefers the live on-demand
                // cache + analyzedIndex (`store.sourceApp(for:)`) so a
                // tile that was classified mid-session lights up its
                // badge without waiting for the next full similar scan.
                // Fall back to the persisted per-item field for assets
                // already badged before the on-demand path existed.
                VStack(alignment: .trailing, spacing: 4) {
                    SocialSourceBadge(
                        source: store.sourceApp(for: item.assetId) ?? item.sourceApp
                    )
                    if isSelecting {
                        selectionChip(isSelected: isSelected)
                    }
                }
                .padding(6)

                // Favorite micro-button — top-leading. The config's
                // saveContext carries the right `sourceCategory` per
                // grid (screenshots / blurry / otherPhotos / screen
                // recordings / short / long / source-filtered) so a
                // single overlay handles every flat-grid surface.
                // Skipped silently when the parent didn't supply a
                // saveContext (rare, mostly legacy paths).
                if let base = config.saveContext {
                    VStack {
                        HStack {
                            MediaFavoriteButton(
                                assetId: item.assetId,
                                mediaType: base.mediaType,
                                sourceCategory: base.sourceCategory,
                                sourceApp: store.sourceApp(for: item.assetId) ?? item.sourceApp
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            // Lazy per-tile source classification — fires once per asset
            // (dedup'd on the store). MediaGridView cells only hold the
            // assetId, so the store resolves the PHAsset internally off
            // the main actor inside the detached classification task.
            // Result writes to `liveSourceCache`; the @Observable refresh
            // re-renders this cell with the badge on the next frame.
            store.requestSourceClassification(assetId: item.assetId)
        }
        // Long-press to inspect the photo at full size. Replaces the old
        // tap-to-preview path now that single-tap toggles selection.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                previewAssetId = item.assetId
            }
        )
    }

    func selectionChip(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? config.accentColor : Color.black.opacity(0.45))
                .frame(width: 24, height: 24)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
        }
    }

    func toggleSelection(_ id: String) {
        // Per-tile rotor tick — every checkbox flip lands the same
        // tactile cue as a chip swap, so bulk-selecting a grid feels
        // continuous instead of silent. The wrapper's own
        // `isEnabled` gate respects the global haptics preference.
        HapticManager.shared.selection()
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    /// Build a SavedFindContext for a preview-overlay save that overlays
    /// the per-tile asset's `sourceApp` on top of the config's default.
    /// Returns nil if the grid doesn't allow saving at all (config.saveContext
    /// is nil). Source-filtered cards already bake the source into
    /// `config.saveContext` as a fallback; this enrichment is for generic
    /// categories (Other Photos, Blurry, …) where the per-tile asset's
    /// PhotoSource is the real provenance signal.
    func enrichedSaveContext(forAssetId assetId: String) -> SavedFindContext? {
        guard let base = config.saveContext else { return nil }
        let tileSource = items.first(where: { $0.assetId == assetId })?.sourceApp
        return SavedFindContext(
            mediaType: base.mediaType,
            sourceCategory: base.sourceCategory,
            sourceApp: tileSource ?? base.sourceApp
        )
    }

    // MARK: - Empty State

    var emptyState: some View {
        CategoryEmptyState(
            iconName: config.emptyIcon,
            accentColor: config.accentColor,
            title: config.emptyTitle,
            subtitle: config.emptySubtitle
        )
    }

    // MARK: - Month Sections (Blurry / Screenshots / Other Photos)
    //
    // Same Select-All-per-row chrome as GroupInlineRow, just keyed on
    // creation month instead of similarity-cluster id. Items with no
    // creationDate fall into a final "Older" bucket so nothing is dropped
    // from the visible list.

    struct MonthSection: Identifiable {
        let id: String
        let label: String
        let items: [ScreenshotAsset]
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    func computeMonthSections() -> [MonthSection] {
        let calendar = Calendar.current
        var byKey: [DateComponents: [ScreenshotAsset]] = [:]
        var undated: [ScreenshotAsset] = []

        for item in items {
            if let date = item.creationDate {
                let comps = calendar.dateComponents([.year, .month], from: date)
                byKey[comps, default: []].append(item)
            } else {
                undated.append(item)
            }
        }

        let orderedKeys = byKey.keys.sorted { lhs, rhs in
            if (lhs.year ?? 0) != (rhs.year ?? 0) {
                return (lhs.year ?? 0) > (rhs.year ?? 0)
            }
            return (lhs.month ?? 0) > (rhs.month ?? 0)
        }

        var sections: [MonthSection] = []
        for key in orderedKeys {
            guard let bucket = byKey[key],
                  let date = calendar.date(from: key) else { continue }
            let id = "\(key.year ?? 0)-\(key.month ?? 0)"
            sections.append(MonthSection(
                id: id,
                label: Self.monthFormatter.string(from: date),
                items: bucket
            ))
        }
        if !undated.isEmpty {
            sections.append(MonthSection(id: "undated", label: "Older", items: undated))
        }
        return sections
    }

    var groupedSectionsContent: some View {
        ScrollView {
            // ForEach identity = section.id (e.g. "2026-05" / "undated"),
            // NOT the index. Same fix rationale as the Compress grid:
            // index identity over a sortable array means SwiftUI matches
            // by position when the array reshapes, blowing away the
            // LazyHStack thumbnail caches inside each row. Section IDs
            // are stable across recomputes (built from the calendar
            // year-month), so cells track their content correctly when
            // counts shift.
            LazyVStack(spacing: 28) {
                ForEach(cachedMonthSections) { section in
                    monthSectionRow(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        // Cache invalidates on the asset-id LIST hash, not on the count.
        // Previously `id: items.count` would silently miss a same-count
        // permutation — e.g. user deletes one screenshot AND a new one
        // arrives in the same incremental refresh window: count unchanged,
        // sections frozen, the new asset never appears + the deleted one
        // lingers as a tombstone tile until a fresh appear. Hashing the
        // ordered id sequence catches every legitimate change while
        // costing only an O(n) walk on actual mutations (not per body).
        .task(id: itemsCacheToken) {
            cachedMonthSections = computeMonthSections()
        }
    }

    /// Cheap composite token used to drive `cachedMonthSections` refresh.
    /// Combines count (fast-path bail when items shrinks/grows) with the
    /// ordered asset-id hash (catches same-count permutations). Computed
    /// per body but the body never reads `cachedMonthSections` directly,
    /// so this only kicks the section-bucketing pass when the underlying
    /// list actually changed.
    var itemsCacheToken: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for asset in items {
            hasher.combine(asset.assetId)
        }
        return hasher.finalize()
    }

    @ViewBuilder
    func monthSectionRow(_ section: MonthSection) -> some View {
        let sectionBytes = section.items.reduce(Int64(0)) { $0 + $1.fileSize }
        let allSelected = !section.items.isEmpty &&
            section.items.allSatisfy { selectedIds.contains($0.assetId) }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Tap-the-title-row entry into the month-scoped swipe deck.
                // The wand-pill that used to live on the right was eating
                // a chunk of the row for a job the title can already do —
                // tapping the month *is* "swipe this month." The chevron
                // is the only affordance kept, and it inherits the
                // category accent so the visual tie to the full-grid
                // swipe button stays intact.
                Button {
                    if !isSelecting, config.makeSwipeViewForItems != nil {
                        monthSwipeItems = section.items
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.label)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(hex: "1C1917"))
                            Text("\(section.items.count) \(config.countLabel.lowercased()) · \(formatBytes(sectionBytes))")
                                .font(.system(size: 12))
                                .foregroundColor(.mutedForeground)
                        }

                        if !isSelecting, config.makeSwipeViewForItems != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(config.accentColor.opacity(0.75))
                                .padding(.leading, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSelecting || config.makeSwipeViewForItems == nil)

                Spacer()

                Button {
                    toggleSectionSelection(section, allSelected: allSelected)
                } label: {
                    BitePalSelectPillLabel(
                        text: allSelected ? "Deselect All" : "Select All",
                        isActive: allSelected
                    )
                }
                .buttonStyle(.plain)
            }

            // LazyHStack so a 200-item month doesn't fire 200 thumbnail
            // requests on appear — same rationale as GroupInlineRow.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(section.items) { item in
                        monthSectionCell(for: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func monthSectionCell(for item: ScreenshotAsset) -> some View {
        let isSelected = selectedIds.contains(item.assetId)
        let thumbSize: CGFloat = 160

        Button {
            if isSelecting {
                toggleSelection(item.assetId)
            } else {
                previewAssetId = item.assetId
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                PhotoThumbnailView(
                    assetIdentifier: item.assetId,
                    size: CGSize(width: 480, height: 480)
                )
                .frame(width: thumbSize, height: thumbSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? config.accentColor : Color.clear, lineWidth: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(isSelected ? 0.35 : 0))
                )
                // Per-photo storage badge — same espresso pill as the flat
                // grid cell so a user month-grouping through Screenshots /
                // Blurry / Other Photos can see file weight at a glance.
                .overlay(alignment: .bottomLeading) {
                    if item.fileSize > 0 {
                        Text(formatBytes(item.fileSize))
                            .font(.custom("Poppins-Bold", size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "1C1917").opacity(0.85))
                            )
                            .padding(6)
                    }
                }

                if isSelecting {
                    selectionChip(isSelected: isSelected)
                        .padding(6)
                }
            }
            .frame(width: thumbSize, height: thumbSize)
        }
        .buttonStyle(.plain)
    }

    func toggleSectionSelection(_ section: MonthSection, allSelected: Bool) {
        // Tapping Select-All on a section also enters selection mode if not
        // already in it — otherwise the deletion bar wouldn't appear and
        // the user would be confused why their selection didn't surface.
        if allSelected {
            for item in section.items {
                selectedIds.remove(item.assetId)
            }
        } else {
            for item in section.items {
                selectedIds.insert(item.assetId)
            }
            if !isSelecting { isSelecting = true }
        }
    }
}

