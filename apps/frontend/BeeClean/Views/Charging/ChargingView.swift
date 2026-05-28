import SwiftUI

// MARK: - Cleanup Destinations
enum CleanupDestination: Hashable {
    case duplicatePhotos, similarPhotos, similarScreenshots
    case screenshots, blurryPhotos, otherPhotos
    case similarVideos, screenRecordings, shortRecordings, longVideos
    case guidedCleanup
    /// Per-source cleanup ("Snapchat", "Instagram", etc.) — backed by
    /// `MediaGridView.sourceFiltered(_:source:)`. One case parameterized
    /// by `PhotoSource` covers every social-app card.
    case sourceFiltered(PhotoSource)
}

// MARK: - Quick Access Destinations (Home-local pushes)
enum QuickAccessDestination: Hashable {
    case photos
    case videos
    case email
    case compress
}

// MARK: - Charging View (Dashboard)
struct ChargingView: View {
    @State private var selectedCleanup: CleanupDestination?
    @State private var quickAccessDestination: QuickAccessDestination?
    @State private var showCleanupHistory = false
    @State private var totalBytes: Int64 = 0
    @State private var availableBytes: Int64 = 0
    @Environment(SimilarPhotosStore.self) private var similarVM
    @ObservedObject private var statsManager = HiveStatsManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var beeVM = BeeViewModel.shared
    @ObservedObject private var taskManager = CleanupTaskManager.shared
    @State private var categories: [MediaCategory] = []
    @State private var resolvedPlan: TodayCleanupPlan?
    /// Derived directly from `similarVM.dashboardSnapshot` + `statsManager.cleanScore`
    /// so the Observation framework tracks both and triggers body invalidation when
    /// either changes. Using @State + .onChange broke the observation chain because
    /// the body never read `dashboardSnapshot` directly.
    private var todayPlan: TodayCleanupPlan {
        CleanupOrchestrator.shared.buildTodayPlan(
            from: similarVM.dashboardSnapshot,
            cleanScore: statsManager.cleanScore
        )
    }

    /// Plan shown on the dashboard card. Structure/visibility (the Quick
    /// Cleanup row + Start CTA) always comes from the lightweight `todayPlan`
    /// so the card never collapses when the resolved pool is thin. When a
    /// viable resolved plan exists, overlay its real storage + XP so the row
    /// reflects what Start Quick Cleanup will actually award.
    private var cardPlan: TodayCleanupPlan {
        let base = todayPlan
        // The task row's MB comes from the PERSISTED active task (stable across
        // launches). The big "total space" number stays from `base` (overall
        // clutter). Fall back to the resolved plan, then base.
        let roundBytes = taskManager.activeTask?.estimatedBytes
            ?? (resolvedPlan?.tasks.isEmpty == false ? resolvedPlan?.roundBytes : nil)
            ?? base.roundBytes
        guard !base.tasks.isEmpty else { return base }
        return TodayCleanupPlan(
            totalRecoverableBytes: base.totalRecoverableBytes,
            roundBytes: roundBytes,
            tasks: base.tasks,
            estimatedSeconds: base.estimatedSeconds,
            beeHealthScore: base.beeHealthScore,
            subtitle: base.subtitle,
            checkpointCount: base.checkpointCount
        )
    }

    /// Coins shown for the active task — from the persisted snapshot, falling
    /// back to the resolved plan estimate.
    private var potentialCoins: Int {
        if let active = taskManager.activeTask { return active.estimatedCoins }
        guard let resolved = resolvedPlan, !resolved.tasks.isEmpty else { return 0 }
        return ProgressMath.estimatedTaskCoins(for: resolved.tasks)
    }

    // The HiveScoreCard's Y position in global coordinates drives the
    // header-chrome clip. The preference set inside the ScrollView
    // propagates up to ChargingView's body where `.onPreferenceChange`
    // captures it. Preferences only flow child→parent, so sibling views
    // (like HeaderChromeOverlay) can't read them directly — the value
    // must be read here and passed down.
    @State private var dashboardScrollOffset: CGFloat = 10000

    private var clutterBytes: Int64 {
        // Read from the precomputed snapshot — same dedup logic as the
        // legacy `store.totalClutterBytes` computed property, but the
        // walk runs once per scan-result mutation instead of once per
        // body invalidation. See `recomputeDashboardSnapshot()`.
        max(similarVM.dashboardSnapshot.totalClutterBytes, 0)
    }


    private var usedBytes: Int64 {
        max(totalBytes - availableBytes, 0)
    }

    /// Progress fed to the bee mascot animation + green bar meter.
    /// Derived from `beeVM.stage` (the single source of truth that applies
    /// decay, momentum, byte floors and the "never cleaned → stage1" rule)
    /// so the mascot, bar, and HiveScoreCard headline always agree.
    /// Each value lands in the middle of its stage band in
    /// BeeStageAnimationConfig.stage(for:), so the bar settles cleanly
    /// inside the matching stage frame range.
    private var stageProgress: Double {
        switch beeVM.stage {
        case .stage1: return 0.30
        case .stage2: return 0.63
        case .stage3: return 0.79
        case .stage4: return 0.91
        case .stage5: return 0.98
        }
    }


    var body: some View {
        GeometryReader { geo in
            let heroHeight = geo.size.height * 0.50
            let safeTop = geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                BeeGreetingView(
                    heroHeight: heroHeight,
                    safeAreaTop: safeTop,
                    progress: stageProgress,
                    isAnimating: true
                )
                .allowsHitTesting(false)
                .zIndex(0)
                .animation(.spring(response: 0.65, dampingFraction: 0.82), value: beeVM.stage)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        Color.clear
                            .frame(height: heroHeight)
                            .allowsHitTesting(false)

                        TodaysCleanupCard(
                            plan: cardPlan,
                            stage: beeVM.stage,
                            potentialCoins: potentialCoins,
                            activeTask: taskManager.activeTask,
                            recentCompleted: taskManager.recentCompleted,
                            onStartCleanup: handleStartCleanup,
                            onViewAll: { showCleanupHistory = true }
                        )
                        .padding(.horizontal, 6)
                        .overlay(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        dashboardScrollOffset = proxy.frame(in: .global).minY
                                    }
                                    .onChange(of: proxy.frame(in: .global).minY) { _, newY in
                                        dashboardScrollOffset = newY
                                    }
                            }
                        )

                        QuickAccessCard(
                            onPhotos: { quickAccessDestination = .photos },
                            onVideos: { quickAccessDestination = .videos },
                            onEmail: { quickAccessDestination = .email },
                            onCompress: { quickAccessDestination = .compress }
                        )
                        .padding(.horizontal, 6)
                        .padding(.top, 0)

                        // Per-source cleanup row — one card per social app
                        // the user has saved media from (Snapchat / Instagram /
                        // WhatsApp / etc.). Reads from the precomputed
                        // dashboard snapshot so the row is O(1) to render and
                        // appears/refreshes as Tier 2 EXIF enrichment lands.
                        SourceAppCleanupRow(
                            snapshot: similarVM.dashboardSnapshot,
                            onSelect: { source in
                                selectedCleanup = .sourceFiltered(source)
                            }
                        )
                        .padding(.bottom, 100)

                        ForEach(categories) { category in
                            MediaCleanupCard(category: category)
                                .padding(.horizontal, DesignTokens.Spacing.xl)
                        }
                    }
                    .padding(.bottom, 180)
                }
                .scrollContentBackground(.hidden)
                .zIndex(1)

                // Header chrome (BeeBuddy name, streak, settings) sits in
                // FRONT of the ScrollView so the buttons receive taps —
                // ScrollView's gesture recognizers would otherwise eat
                // every touch in the hero area. `clipShape` (NOT mask)
                // is the key here: it clips both rendering AND hit-
                // testing to the visible region (the slice above the
                // card's top edge). So once the card scrolls over a
                // button, that button is both invisible and inert — no
                // separate `.allowsHitTesting` toggle needed.
                //
                // Lives in its own struct (HeaderChromeOverlay) so the
                // scroll-offset @State is local — the parent
                // ChargingView body doesn't re-render on scroll.
                HeaderChromeOverlay(safeTop: safeTop, offset: dashboardScrollOffset)
                    .zIndex(2)
            }
            .background(Color.clear)
            .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedCleanup) { dest in
            // Belt-and-suspenders `.hidesBottomNavBar()` on every push
            // site — see the comment in PhotoCleanupView/VideoCleanupView
            // for why the modifier on the view body alone is not enough.
            switch dest {
            case .duplicatePhotos: DuplicatePhotosView().hidesBottomNavBar()
            case .similarPhotos: SimilarPhotosView().hidesBottomNavBar()
            case .similarScreenshots: ScreenshotsView().hidesBottomNavBar()
            case .screenshots: MediaGridView(config: .screenshots(similarVM)).hidesBottomNavBar()
            case .blurryPhotos: MediaGridView(config: .blurryPhotos(similarVM)).hidesBottomNavBar()
            case .otherPhotos: MediaGridView(config: .otherPhotos(similarVM)).hidesBottomNavBar()
            case .similarVideos: SimilarVideosView().hidesBottomNavBar()
            case .screenRecordings: MediaGridView(config: .screenRecordings(similarVM)).hidesBottomNavBar()
            case .shortRecordings: MediaGridView(config: .shortRecordings(similarVM)).hidesBottomNavBar()
            case .longVideos: MediaGridView(config: .longVideos(similarVM)).hidesBottomNavBar()
            case .guidedCleanup: GuidedCleanupView(plan: resolvedPlan ?? todayPlan, store: similarVM).hidesBottomNavBar()
            case .sourceFiltered(let source): MediaGridView(config: .sourceFiltered(similarVM, source: source)).hidesBottomNavBar()
            }
        }
        .navigationDestination(item: $quickAccessDestination) { dest in
            // Hide the floating nav bar across every Quick Access
            // push. The bar belongs to the dashboard only — clicking
            // into Photos / Videos / Emails / Compress should give
            // those screens the full canvas, never overlap their
            // bottom content. Restored after the earlier "stay
            // visible" experiment because the bar was reappearing
            // over category lists.
            switch dest {
            case .photos: PhotoCleanupView().hidesBottomNavBar()
            case .videos: VideoCleanupView().hidesBottomNavBar()
            case .email: EmailView(showsBackButton: true).hidesBottomNavBar()
            case .compress: CompressView(showsBackButton: true).hidesBottomNavBar()
            }
        }
        .navigationDestination(isPresented: $showCleanupHistory) {
            CleanupHistoryView().hidesBottomNavBar()
        }
        .onAppear {
            // Force-clear ONLY when no pushed destination is currently
            // active. The previous unconditional clear was firing
            // during the iOS pop-animation window (when SwiftUI briefly
            // re-runs the parent's onAppear before the child view is
            // truly torn down), wiping the child's legitimate hide
            // request and leaving the BottomNavBar visible on screens
            // like "Short Recordings". Gating on the destination
            // bindings restores the original belt-and-suspenders
            // intent (clean slate on real dashboard return) without
            // racing the pop animation.
            if selectedCleanup == nil && quickAccessDestination == nil {
                BottomNavBarVisibility.shared.forceClear()
            }
            // Refresh the daily Clean Bar whenever the dashboard reappears —
            // e.g. returning from a guided cleanup — so the bar + bee stage
            // reflect the latest server-reconciled state.
            Task { await ProgressManager.shared.loadProgress() }
        }
        // Hide the floating nav bar the instant a Cleanup destination
        // pushes, restore on pop.
        .onChange(of: selectedCleanup) { oldValue, newValue in
            if oldValue == nil && newValue != nil {
                BottomNavBarVisibility.shared.requestHide()
            } else if oldValue != nil && newValue == nil {
                BottomNavBarVisibility.shared.releaseHide()
            }
        }
        // Same hide rule for Quick Access destinations (Photos / Videos
        // / Emails / Compress). The pushed child also calls
        // `.hidesBottomNavBar()` for belt-and-suspenders, but firing the
        // request from THIS view at push-time closes the window where the
        // bar visibly flickered between the push animation and the
        // child's `.task` block running. Mirrors the rule above so back
        // navigation pops the bar back in synchronously.
        .onChange(of: quickAccessDestination) { oldValue, newValue in
            // Use the HARD override instead of the counter-based path
            // so the nav bar can never reappear over a Quick Access
            // category screen, even if a SwiftUI lifecycle race lets
            // the counter drop to zero between the parent's release
            // and the child's request. `forceClear()` on root return
            // automatically resets the flag.
            if oldValue == nil && newValue != nil {
                BottomNavBarVisibility.shared.setForceHidden(true)
            } else if oldValue != nil && newValue == nil {
                BottomNavBarVisibility.shared.setForceHidden(false)
            }
        }
        .task {
            ThemeManager.shared.refresh()
            statsManager.refreshStreak()
            loadDeviceStorage()
            // Compute the full photo library footprint (the Apple-
            // equivalent total) so the dashboard can compare against
            // our clutter total and reconcile the "Apple says 50 GB
            // but BeeClean says 45" undercount.
            PhotoLibraryBytesService.shared.refreshIfStale()

            // bootstrap() is the only scan entry point the view should call:
            // it surfaces cached data immediately, attaches the library
            // change observer, and runs any needed scan in a store-owned
            // Task that SURVIVES tab switches. That's the fix for "scan
            // restarts every time I return to home" — a view-parented
            // Task would cancel the instant the user navigates away.
            similarVM.bootstrap()
            await statsManager.pullFromBackend()
            // Load the PERSISTED active task (Shuffling System) instead of
            // regenerating on every appearance. Only generates when none exists.
            await taskManager.loadActiveTask(store: similarVM, cleanScore: statsManager.cleanScore)
        }
        .onChange(of: similarVM.dashboardSnapshot) { _, newSnapshot in
            // Library changed (e.g. manual deletes) — re-validate the active
            // task and rotate only if it's no longer viable.
            Task { await taskManager.validateActiveTask(store: similarVM, cleanScore: statsManager.cleanScore) }
            // Sync the "total space to clean" snapshot to the backend.
            // Throttled inside the service so rapid mid-scan updates
            // don't hammer the API.
            ScanSnapshotService.shared.sync(snapshot: newSnapshot)
            // Re-pull the Apple-equivalent library total so the headline
            // stays honest when a scan reveals new clutter or a cleanup
            // shrinks the library. Service throttles its own recompute.
            PhotoLibraryBytesService.shared.refreshIfStale()
        }
    }

    // (The header chrome view has moved out of ChargingView entirely —
    // see `HeaderChromeOverlay` near the bottom of this file. Owning
    // its own scroll-offset @State is what keeps scroll redraws scoped
    // to the overlay instead of the whole view.)

    private func handleStartCleanup() {
        // Launch the active task: resolve its executable plan (cached by the
        // manager, else freshly resolved by the existing generator).
        let plan = taskManager.resolvedPlanForLaunch(store: similarVM, cleanScore: statsManager.cleanScore)
        guard !plan.tasks.isEmpty else { return }
        resolvedPlan = plan
        selectedCleanup = .guidedCleanup
    }

    private func loadDeviceStorage() {
        // Volume capacity query is blocking I/O — keep it off the main thread.
        DispatchQueue.global(qos: .utility).async {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let keys: Set<URLResourceKey> = [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
            ]
            guard let values = try? home.resourceValues(forKeys: keys) else { return }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            DispatchQueue.main.async {
                totalBytes = total
                availableBytes = available
            }
        }
    }
}

// MARK: - Source-App Cleanup Row
//
// Horizontal row of per-source cards ("Snapchat", "Instagram", etc.) that
// appears on the Charging tab between QuickAccessCard and the main
// category list. Renders only sources where the user actually has assets
// (snapshot.sourceCardCounts[source] > 0) so the row grows organically
// as Tier 2 EXIF enrichment populates the index.
//
// Reads everything from the precomputed `DashboardSnapshot` — body work
// is O(activeSources) which is ≤6, not O(library size).
private struct SourceAppCleanupRow: View {
    let snapshot: DashboardSnapshot
    let onSelect: (PhotoSource) -> Void

    private var activeSources: [PhotoSource] {
        PhotoSource.allCases.filter { source in
            source.isExternal && (snapshot.sourceCardCounts[source] ?? 0) > 0
        }
    }

    var body: some View {
        if !activeSources.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cleanup by App")
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(.foreground)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(activeSources, id: \.self) { source in
                            SourceAppCard(
                                source: source,
                                count: snapshot.sourceCardCounts[source] ?? 0,
                                bytes: snapshot.sourceCardBytes[source] ?? 0,
                                onTap: { onSelect(source) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct SourceAppCard: View {
    let source: PhotoSource
    let count: Int
    let bytes: Int64
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                SocialSourceBadge(source: source, size: 44)
                Text(source.displayName)
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(.foreground)
                Text("\(count) · \(formatBytes(bytes))")
                    .font(.system(size: 11))
                    .foregroundColor(.foregroundSecondary)
            }
            .frame(width: 124, height: 132)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(source.brandColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(source.brandColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header Chrome Overlay
//
// Receives `offset` (the HiveScoreCard's global-Y) from the parent.
// Sits IN FRONT of the ScrollView (zIndex 2) so its buttons reliably
// receive taps. `clipShape` (NOT mask) clips both rendering AND
// hit-testing, so once the card scrolls over a button it becomes
// invisible AND inert in one step.
private struct HeaderChromeOverlay: View {
    let safeTop: CGFloat
    let offset: CGFloat

    @ObservedObject private var theme = ThemeManager.shared
    @State private var showStreakSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                NameEditOverlay()
                    .padding(.leading, DesignTokens.Spacing.xl)
                    .padding(.top, safeTop + DesignTokens.Spacing.sm)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        HapticManager.shared.streakReveal()
                        showStreakSheet = true
                    } label: {
                        StreakBadge()
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        let isNight = theme.isNightMode
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(
                                isNight
                                    ? Color(hex: "C7C7CC")
                                    : Color(hex: "6E6E73")
                            )
                            .frame(width: 36, height: 36)
                            .background(FuturisticPillSurface(isNight: isNight))
                            .clipShape(Circle())
                            .background(
                                Circle()
                                    .fill(Color(hex: "F0D58A"))
                                    .opacity(isNight ? 0.16 : 0)
                                    .blur(radius: 10)
                                    .scaleEffect(1.15)
                            )
                            .shadow(
                                color: Color.black.opacity(isNight ? 0.40 : 0.10),
                                radius: isNight ? 12 : 7,
                                x: 0,
                                y: isNight ? 5 : 2
                            )
                    }
                }
                .padding(.trailing, 20)
                .padding(.top, safeTop + 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(HeaderChromeClip(visibleHeight: max(0, offset)))
        .fullScreenCover(isPresented: $showStreakSheet) {
            StreakDetailView(onClose: { showStreakSheet = false })
        }
    }
}

// Clips the header chrome to a top-aligned rectangle of `visibleHeight`.
// Unlike `.mask`, `clipShape` clips hit-testing too, so once the card
// scrolls over a button the button stops receiving taps automatically —
// no parallel `.allowsHitTesting` toggle to keep in sync.
private struct HeaderChromeClip: Shape {
    var visibleHeight: CGFloat

    var animatableData: CGFloat {
        get { visibleHeight }
        set { visibleHeight = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(0, visibleHeight)
        ))
    }
}

// MARK: - Name Edit Overlay
//
// The dashboard name was previously tappable — tapping the headline
// "BeeBuddy" / custom name opened the EditBeeNameSheet inline. Per the
// BitePal-aligned redesign the rename surface moved into
// Settings → "Bee's name" (see `SettingsView.beeNameRow`). The dashboard
// label stays display-only for opening the rename sheet, BUT a tap
// still fires a light haptic click — a small "psychological lock" cue
// that tells the user "you tapped something" without taking them
// anywhere. Helps the headline read as a deliberate, tactile surface
// even though the actual edit lives elsewhere.
private struct NameEditOverlay: View {
    @AppStorage("userName") private var beeName = ""

    private var displayName: String {
        let trimmed = beeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BeeBuddy" : trimmed
    }

    var body: some View {
        Text(displayName)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.vertical, 6)
            // Strict tap hit-region — text glyph only, no surrounding
            // dead space, so a stray finger during nav transitions can't
            // fire the haptic. Same `.rect` shape the original button
            // path used.
            .contentShape(.rect)
            .onTapGesture {
                HapticManager.shared.impact(.light)
            }
    }
}

#Preview {
    ZStack {
        Color.honeyCanvas.ignoresSafeArea()
        ChargingView()
    }
}
