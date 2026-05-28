import SwiftUI

// MARK: - Intelligent Preview Card
/// Image-first cleanup card: title at top, two side-by-side photo previews,
/// and an info badge overlaid on the photo area.
struct IntelligentPreviewCard: View {
    let destination: CleanupDestination
    @Binding var selectedDestination: CleanupDestination?
    let title: String
    let accentColor: Color
    let itemCount: Int
    let storageBytes: Int64
    let assetIds: [String]
    let isScanning: Bool
    let scanComplete: Bool
    /// Fires once per asset whose thumbnail is genuinely unrenderable (both
    /// opportunistic and high-quality fetches returned nil — usually the
    /// asset was deleted from Photos after the scan cached its ID). Callers
    /// must route this to `SimilarPhotosStore.pruneUnloadableAsset` so the
    /// dead ID disappears from the preview list and the card stops showing
    /// a gray empty rectangle where the photo should be.
    var onAssetUnloadable: ((String) -> Void)? = nil

    private let cardRadius: CGFloat = DesignTokens.Radius.xl

    @State private var allClearScale: CGFloat = 0.5
    /// Manual press-state flag so the dim+scale visual is GUARANTEED
    /// visible even on micro-quick taps (vanilla Button press visual
    /// vanishes before the eye catches it because the navigation
    /// transition starts in the same frame).
    @State private var isCardPressed = false
    /// Drives the pill's content rotation between the stats line ("87
    /// Photos") and the "New Photos" badge. Toggled by `rotationTimer`
    /// only while `hasNewContent` is true — once the user taps the card
    /// the baseline updates and rotation stops on next render.
    @State private var showingNewIndicator = false
    @State private var rotationTimer: Timer?

    // MARK: - State

    private var hasItems: Bool { !assetIds.isEmpty && itemCount > 0 }
    private var isAllClear: Bool { scanComplete && itemCount == 0 }

    /// Stable string key per destination for the baseline UserDefault.
    /// Hand-rolled instead of `String(describing:)` so a future enum
    /// rename doesn't silently invalidate every user's baseline and
    /// flash "New" labels across the entire dashboard.
    private var destinationKey: String {
        switch destination {
        case .duplicatePhotos: return "duplicatePhotos"
        case .similarPhotos: return "similarPhotos"
        case .similarScreenshots: return "similarScreenshots"
        case .screenshots: return "screenshots"
        case .blurryPhotos: return "blurryPhotos"
        case .otherPhotos: return "otherPhotos"
        case .similarVideos: return "similarVideos"
        case .screenRecordings: return "screenRecordings"
        case .shortRecordings: return "shortRecordings"
        case .longVideos: return "longVideos"
        case .guidedCleanup: return "guidedCleanup"
        case .sourceFiltered(let source):
            // Namespaced per-source so each connector (Snap, Insta, etc.)
            // keeps its own "New" baseline independent of every other
            // source AND of the main library categories.
            return "sourceFiltered.\(source.rawValue)"
        }
    }

    private var baselineDefaultsKey: String {
        "IntelligentPreviewCard.lastSeenCount.\(destinationKey)"
    }

    /// True when the on-device scanner has surfaced more items in this
    /// category than the user last saw.
    ///
    /// The baseline is seeded the first time `scanComplete == true` (see
    /// `seedBaselineIfNeeded`) so the FIRST scan after install never
    /// blanket-flashes "New" on every populated card — the user hasn't
    /// asked us to alert them about clutter that's been there all along.
    /// "New" should only ever pop on a category where the scanner has
    /// found *more* items since the last time the user opened the card.
    private var hasNewContent: Bool {
        guard itemCount > 0 else { return false }
        // Treat a missing baseline as "not yet seeded" — the first
        // post-scan render will seed it via `seedBaselineIfNeeded`. Until
        // that happens, suppress the "New" flash so a freshly-launched
        // app doesn't strobe across every card.
        guard UserDefaults.standard.object(forKey: baselineDefaultsKey) != nil else {
            return false
        }
        let lastSeen = UserDefaults.standard.integer(forKey: baselineDefaultsKey)
        return itemCount > lastSeen
    }

    /// Writes the current `itemCount` as the user's baseline the first
    /// time this card sees a completed scan. Only runs when:
    ///   • a scan has actually completed (`scanComplete == true`), and
    ///   • we haven't already persisted a baseline for this destination.
    /// Any later increase in `itemCount` (new screenshot taken, new
    /// duplicate detected on the next incremental refresh, etc.) will
    /// correctly satisfy `hasNewContent` and trigger the rotation.
    private func seedBaselineIfNeeded() {
        guard scanComplete else { return }
        guard UserDefaults.standard.object(forKey: baselineDefaultsKey) == nil else { return }
        UserDefaults.standard.set(itemCount, forKey: baselineDefaultsKey)
    }

    private var itemLabel: String {
        switch destination {
        case .duplicatePhotos, .similarPhotos, .similarScreenshots, .similarVideos:
            return itemCount == 1 ? "Group" : "Groups"
        case .screenshots:
            return itemCount == 1 ? "Screenshot" : "Screenshots"
        case .blurryPhotos:
            return itemCount == 1 ? "Photo" : "Photos"
        case .otherPhotos:
            return itemCount == 1 ? "Photo" : "Photos"
        case .screenRecordings:
            return itemCount == 1 ? "Recording" : "Recordings"
        case .shortRecordings:
            return itemCount == 1 ? "Video" : "Videos"
        case .longVideos:
            return itemCount == 1 ? "Video" : "Videos"
        case .guidedCleanup:
            return "Task"
        case .sourceFiltered:
            // Source-filtered grids show whatever media the source
            // exposed — photos and videos can be mixed. "Item"
            // generalizes without making a wrong commitment.
            return itemCount == 1 ? "Item" : "Items"
        }
    }

    private var categoryIcon: String {
        switch destination {
        case .duplicatePhotos: return "doc.on.doc.fill"
        case .similarPhotos: return "photo.stack.fill"
        case .similarScreenshots: return "rectangle.on.rectangle.fill"
        case .screenshots: return "camera.viewfinder"
        case .blurryPhotos: return "camera.metering.unknown"
        case .otherPhotos: return "photo.artframe"
        case .similarVideos: return "video.fill"
        case .screenRecordings: return "record.circle.fill"
        case .shortRecordings: return "video.badge.ellipsis"
        case .longVideos: return "film.fill"
        case .guidedCleanup: return "sparkles"
        case .sourceFiltered:
            // Generic "connected source" glyph — the per-source brand
            // is communicated by the card's title + accent, not the
            // SF Symbol. Keeps the visual language consistent across
            // every imported-source preview card.
            return "link.circle.fill"
        }
    }

    private var formattedStorage: String {
        let bytes = Double(storageBytes)
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", bytes / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", bytes / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.0f KB", bytes / 1024)
        }
        return "0 KB"
    }

    // MARK: - Body

    var body: some View {
        Button {
            // Same pop-then-navigate pattern as Quick Access tiles —
            // pin the press visual for ~150ms so the user SEES the
            // darken/scale before the navigation transition starts.
            // Without this delay the press state is dismissed before
            // the eye can catch it, which reads as "static" to the user.
            UserDefaults.standard.set(itemCount, forKey: baselineDefaultsKey)
            HapticManager.shared.impact(.light)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                isCardPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    isCardPressed = false
                }
                selectedDestination = destination
            }
        } label: {
            if hasItems {
                imageFirstLayout
            } else {
                compactRowLayout
            }
        }
        .buttonStyle(.plain)
        // Manual press visual driven by `isCardPressed` — guaranteed
        // visible regardless of how fast the user releases.
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                .fill(Color.black.opacity(isCardPressed ? 0.18 : 0))
                .allowsHitTesting(false)
        )
        .brightness(isCardPressed ? -0.08 : 0)
        .scaleEffect(isCardPressed ? 0.96 : 1)
        .onAppear {
            if isAllClear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    allClearScale = 1.0
                }
            }
            seedBaselineIfNeeded()
            startRotationIfNeeded()
        }
        .onDisappear {
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
        // Re-evaluate the baseline + rotation whenever the scanner hands
        // us a fresh result. `scanComplete` flipping true is what unlocks
        // the FIRST baseline seed (so the first scan never strobes
        // "New"). `itemCount` changing covers every later update —
        // PhotoLibraryChangeMonitor → incrementalRefresh → new count, or
        // a per-category rescan, or a delete that drops the count.
        .onChange(of: scanComplete) { _, _ in
            seedBaselineIfNeeded()
            startRotationIfNeeded()
        }
        .onChange(of: itemCount) { _, _ in
            seedBaselineIfNeeded()
            startRotationIfNeeded()
        }
    }

    /// Cancels any in-flight rotation and starts a fresh one when the
    /// card is currently surfacing new content. Staggered initial delay
    /// so a dashboard full of "new" cards doesn't pulse in lockstep.
    ///
    /// Cadence: ~6 seconds per swap. The previous 2.5s interval read as
    /// frantic — the user reported the page felt "buggy and fast" with
    /// every tile strobing the "New" pill on top of an unstable
    /// SwiftUI cross-fade. 6s gives the user a clear two-beat read of
    /// each label (count → New → count) without burning the eye.
    /// Cross-fade extended to 0.6s for the same reason — the swap
    /// itself becomes the moment, not a flicker.
    private func startRotationIfNeeded() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        showingNewIndicator = false
        guard hasNewContent else { return }
        let stagger = Double.random(in: 0.4...2.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger) {
            // Re-check on the delayed tick — itemCount may have moved
            // again or the user may have already navigated away.
            guard hasNewContent else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                showingNewIndicator = true
            }
            rotationTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.6)) {
                    showingNewIndicator.toggle()
                }
            }
        }
    }

    // MARK: - Image-First Layout

    private var imageFirstLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category title
            Text(title)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(.foreground)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            // Two side-by-side photo previews with the count pill
            // overlaid on the bottom-right of the second (right) tile.
            // The pill sits inside the photo row's bounding box so it
            // visually attaches to the right thumbnail rather than the
            // card chrome.
            ZStack(alignment: .bottomTrailing) {
                photoRow
                    .padding(.horizontal, 12)

                // Info badge — inset ~12pt from the right thumbnail's
                // bottom-right corner. Trailing offset = card padding (12)
                // + visual inset (12) = 24.
                infoBadge
                    .padding(.trailing, 24)
                    .padding(.bottom, 12)
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // GlassPanel = the same elite surface the Email category rows use:
        // .ultraThinMaterial + a top→bottom white gradient + a sheen border
        // and its own soft drop shadow. The cards now read as bright glass
        // tiles, with the nav-bar gradient providing the canvas anchor.
        .background(GlassPanel(cornerRadius: cardRadius, elevation: .card))
        .clipShape(RoundedRectangle(cornerRadius: cardRadius))
        .contentShape(RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Photo Row — exactly two thumbnails
    //
    // Every populated card uses the same 1×2 layout to match the
    // Duplicates / Similar Photos reference. We take the first two
    // representative thumbnails from `assetIds` (same source the older
    // 3×2 grid used) and render them side-by-side with a small gap.
    // The count pill is overlaid on the right tile by the parent
    // `imageFirstLayout`. If only one asset is available, we render a
    // single full-width tile rather than leaving an empty slot — the
    // pill still anchors to the bottom-right and reads correctly.
    // The card body routes zero-item categories to `compactRowLayout`,
    // so the 0-case is impossible here.
    private var photoRow: some View {
        let realIds = Array(assetIds.prefix(2))
        let count = realIds.count

        return GeometryReader { geo in
            let spacing: CGFloat = 8
            let columns = max(count, 1)
            let tileWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { idx in
                    let assetId = realIds[idx]
                    PhotoThumbnailView(
                        assetIdentifier: assetId,
                        size: CGSize(width: 600, height: 600),
                        onUnloadable: { onAssetUnloadable?(assetId) }
                    )
                    .frame(width: tileWidth, height: geo.size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(height: 168)
        .clipped()
    }

    // MARK: - Info Badge

    private var infoBadge: some View {
        HStack(spacing: 6) {
            if isAllClear {
                // All-clear state reads as a celebratory chip, not a count.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                Text(BCLoc.allClear.tr)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            } else if isScanning && itemCount == 0 {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)

                Text("Scanning…")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            } else {
                // Primary line rotates between the stats count ("87
                // Photos") and a "New Photos" tag whenever the
                // on-device scanner has surfaced more items than the
                // user has acknowledged. .contentTransition(.opacity)
                // gives the swap a soft cross-fade tied to the
                // animation in `startRotationIfNeeded`.
                let primaryText: String = {
                    if hasNewContent && showingNewIndicator {
                        return "New \(itemLabel)"
                    }
                    return "\(itemCount) \(itemLabel)"
                }()

                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .contentTransition(.opacity)
                        .id(primaryText)
                        .transition(.opacity)

                    if storageBytes > 0 {
                        Text(formattedStorage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                ChevronGlyph(size: .small, tint: .white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isAllClear ? Color.success : accentColor)
        )
        .shadow(
            color: (isAllClear ? Color.success : accentColor).opacity(0.35),
            radius: 8,
            y: 3
        )
    }

    // MARK: - Compact Row Layout (all clear / empty / scanning)

    private var compactRowLayout: some View {
        HStack(spacing: 14) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isAllClear ? Color.success.opacity(0.1) : accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)

                if isAllClear {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.success)
                        .scaleEffect(allClearScale)
                } else if isScanning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(accentColor)
                }
            }

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(.foreground)

                Text(compactSubtitle)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(isAllClear ? .success : .mutedForeground)
            }

            Spacer()

            // Exact match for `EmailCategoryRow`'s chevron: 13pt heavy,
            // #A1A1AA. Every row across Photos / Videos / Email reads
            // with the same arrow weight + color.
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.mutedForeground)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same GlassPanel surface as the image-first layout — bright white
        // glass tiles against the BitePal-gradient nav bar below.
        .background(GlassPanel(cornerRadius: DesignTokens.Radius.xl, elevation: .card))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    private var compactSubtitle: String {
        if isScanning { return "Scanning..." }
        if isAllClear { return BCLoc.allClear.tr }
        return "Tap to view"
    }
}
