import SwiftUI

// MARK: - Group Inline Row (horizontal scroll row for one group)
struct GroupInlineRow: View {
    let group: SimilarGroupVM
    let groupIndex: Int
    let source: GroupSource
    let onToggle: (UUID, String) -> Void
    let onSelectAll: (UUID) -> Void
    let onDeselectAll: (UUID) -> Void
    /// Tapping a thumbnail body opens a full-screen preview (Cleanup-style
    /// swipe deck). Receives the groupId and the tapped item's index so the
    /// pager can start positioned on that exact item. Optional so callers
    /// that don't want the preview path can omit it.
    var onOpenDetail: ((UUID, Int) -> Void)? = nil
    /// Tapping the small swipe pill in the row header opens a Tinder-style
    /// deck of just THIS group's items — same UX as the flat-grid swipe in
    /// Other Photos / Blurry / Screenshots. Lets users plow through one
    /// group at a time without having to scroll back to the parent list.
    /// When nil, the pill is hidden (e.g. for callers that haven't wired
    /// the cover yet).
    var onSwipeGroup: ((SimilarGroupVM) -> Void)? = nil
    /// Fired when a thumbnail's underlying PHAsset cannot be loaded after
    /// the loadThumbnail retry chain has been exhausted. Caller should
    /// route this to `store.pruneUnloadableAsset(assetId)` so the cell
    /// disappears from the row instead of sitting on screen as a gray
    /// skeleton claiming there's something to clean up. Optional — callers
    /// that don't manage a mutable source list can omit it.
    var onItemUnloadable: ((String) -> Void)? = nil

    private var allSelected: Bool {
        !group.items.isEmpty && group.items.allSatisfy(\.isSelectedForDelete)
    }

    // "Deselect All" only makes sense for multi-selection — otherwise the
    // user can just tap the single red-checked tile to clear it. Keep the
    // header toggle showing "Select All" for 0 or 1 selected, and flip to
    // "Deselect All" only when every tile in the group (Best included) is
    // already selected.
    private var showDeselect: Bool {
        group.selectedCount > 1 && allSelected
    }

    private var groupTotalBytes: Int64 {
        let itemBytes = group.items.reduce(Int64(0)) { $0 + $1.fileSize }
        return itemBytes > 0 ? itemBytes : group.totalBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: "[N] Similar" left, "Swipe" + "Select All" right.
            //
            // The Swipe pill opens a Tinder-style deck scoped to THIS
            // group's items only — same engine as Other Photos / Blurry /
            // Screenshots. Hidden when the parent doesn't wire onSwipeGroup
            // (forwards-compat with any caller still on the old API).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(group.count) Similar")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                // Wand pill is video-only. Similar Photos / Duplicates /
                // Similar Screenshots intentionally suppress it — those
                // flows already lean on tap-to-zoom + the Select All
                // pill, and the extra glyph was crowding the row header
                // without earning its keep. Similar Videos keeps it
                // because video review benefits from the per-group
                // Tinder deck.
                if onSwipeGroup != nil && source == .videos {
                    Button {
                        onSwipeGroup?(group)
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                source.themeColor,
                                                source.themeColor.opacity(0.85)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .shadow(color: source.themeColor.opacity(0.35), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    // Tactile feedback on every per-group Select / Deselect
                    // press. Same `buttonTap` signature the rest of the
                    // primary chrome uses so the pill reads as a deliberate
                    // commit, not a silent toggle.
                    HapticManager.shared.buttonTap()
                    if showDeselect {
                        onDeselectAll(group.id)
                    } else {
                        onSelectAll(group.id)
                    }
                } label: {
                    BitePalSelectPillLabel(
                        text: showDeselect ? "Deselect All" : "Select All",
                        isActive: showDeselect
                    )
                }
                .buttonStyle(.plain)
            }

            // Horizontal scroll of large thumbnails — two visible at a time.
            // LazyHStack so groups with many similar photos don't fire
            // PHImageManager.requestImage for off-screen tiles on appear.
            // For a 50-item group the eager HStack was loading 50 × 480px
            // thumbnails up front; LazyHStack defers everything past the
            // visible window.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    // Identity by assetId, NOT by index. Index-based
                    // identity meant a selection toggle could shift the
                    // SwiftUI identity table and re-associate a cell's
                    // @State (including its loaded thumbnail and its
                    // in-flight request token) with a different photo —
                    // which painted as "gray box that should have been
                    // an image." Stable identity by assetId ensures every
                    // cell keeps its own loaded state across mid-row
                    // mutations like selection toggles.
                    ForEach(Array(group.items.enumerated()), id: \.element.assetId) { itemIndex, item in
                        InlineThumbnailCell(
                            item: item,
                            themeColor: source.themeColor,
                            isVideo: source == .videos,
                            source: source,
                            onOpenDetail: {
                                onOpenDetail?(group.id, itemIndex)
                            },
                            onToggleSelection: {
                                // Best is a *recommendation*, not a lock —
                                // users explicitly asked to be able to mark
                                // the Best item for delete too. The visual
                                // "Best" crown still shows so they know
                                // which one we recommend keeping.
                                onToggle(group.id, item.assetId)
                            },
                            onUnloadable: {
                                onItemUnloadable?(item.assetId)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Inline Thumbnail Cell
struct InlineThumbnailCell: View {
    let item: SimilarGroupItem
    let themeColor: Color
    /// Kept as a parameter for call-site compatibility but no longer drives
    /// any visual treatment. Per-video storage labels were removed from the
    /// Similar Videos grid — the user found them visually noisy.
    var isVideo: Bool = false
    /// Drives the favorite micro-button's `SavedFindSourceCategory`
    /// mapping so a save from a Similar Photos group lands in the
    /// `.similarPhotos` bucket, a Duplicate save lands in
    /// `.duplicates`, etc. Default `.photos` keeps any legacy call site
    /// that hasn't been migrated yet compiling — it just defaults to
    /// the Similar Photos bucket.
    var source: GroupSource = .photos
    /// Tap anywhere on the thumbnail body → open full-screen preview pager.
    let onOpenDetail: () -> Void
    /// Tap the selection checkbox chip → toggle isSelectedForDelete. This
    /// is a SEPARATE tap target so the user can still select without
    /// opening the full preview (the chip is a button overlaid on the
    /// thumbnail and consumes its own taps).
    let onToggleSelection: () -> Void
    /// Forwarded to PhotoThumbnailView's `onUnloadable` — fires once if the
    /// asset cannot be rendered after the loadThumbnail retry chain. The
    /// owning view (GroupInlineRow → SimilarPhotosView etc.) routes this
    /// to `store.pruneUnloadableAsset` so the cell vanishes.
    var onUnloadable: (() -> Void)? = nil
    /// Cross-flow source resolution — see PhotoCompressCard rationale.
    /// `store.sourceApp(for:)` reads analyzedIndex + liveSourceCache so
    /// the badge mirrors the latest classification result regardless of
    /// whether it landed via the bulk scan or the on-demand tile pass.
    @Environment(SimilarPhotosStore.self) private var similarStore

    private var resolvedSource: PhotoSource? {
        similarStore.sourceApp(for: item.assetId) ?? item.sourceApp
    }

    /// Media-type input for the favorite micro-button. Videos surface
    /// when the cell's containing group is `.videos`; everything else
    /// (Similar Photos / Duplicates / Screenshots) is a photo cell.
    private var favoriteMediaType: SavedFindMediaType {
        source == .videos ? .video : .photo
    }

    /// Source-category input — 1:1 mapping from the group's
    /// `GroupSource` to the matching `SavedFindSourceCategory` so a
    /// saved item shows up inside the right Saved Finds filter chip.
    private var favoriteSourceCategory: SavedFindSourceCategory {
        switch source {
        case .photos:      return .similarPhotos
        case .duplicates:  return .duplicates
        case .screenshots: return .similarScreenshots
        case .videos:      return .similarVideos
        }
    }

    private let thumbSize: CGFloat = 160

    var body: some View {
        // Apple-Photos dual-region pattern:
        //   • Tap the card body → opens the full-screen preview pager
        //     (`onOpenDetail`). The user wanted to see the actual image
        //     by tapping the card.
        //   • Tap the bottom-right checkbox glyph → toggles the red-
        //     checkmark selection (`onToggleSelection`). The checkbox
        //     is its own Button overlay with its own hit region.
        //   • Tap the top-left heart → favorites to Saved Finds (own
        //     Button in its own overlay).
        // Three discrete tap regions, three discrete intents — no
        // nested-Button arbitration on the outer body because the
        // outer body is a plain `.onTapGesture` on a `.contentShape`'d
        // ZStack. The inner Buttons (heart + checkbox) keep gesture
        // priority for their own 32pt frames.
        ZStack {
            PhotoThumbnailView(
                assetIdentifier: item.assetId,
                // `size` is in logical points — `loadThumbnail` scales
                // by UIScreen.main.scale before hitting PHImageManager,
                // so passing the cell's exact `thumbSize` (160pt) is
                // enough to get a 480-pixel image on 3x retina.
                size: CGSize(width: thumbSize, height: thumbSize),
                contentMode: .fill,
                onUnloadable: { onUnloadable?() }
            )
            .frame(width: thumbSize, height: thumbSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Dim overlay for selected items
            if item.isSelectedForDelete {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.35))
                    .allowsHitTesting(false)
            }

            // Bottom-left: Best badge (frosted pill)
            if item.isBest {
                VStack {
                    Spacer()
                    HStack {
                        bestBadge
                        Spacer()
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        // Restrict the tap hit region to the rounded card silhouette so
        // taps just outside the visible image (in the rounded corners)
        // don't fire selection.
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            // Card body tap opens the preview pager. Tactile feedback
            // fires synchronously with the open so the user feels the
            // commit before the cover-animation kicks in.
            HapticManager.shared.buttonTap()
            onOpenDetail()
        }
        .overlay(alignment: .topTrailing) {
            // Source-app badge — top-right of the group tile. Renders
            // nothing when source is nil / .camera. Smaller (18pt)
            // than the detail-grid badge since group tiles are denser.
            // `resolvedSource` reads through the store so on-demand
            // classification results light up the badge instantly.
            SocialSourceBadge(source: resolvedSource, size: 18)
                .padding(6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            // Favorite micro-button — Button keeps tap priority within
            // its own 32pt frame, so tapping the heart favorites the
            // item without firing the card's tap-to-select.
            MediaFavoriteButton(
                assetId: item.assetId,
                mediaType: favoriteMediaType,
                sourceCategory: favoriteSourceCategory,
                sourceApp: resolvedSource,
                size: 26
            )
            .padding(6)
        }
        .task {
            // Lazy classification kick-off — see PhotoCompressCard for
            // the full rationale. Idempotent + dedup'd on the store.
            similarStore.requestSourceClassification(assetId: item.assetId)
        }
        .overlay(alignment: .bottomTrailing) {
            // Dedicated checkbox Button — its own 32pt tap region at
            // bottom-trailing. Tapping here toggles the red checkmark
            // WITHOUT firing the card body's tap (which would open the
            // preview pager). Same dual-region pattern Apple Photos
            // uses: card surface to view, chip to select.
            //
            // Selection tick haptic fires for both directions (select
            // and deselect). Lighter than `buttonTap` because the
            // checkbox is a high-frequency control during bulk review
            // — a heavier sensation would fatigue on a 50-tap session.
            Button {
                HapticManager.shared.selection()
                onToggleSelection()
            } label: {
                selectionCheckbox
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Best Badge
    private var bestBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "D4A017"))

            Text(BCLoc.best.tr)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Selection Checkbox
    @ViewBuilder
    private var selectionCheckbox: some View {
        if item.isSelectedForDelete {
            ZStack {
                Circle()
                    .fill(Color.destructive)
                    .frame(width: 26, height: 26)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.7), lineWidth: 2)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(0.2))
                )
        }
    }
}
