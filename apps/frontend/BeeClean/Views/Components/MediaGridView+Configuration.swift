import SwiftUI


// MARK: - Media Grid Configuration

@MainActor
struct MediaGridConfig {
    let title: String
    let items: @MainActor () -> [ScreenshotAsset]
    let totalBytes: @MainActor () -> Int64
    let countLabel: String
    let accentColor: Color
    let emptyIcon: String
    let emptyTitle: String
    let emptySubtitle: String
    let showVideoBadge: Bool
    let makeSwipeView: @MainActor (Int) -> AnyView
    /// Optional month-scoped swipe view. When provided, each month section in
    /// the grid renders a "Swipe Month" pill that opens this view with
    /// `items` filtered to that single month. Lets users tackle a backlog
    /// month-by-month instead of facing a 6,000-photo Tinder deck.
    var makeSwipeViewForItems: (@MainActor ([ScreenshotAsset]) -> AnyView)? = nil
    // Rebuilds the store slice for this category after deletion. Each flat
    // category keeps its list in a different place (analyzedIndex vs its own
    // ScreenshotScanResult), so the caller supplies the right refresh.
    let refreshAfterDelete: @MainActor (SimilarPhotosStore, Set<String>) async -> Void
    /// SF Symbol shown on the per-month "swipe this month" pill in
    /// `monthSectionRow`. Distinct per category so Screenshots / Blurry /
    /// Other Photos each read as their own action instead of all sharing the
    /// generic `hand.draw.fill` glyph.
    var swipeMonthIcon: String = "hand.draw.fill"
    // Photo categories with no inherent group structure (Blurry / Screenshots
    // / Other Photos) opt into month-section rendering: each section is a
    // horizontal scroll of large tiles with a Select-All header. Mirrors the
    // GroupInlineRow layout used by Duplicates / Similar so the bottom-half
    // of the photos tab feels organized instead of one endless flat grid.
    var useMonthGrouping: Bool = false
    /// Video categories (Screen Recordings / Short Recordings / Long Videos)
    /// opt out of swipe-mode entirely — neither the header swipe button nor
    /// the per-month wand affordance shows. Cleanup happens via multi-select
    /// + delete, matching the Cleanup tab's interaction model.
    var showsSwipe: Bool = true
    /// Optional Saved Finds context. Threaded into the tap-to-zoom preview
    /// overlay so users can bookmark a photo/video without leaving review.
    /// Approved Photos/Videos categories set this; banned flows leave nil.
    var saveContext: SavedFindContext? = nil
}

// MARK: - Factory Methods

extension MediaGridConfig {
    static func screenshots(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "All Screenshots",
            items: { store.ungroupedScreenshots },
            totalBytes: { store.ungroupedScreenshotBytes },
            countLabel: "Screenshots",
            accentColor: .categoryOrange,
            // Matches `IntelligentPreviewCard.categoryIcon[.screenshots]`
            // so the homepage tile and the empty state share one icon.
            emptyIcon: "camera.viewfinder",
            emptyTitle: "No Screenshots Found",
            emptySubtitle: "Run a scan to detect screenshots\nin your photo library",
            showVideoBadge: false,
            makeSwipeView: { index in
                AnyView(MediaSwipeView(
                    vm: ScreenshotSwipeViewModel(store: store, startIndex: index),
                    config: MediaSwipeConfig(
                        accentColor: .categoryOrange,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .screenshots)
                    )
                ))
            },
            makeSwipeViewForItems: { items in
                AnyView(MediaSwipeView(
                    vm: ScreenshotSwipeViewModel(store: store, items: items),
                    config: MediaSwipeConfig(
                        accentColor: .categoryOrange,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .screenshots)
                    )
                ))
            },
            refreshAfterDelete: { store, _ in
                await store.refreshScreenshotScanResult()
            },
            swipeMonthIcon: "wand.and.stars",
            useMonthGrouping: true,
            saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .screenshots)
        )
    }

    static func blurryPhotos(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "Blurred Photos",
            items: { store.blurryPhotos },
            totalBytes: { store.blurryPhotoBytes },
            countLabel: "Photos",
            accentColor: .categoryRose,
            emptyIcon: "camera.metering.unknown",
            emptyTitle: "No Blurred Photos Found",
            emptySubtitle: "All your photos are sharp and clear",
            showVideoBadge: false,
            makeSwipeView: { index in
                AnyView(MediaSwipeView(
                    vm: BlurryPhotoSwipeViewModel(store: store, startIndex: index),
                    config: MediaSwipeConfig(
                        accentColor: .categoryRose,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .blurredPhotos)
                    )
                ))
            },
            makeSwipeViewForItems: { items in
                AnyView(MediaSwipeView(
                    vm: BlurryPhotoSwipeViewModel(store: store, items: items),
                    config: MediaSwipeConfig(
                        accentColor: .categoryRose,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .blurredPhotos)
                    )
                ))
            },
            refreshAfterDelete: { _, _ in
                // Blurry list is computed from analyzedIndex; deleteFlatAssets
                // already pruned it, so the published view recomputes.
            },
            swipeMonthIcon: "wand.and.stars",
            useMonthGrouping: true,
            saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .blurredPhotos)
        )
    }

    static func otherPhotos(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "Other Photos",
            items: { store.ungroupedPhotos },
            totalBytes: { store.ungroupedPhotoBytes },
            countLabel: "Photos",
            accentColor: .categoryBlue,
            // Sleeker framed-photo glyph (vs the chunky `photo.fill`
            // landscape-with-mountain). Stays distinct from every other
            // category icon and reads as "miscellaneous photo" cleanly.
            // Matches `IntelligentPreviewCard.categoryIcon[.otherPhotos]`
            // so the homepage tile and the empty state share one icon.
            emptyIcon: "photo.artframe",
            emptyTitle: "No Other Photos Found",
            emptySubtitle: "Run a scan to detect photos\nin your library",
            showVideoBadge: false,
            makeSwipeView: { index in
                AnyView(MediaSwipeView(
                    vm: OtherPhotoSwipeViewModel(store: store, startIndex: index),
                    config: MediaSwipeConfig(
                        accentColor: .categoryBlue,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .otherPhotos)
                    )
                ))
            },
            makeSwipeViewForItems: { items in
                AnyView(MediaSwipeView(
                    vm: OtherPhotoSwipeViewModel(store: store, items: items),
                    config: MediaSwipeConfig(
                        accentColor: .categoryBlue,
                        saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .otherPhotos)
                    )
                ))
            },
            refreshAfterDelete: { _, _ in
                // Other-photos list is computed from analyzedIndex; same
                // rationale as blurry — pruning analyzedIndex is enough.
            },
            swipeMonthIcon: "wand.and.stars",
            useMonthGrouping: true,
            saveContext: SavedFindContext(mediaType: .photo, sourceCategory: .otherPhotos)
        )
    }

    // MARK: - Source-App Filtered
    //
    // Backs the per-source dashboard cards on the Charging tab
    // ("Snapchat", "Instagram", "WhatsApp", etc.). Same flat-grid +
    // swipe-deck plumbing as Other Photos — only the items closure and
    // accent color change. The brand-tinted accent ties the grid header,
    // selection chip, and swipe-card background back to the source.
    static func sourceFiltered(_ store: SimilarPhotosStore, source: PhotoSource) -> MediaGridConfig {
        let items = { store.assetsFrom(source: source) }
        return MediaGridConfig(
            title: source.displayName,
            items: items,
            totalBytes: { store.dashboardSnapshot.sourceCardBytes[source] ?? 0 },
            countLabel: "Photos",
            accentColor: source.brandColor,
            // Generic photo glyph — the brand-tinted accent + title carry
            // the source identity, so the empty-state icon stays neutral.
            emptyIcon: "photo.on.rectangle.angled",
            emptyTitle: "No \(source.displayName) photos",
            emptySubtitle: "Photos saved by \(source.displayName) will\nappear here as your library grows.",
            showVideoBadge: false,
            makeSwipeView: { index in
                AnyView(MediaSwipeView(
                    vm: OtherPhotoSwipeViewModel(
                        store: store,
                        items: items(),
                        startIndex: index
                    ),
                    config: MediaSwipeConfig(
                        accentColor: source.brandColor,
                        saveContext: SavedFindContext(
                            mediaType: .photo,
                            sourceCategory: .otherPhotos,
                            sourceApp: source
                        )
                    )
                ))
            },
            makeSwipeViewForItems: { items in
                AnyView(MediaSwipeView(
                    vm: OtherPhotoSwipeViewModel(store: store, items: items),
                    config: MediaSwipeConfig(
                        accentColor: source.brandColor,
                        saveContext: SavedFindContext(
                            mediaType: .photo,
                            sourceCategory: .otherPhotos,
                            sourceApp: source
                        )
                    )
                ))
            },
            refreshAfterDelete: { _, _ in
                // Source-filtered list reads from analyzedIndex; deletion
                // already prunes it (same rationale as Blurry / Other Photos).
            },
            swipeMonthIcon: "wand.and.stars",
            useMonthGrouping: true,
            saveContext: SavedFindContext(
                mediaType: .photo,
                sourceCategory: .otherPhotos,
                sourceApp: source
            )
        )
    }

    static func screenRecordings(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "Screen Recordings",
            items: { store.screenRecordingScanResult.screenshots },
            totalBytes: { store.screenRecordingTotalBytes },
            countLabel: "Recordings",
            // Indigo — matches the home-card accent so the color identity
            // carries through from Cleanup → detail screen.
            accentColor: .categoryIndigo,
            // Matches `IntelligentPreviewCard.categoryIcon[.screenRecordings]`.
            emptyIcon: "record.circle.fill",
            emptyTitle: "No Screen Recordings Found",
            emptySubtitle: "Run a scan to detect screen recordings\nin your video library",
            showVideoBadge: true,
            makeSwipeView: { _ in AnyView(EmptyView()) },
            refreshAfterDelete: { store, _ in
                await store.refreshScreenRecordingScanResult()
            },
            useMonthGrouping: true,
            showsSwipe: false,
            saveContext: SavedFindContext(mediaType: .video, sourceCategory: .screenRecordings)
        )
    }

    static func shortRecordings(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "Short Recordings",
            items: { store.shortVideoScanResult.screenshots },
            totalBytes: { store.shortVideoTotalBytes },
            countLabel: "Videos",
            // Mint — matches the home-card accent.
            accentColor: .categoryMint,
            // Matches `IntelligentPreviewCard.categoryIcon[.shortRecordings]`
            // — distinct from `video.fill` (Similar Videos).
            emptyIcon: "video.badge.ellipsis",
            emptyTitle: "No Short Recordings Found",
            emptySubtitle: "Run a scan to detect short videos\nin your library",
            showVideoBadge: true,
            makeSwipeView: { _ in AnyView(EmptyView()) },
            refreshAfterDelete: { store, _ in
                await store.refreshShortVideoScanResult()
            },
            useMonthGrouping: true,
            showsSwipe: false,
            saveContext: SavedFindContext(mediaType: .video, sourceCategory: .shortRecordings)
        )
    }

    static func longVideos(_ store: SimilarPhotosStore) -> MediaGridConfig {
        MediaGridConfig(
            title: "Long Videos",
            items: { store.longVideoScanResult.screenshots },
            totalBytes: { store.longVideoTotalBytes },
            countLabel: "Videos",
            // Cocoa — matches the home-card accent.
            accentColor: .categoryCocoa,
            // Matches `IntelligentPreviewCard.categoryIcon[.longVideos]`.
            emptyIcon: "film.fill",
            emptyTitle: "No Long Videos Found",
            emptySubtitle: "Long videos (10 min or more) will\nappear here for cleanup",
            showVideoBadge: true,
            makeSwipeView: { _ in AnyView(EmptyView()) },
            refreshAfterDelete: { store, _ in
                await store.refreshLongVideoScanResult()
            },
            useMonthGrouping: true,
            showsSwipe: false,
            saveContext: SavedFindContext(mediaType: .video, sourceCategory: .longVideos)
        )
    }
}
