import SwiftUI

// MARK: - Progress Tab — Cal AI / Quittr-inspired shell
//
// Exactly three major elements:
//  1. Top row: Phone Health card + Clean Streak / Reset card
//  2. Clean Progress line graph (hero)
//  3. Next Cleanup Target action card
//
// Home is the action loop; Progress is the proof/challenge loop.
// Data sources:
//  - HiveStatsManager.shared — cleanScore, currentStreak, lastSevenDays
//  - CleanupOrchestrator.shared.buildTodayPlan(…) — checkpointCount,
//    formattedRoundBytes for the Next Cleanup Target card
//  - SimilarPhotosStore.dashboardSnapshot — feeds the orchestrator
// The line graph uses a local trend derived from current cleanScore;
// no backend history is added yet — UI shell only.
struct ProgressTabView: View {
    @ObservedObject private var stats = HiveStatsManager.shared
    @Environment(SimilarPhotosStore.self) private var similarVM
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedRange: ProgressRange = .sevenDay
    @State private var selectedPointIndex: Int? = nil
    @State private var showGuidedCleanup: Bool = false
    @State private var resolvedPlan: TodayCleanupPlan? = nil
    @State private var activities: [ActivityEntry] = []
    /// Drives the dimming hint during pull-to-refresh. One flag
    /// covers both the graph and the Recent Wins module.
    @State private var isRefreshing: Bool = false
    /// Drives the streak-detail sheet from the Recent Wins streak chip.
    @State private var showStreakDetail: Bool = false
    /// Headline bytes value that the hero `Text` is bound to. Starts at
    /// 0 and animates up to the period total on appear / range change —
    /// the Robinhood "roll-in" feel. Combined with
    /// `.contentTransition(.numericText())` on the `Text`, the digits
    /// tumble through intermediate values rather than snapping.
    @State private var heroBytesAnimated: Double = 0
    /// Throttle for `reloadFromBackend` — guards against rapid tab
    /// switching firing a redundant 365-day activity log pull every
    /// time the user lands on Progress. Pull-to-refresh bypasses this
    /// (it has its own entry point); the 30s window only affects
    /// automatic .task / scene-phase syncs.
    @State private var lastBackendSyncAt: Date = .distantPast
    private static let backendSyncThrottle: TimeInterval = 30

    // MARK: - User-pickable chart palettes
    //
    // Persisted across launches via @AppStorage so a user's color choice
    // survives a relaunch. Defaults to `.honey` (the original orange palette)
    // so existing users see zero visual change until they actively pick a
    // new color via the corner palette dot.
    //
    // Hero and Best Day track independently — the user can run the big
    // chart in cobalt and the Best Day mini in coral if they want.
    // Defaults: the three primary cards (Activity hero / XP /
    // Segmentation) all land on `.liquidGlass` so the dashboard ships
    // with a single unified "frost glass" tone across every chart.
    // Items + Best Day sparklines pick their own historic defaults so
    // the per-stat color identity (green for items, honey for best
    // day) survives unless the user explicitly recolors them.
    @AppStorage("progress.heroChartPaletteRaw") private var heroChartPaletteRaw: String = ChartPalette.liquidGlass.rawValue
    @AppStorage("progress.bestDaySparkPaletteRaw") private var bestDaySparkPaletteRaw: String = ChartPalette.honey.rawValue
    /// Items Cleaned sparkline palette — defaults to `.forest` to
    /// preserve the green-up visual the column had when it was
    /// tinted by delta direction. User can override via the
    /// per-stat color dot picker.
    @AppStorage("progress.itemsSparkPaletteRaw") private var itemsSparkPaletteRaw: String = ChartPalette.forest.rawValue
    /// XP card palette — defaults to `.liquidGlass` so the XP bars
    /// match the hero card's frost-glass tone out of the box. User
    /// can override via the chart customization sheet.
    @AppStorage("progress.xpPaletteRaw") private var xpPaletteRaw: String = ChartPalette.liquidGlass.rawValue
    /// Segmentation card palette OVERRIDE. Defaults to
    /// `.liquidGlass` (a fixed palette, not the sentinel) so the
    /// segmentation chart ships with the same liquid-glass tone the
    /// other two cards use; users can flip it back to Auto from the
    /// chart customization sheet to get per-scope tinting.
    @AppStorage("progress.segmentationPaletteRaw") private var segmentationPaletteRaw: String = ChartPalette.liquidGlass.rawValue

    /// Persisted order of the four Progress cards (activity / xp /
    /// segmentation / leaderboard). BitePal-style reorder: long-press
    /// a card → context menu with "Move Up" / "Move Down". The user's
    /// pick survives a relaunch. CSV of `ProgressCardKind.rawValue`
    /// so a corrupt value just falls back to the default order.
    @AppStorage("progress.cardOrder") private var cardOrderRaw: String =
        "activity,xp,segmentation,leaderboard"
    /// Single unified customization sheet — the top-right paint button
    /// in the Progress header opens this. One surface that lets the user
    /// pick which chart to recolor, then pick the palette. Replaces
    /// three per-chart corner dots that each owned a separate sheet.
    @State private var showingChartCustomization = false

    /// Materialized palette for the hero chart. Falls back to `.honey`
    /// on any decode miss (e.g., a corrupted UserDefaults value or a
    /// future palette case that was rolled back) so the chart never
    /// renders without a color.
    private var heroPalette: ChartPalette {
        get { ChartPalette(rawValue: heroChartPaletteRaw) ?? .honey }
    }

    private var bestDayPalette: ChartPalette {
        get { ChartPalette(rawValue: bestDaySparkPaletteRaw) ?? .honey }
    }

    private var itemsPalette: ChartPalette {
        get { ChartPalette(rawValue: itemsSparkPaletteRaw) ?? .forest }
    }

    /// `Binding<ChartPalette>` adapters so the picker sheet can write
    /// the user's choice straight back into @AppStorage. Read decodes
    /// from raw, write encodes back — single source of truth stays in
    /// UserDefaults.
    private var heroPaletteBinding: Binding<ChartPalette> {
        Binding(
            get: { ChartPalette(rawValue: heroChartPaletteRaw) ?? .honey },
            set: { heroChartPaletteRaw = $0.rawValue }
        )
    }

    private var bestDayPaletteBinding: Binding<ChartPalette> {
        Binding(
            get: { ChartPalette(rawValue: bestDaySparkPaletteRaw) ?? .honey },
            set: { bestDaySparkPaletteRaw = $0.rawValue }
        )
    }

    private var itemsPaletteBinding: Binding<ChartPalette> {
        Binding(
            get: { ChartPalette(rawValue: itemsSparkPaletteRaw) ?? .forest },
            set: { itemsSparkPaletteRaw = $0.rawValue }
        )
    }

    /// User-selected XP card palette. Falls back to `.honey` on a
    /// decode miss for the same reason heroPalette does.
    private var xpPalette: ChartPalette {
        ChartPalette(rawValue: xpPaletteRaw) ?? .honey
    }

    private var xpPaletteBinding: Binding<ChartPalette> {
        Binding(
            get: { ChartPalette(rawValue: xpPaletteRaw) ?? .honey },
            set: { xpPaletteRaw = $0.rawValue }
        )
    }

    /// Segmentation palette binding. `nil` slot in the picker maps to
    /// "use the per-scope auto palette" (we encode that with an empty
    /// string in @AppStorage so we don't need a separate flag). The
    /// sheet treats the absence of a stored value as "Auto" and lets
    /// the user pick a fixed palette to override it.
    private var segmentationPaletteBinding: Binding<ChartPalette> {
        Binding(
            get: { ChartPalette(rawValue: segmentationPaletteRaw) ?? .honey },
            set: { segmentationPaletteRaw = $0.rawValue }
        )
    }
    /// Namespace for the sliding-pill range selector. Lets the dark
    /// capsule glide between range slots via `matchedGeometryEffect`
    /// instead of snapping.
    @Namespace private var rangePillNS
    /// Second sliding-pill namespace for the BreakdownCard's mirror
    /// of the range selector. Two instances of `rangePillRow` on
    /// screen at once need separate namespaces — otherwise both
    /// would think they own the same `matchedGeometryEffect` id and
    /// fight for the same pill (visual jitter or no pill at all).
    /// Both rows drive the same `selectedRange` state, so tapping
    /// either flips both cards in lockstep.
    @Namespace private var breakdownRangePillNS
    /// Active category chip. `nil` = "All" (every tagged + untagged
    /// entry contributes). Setting this filters every data series
    /// (`activitySeries`, `previousPeriodSeries`, `itemsSparklineSeries`,
    /// `itemsForRange`) so the hero number, delta chip, Best Day, and
    /// Recent Wins stats all narrow to the selected category in
    /// lockstep — same Bloomberg-style "scope a symbol, change the
    /// timeframe" workflow.
    @State private var selectedProgressCategory: SavedFindSourceCategory?
    /// Independent time-scope for the BreakdownCard. Decoupled from
    /// `selectedRange` (top card) so the user can hold the chart on
    /// 30D while inspecting the breakdown at 1D, or vice versa.
    /// Defaults to 7D to match the top card on cold-open — same
    /// initial window, then each card can be flipped independently.
    @State private var selectedBreakdownRange: ProgressRange = .sevenDay
    /// Active top-level segment for the segmentation card. `nil` = All
    /// (aggregate across every Quick Access category). When non-nil,
    /// every series + headline + tooltip is filtered to that single
    /// top-level. Mirrors how Cal AI lets you scope its dashboard.
    @State private var selectedBreakdownTopLevel: TopLevelCategory? = nil
    /// Active leaf inside the chosen top-level (Duplicates inside Photos,
    /// Long Videos inside Videos, Photo Compression inside Compression).
    /// `nil` = roll up across every leaf in the active top-level.
    /// Reset whenever the top-level changes so a stale leaf from a prior
    /// scope can never narrow the chart silently.
    @State private var selectedBreakdownLeaf: SavedFindSourceCategory? = nil
    /// Scrub index for the segmentation chart — independent from the top
    /// chart's `selectedPointIndex` so dragging one chart never moves
    /// the other.
    @State private var selectedBreakdownPointIndex: Int? = nil

    /// XP card range toggle. Week / Month only — year is intentionally
    /// excluded (an XP rollup over 12 months collapses every weekly
    /// nuance into a flat trend that doesn't motivate). Defaults to
    /// week so the user lands on the live "this week vs last week"
    /// comparison.
    @State private var selectedXpRange: XpRange = .week
    /// Bar tapped on the XP card — drives the highlighted bar +
    /// scrubbed headline. `nil` = aggregate total.
    @State private var selectedXpIndex: Int? = nil

    private let cal = Calendar.current

    // MARK: - Derived

    private var todayPlan: TodayCleanupPlan {
        CleanupOrchestrator.shared.buildTodayPlan(
            from: similarVM.dashboardSnapshot,
            cleanScore: stats.cleanScore
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            canvas
            scrollContent
            // Soft frosted blur applied to the dashboard while the
            // Chart Colors sheet is up. Keeps the cards behind the
            // sheet from competing with the picker.
            chartCustomizationBlurOverlay
        }
        .animation(.easeInOut(duration: 0.18), value: showingChartCustomization)
        .task { await reloadFromBackend() }
        .onAppear { rollHeroBytes() }
        // Re-roll on range switch so the headline reads as a fresh
        // commit rather than a snap — same dopamine cue Robinhood uses
        // when flipping between 1D / 1W / 1Y on the portfolio screen.
        .onChange(of: selectedRange) { _, _ in rollHeroBytes() }
        // Re-roll once the backend activity log lands so the headline
        // reflects the freshest period total, not the stale fallback
        // that rendered before `activities` populated. Keying on the
        // count (an Int) sidesteps making `ActivityEntry` Equatable
        // for this one onChange.
        .onChange(of: activities.count) { _, _ in rollHeroBytes() }
        // Celebrate the moment the user crosses their daily commit
        // while they're already on the Progress tab — a success-
        // notify fires when `dailyMetCommitment` transitions
        // false→true, but never the other way and never on initial
        // load. Reads like Robinhood's "alert hit" cue when a price
        // crosses a target.
        .onChange(of: stats.dailyMetCommitment) { oldValue, newValue in
            if !oldValue && newValue {
                HapticManager.shared.actionSuccess()
            }
        }
        .modifier(
            ProgressBackendSync(
                lifetimeBytes: stats.lifetimeBytesSaved,
                lifetimeItems: stats.lifetimeItemsCleaned,
                currentStreak: stats.currentStreak,
                scenePhase: scenePhase,
                onLightSync: { Task { await reloadFromBackend(includeStats: false) } },
                onFullSync:  { Task { await reloadFromBackend(includeStats: true)  } }
            )
        )
        .fullScreenCover(isPresented: $showGuidedCleanup) {
            NavigationStack {
                GuidedCleanupView(
                    plan: resolvedPlan ?? todayPlan,
                    store: similarVM
                )
            }
        }
        // Match Home's presentation exactly: `.fullScreenCover`
        // + `onClose` so StreakDetailView renders its built-in
        // slash drag-handle at the top center. Without `onClose`
        // the handle hides itself, and the user is stranded with
        // no visible dismiss affordance (only the system swipe-
        // down gesture, which isn't discoverable).
        .fullScreenCover(isPresented: $showStreakDetail) {
            StreakDetailView(onClose: { showStreakDetail = false })
        }
        // Single unified chart-customization sheet, opened from the
        // paint button at the top right of the Progress header. Lets the
        // user pick which of the three charts to recolor inline — one
        // sheet, one surface, three accordion rows. The translucent
        // material keeps the charts visible beneath so each palette
        // tap reads as a live preview before the user dismisses.
        .sheet(isPresented: $showingChartCustomization) {
            ChartCustomizationSheet(
                hero: heroPaletteBinding,
                items: itemsPaletteBinding,
                bestDay: bestDayPaletteBinding,
                xp: xpPaletteBinding,
                segmentation: segmentationPaletteBinding,
                segmentationIsAuto: Binding(
                    get: { segmentationPaletteRaw.isEmpty },
                    set: { newAuto in
                        // Auto → clear the stored override so the
                        // segmentation accessor falls back to its
                        // per-scope palette.
                        // Custom → drop a sensible default (liquidGlass,
                        // matching the rest of the dashboard) so the
                        // palette grid below has something to highlight
                        // the moment the toggle flips off.
                        segmentationPaletteRaw = newAuto
                            ? ""
                            : ChartPalette.liquidGlass.rawValue
                    }
                )
            )
            // Full-height sheet — the user reported the half-detent
            // left the dashboard chart peeking through behind the
            // header, which read as visual clutter while picking
            // palettes. Locking to `.large` lifts the sheet to the
            // top of the screen so the picker owns the canvas.
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            // Opaque white sheet — the dashboard behind is also
            // blurred via `.blur(radius: …)` on the canvas while
            // the sheet is up (see `chartCustomizationBlurOverlay`
            // below).
            .presentationBackground(Color(hex: "F2F2F7"))
        }
    }

    /// Soft blur applied to the dashboard while the Chart Colors
    /// sheet is presented — prevents the chart cards behind the
    /// translucent sheet edge from competing with the picker UI.
    @ViewBuilder
    private var chartCustomizationBlurOverlay: some View {
        if showingChartCustomization {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// Triggers the hero-bytes roll-in animation. Resets to 0 then
    /// animates up to the live period total over ~0.85s. Cheap to
    /// call — the `.numericText()` content transition on the bound
    /// `Text` does the visual work. The 0.4s `numberRoll()` haptic
    /// runs alongside the high-amplitude portion of the spring so the
    /// digits feel like they're being mechanically wound up.
    private func rollHeroBytes() {
        let target = activitySeries.reduce(0, +)
        // Only fire the hum when the value is actually moving — if
        // target is 0 (fresh install, empty range) the digits don't
        // animate, and an idle 0.4s hum under "0" reads as broken.
        if target > 0 {
            HapticManager.shared.numberRoll(duration: 0.4)
        }
        heroBytesAnimated = 0
        withAnimation(.easeOut(duration: 0.85)) {
            heroBytesAnimated = target
        }
    }

    /// Single backend entry point for both modules. Pulls lifetime
    /// stats + the 365-day activity log, flips `isRefreshing` for
    /// the dim affordance. `includeStats` is false from
    /// `.onChange(stats.lifetimeBytesSaved)` since the stats object
    /// is already authoritative at that point.
    private func reloadFromBackend(includeStats: Bool = true, force: Bool = false) async {
        // Auto-syncs (tab re-entry, scene phase) hit this often. Skip
        // if we synced recently; pull-to-refresh and explicit user
        // actions pass `force: true` to bypass.
        if !force {
            let elapsed = Date().timeIntervalSince(lastBackendSyncAt)
            if elapsed < Self.backendSyncThrottle { return }
        }
        await MainActor.run { isRefreshing = true }
        if includeStats { await stats.pullFromBackend() }
        let fetched = await StreakService.shared.fetchActivities(limit: 365)
        await MainActor.run {
            self.activities = fetched
            self.isRefreshing = false
            self.lastBackendSyncAt = Date()
        }
    }

    /// Pull-to-refresh entry point — always a full sync + completion
    /// haptic. Separated so user-driven and background refreshes have
    /// distinct semantics.
    private func refreshAll() async {
        await reloadFromBackend(includeStats: true, force: true)
        await MainActor.run {
            // Success-notify on completion — the data just landed, the
            // user pulled to get it. Reads as a small "ding" matching
            // the iOS-native pull-to-refresh expectation, not a
            // generic light pop.
            HapticManager.shared.actionSuccess()
        }
    }

    /// Mirrors ChargingView.handleStartCleanup so the Progress CTA opens
    /// the same guided flow without bouncing through the Home tab. The
    /// resolved plan resolves checkpoint media against the live store so
    /// the flow has real items to act on, not just the dashboard tally.
    private func handleStartCleanup() {
        let plan = todayPlan
        guard !plan.tasks.isEmpty, plan.checkpointCount > 0 else {
            // Nothing scanned yet — fall back to switching to Home so the
            // user can trigger a scan. Light selection tick so the CTA
            // still has tactile acknowledgement even when it bounces.
            HapticManager.shared.selection()
            NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
            return
        }
        // Heavy primary-commit feel only on the success branch — the
        // user is actually entering Guided Cleanup, not being bounced.
        HapticManager.shared.primaryCommit()
        resolvedPlan = CleanupOrchestrator.shared.buildResolvedPlan(
            from: similarVM.dashboardSnapshot,
            cleanScore: stats.cleanScore,
            store: similarVM,
            excluding: UserDefaultsDecisionsStore.shared.allDecidedIds
        )
        showGuidedCleanup = true
    }

    private var canvas: some View {
        // Cool blue-lavender → warm light-gray gradient. Identical
        // stops to the Email / Settings / Compress glass backdrop so
        // every secondary tab shares one unified canvas.
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var scrollContent: some View {
        // ScrollViewReader wraps the scroll so the breakdown card's
        // donut-tap handler can scroll the matching row into view via
        // `.id(bucket.category)` — without the proxy, tapping a donut
        // arc just expands a row that might be off-screen below.
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    // BitePal-style inline reorder indicator: a tiny
                    // up/down chevron pair tucked into each card's
                    // top-LEFT corner. Tapping it opens a Menu with
                    // move-up / move-down / move-to-top / -bottom.
                    // Long-press still works as the alternative.
                    ForEach(orderedCards, id: \.self) { kind in
                        progressCard(kind)
                            .overlay(alignment: .top) {
                                // Centered horizontally at the very
                                // top of the card so the chip sits in
                                // a column that's intentionally clear
                                // of every card's title row (which is
                                // always anchored to leading/trailing).
                                // Drag-style ⇅ glyph reads as "reorder
                                // me" without competing with the
                                // title or the chart paint button.
                                cardReorderChip(for: kind)
                                    .padding(.top, 8)
                            }
                            .contextMenu {
                                reorderMenu(for: kind)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // ContentView already wraps `ProgressTabView` in a
                // 132pt `.safeAreaInset(edge: .bottom)` to clear the
                // floating nav bar — any extra bottom padding here
                // just adds dead white canvas below the last card.
                // 8pt for a hair of breathing room and nothing else.
                .padding(.bottom, 8)
            }
            // BitePal-style pull-to-refresh — pulls fresh lifetime stats +
            // the 365-day activity log so both modules update together.
            .refreshable {
                // Light tick on release so the gesture has tactile closure
                // before the async refresh completes. Matches iOS-native
                // pull-to-refresh expectation.
                HapticManager.shared.impact(.light, intensity: 0.5)
                await refreshAll()
            }
        }
    }

    // MARK: - Card Reorder

    private enum ProgressCardKind: String, CaseIterable, Hashable {
        case activity, xp, segmentation, leaderboard

        var displayName: String {
            switch self {
            case .activity:     return "Activity"
            case .xp:           return "Coins"
            case .segmentation: return "Breakdown"
            case .leaderboard:  return "Leaderboard"
            }
        }
    }

    private var orderedCards: [ProgressCardKind] {
        let stored = cardOrderRaw
            .split(separator: ",")
            .compactMap { ProgressCardKind(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        // Append any new cards not yet in the saved order (forward-compat
        // when we add a 5th card) and dedupe.
        var result: [ProgressCardKind] = []
        var seen: Set<ProgressCardKind> = []
        for k in stored where !seen.contains(k) {
            result.append(k)
            seen.insert(k)
        }
        for k in ProgressCardKind.allCases where !seen.contains(k) {
            result.append(k)
        }
        return result
    }

    @ViewBuilder
    private func progressCard(_ kind: ProgressCardKind) -> some View {
        switch kind {
        case .activity:
            combinedActivityCard
                .opacity(isRefreshing ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isRefreshing)
        case .xp:
            xpCard
                .opacity(isRefreshing ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isRefreshing)
        case .segmentation:
            segmentationCard
                .opacity(isRefreshing ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isRefreshing)
        case .leaderboard:
            LeaderboardPreviewCard()
        }
    }

    /// Eyebrow-text-width offset per card so the reorder chip lands
    /// immediately to the right of the card's title, not stacked on
    /// top of it. Approximations — title widths shift by a few pts
    /// per font size update, but stay within a forgiving margin.
    private func cardChipLeadingOffset(for kind: ProgressCardKind) -> CGFloat {
        switch kind {
        case .activity:     return 178  // "CLEARED THIS WEEK" + arrow chip
        case .xp:           return 180  // "EARNED THIS WEEK" + arrow chip
        case .segmentation: return 142  // "Breakdown" / shorter title
        case .leaderboard:  return 156  // "Leaderboard"
        }
    }

    @ViewBuilder
    private func cardReorderChip(for kind: ProgressCardKind) -> some View {
        // BitePal-style sort glyph: a tiny up/down chevron pair
        // (`chevron.up.chevron.down`) sitting flush with the card's
        // top-left corner. Tap opens a Menu with the four reorder
        // actions; the visual footprint stays under 18×18 so it
        // doesn't conflict with any card title, paint button, or
        // chart content.
        Menu {
            reorderMenu(for: kind)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "78716C"))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.black.opacity(0.04))
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func reorderMenu(for kind: ProgressCardKind) -> some View {
        let order = orderedCards
        let idx = order.firstIndex(of: kind) ?? 0
        let isFirst = idx == 0
        let isLast = idx == order.count - 1

        if !isFirst {
            Button {
                moveCard(kind, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
        }
        if !isLast {
            Button {
                moveCard(kind, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
        }
        if !isFirst {
            Button {
                moveCard(kind, to: 0)
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
        }
        if !isLast {
            Button {
                moveCard(kind, to: order.count - 1)
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
        }
    }

    private func moveCard(_ kind: ProgressCardKind, by delta: Int) {
        var order = orderedCards
        guard let idx = order.firstIndex(of: kind) else { return }
        let target = max(0, min(order.count - 1, idx + delta))
        guard target != idx else { return }
        let item = order.remove(at: idx)
        order.insert(item, at: target)
        persistCardOrder(order)
    }

    private func moveCard(_ kind: ProgressCardKind, to target: Int) {
        var order = orderedCards
        guard let idx = order.firstIndex(of: kind) else { return }
        guard target != idx else { return }
        let item = order.remove(at: idx)
        order.insert(item, at: min(target, order.count))
        persistCardOrder(order)
    }

    private func persistCardOrder(_ order: [ProgressCardKind]) {
        cardOrderRaw = order.map(\.rawValue).joined(separator: ",")
        // Haptic is fired at the button site so the click feels tied
        // to the tap, not to the async @AppStorage write.
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Progress")
                .font(.custom("Poppins-Bold", size: 32))
                .foregroundColor(.foreground)
            Spacer()
            customizeButton
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    /// Cal-AI toolbar affordance — a small circular button at the
    /// trailing edge of the header. Owns ALL chart-color customization
    /// (replaced the three per-chart corner dots that competed with
    /// the data inside each card). The paint icon is a one-glance read:
    /// "this is where you change how the charts look."
    private var customizeButton: some View {
        Button {
            HapticManager.shared.buttonTap()
            showingChartCustomization = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.foreground)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.surfaceLight)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customize chart colors")
    }

    /// the two halves read as the same story at two granularities.
    private var combinedActivityCard: some View {
        VStack(spacing: 0) {
            graphSection
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Rectangle()
                .fill(Color(hex: "1C1917").opacity(0.06))
                .frame(height: 0.6)
                .padding(.horizontal, 22)

            cleanupStatsSection
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassHeroSurface)
        .overlay(glassHeroHairline)
        // Warm-tinted shadow — reads as a premium dashboard card
        // catching light from above, not a flat panel on a desk.
        .shadow(color: Color.black.opacity(0.07),
                radius: 22, x: 0, y: 10)
    }

    // MARK: - XP Card (gamification anchor)
    //
    // Visual scaffolding for the XP-earned card. Sits between the
    // headline cleared-this-week card and the segmentation breakdown
    // below. v1 is intentionally design-only: the chart pulls from a
    // placeholder series keyed to `selectedXpRange` so the type, color,
    // animation, and tap-to-scrub behavior can be finalized while the
    // real XP accrual pipeline is being designed elsewhere.
    //
    // Range toggle is Week / Month only — a yearly XP rollup collapses
    // the weekly nuance into a flat trend that doesn't motivate, so
    // it's deliberately excluded.
    private var xpCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            xpHeader
            xpRangeToggle
            xpBarChart
                .frame(height: 168)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassHeroSurface)
        .overlay(glassHeroHairline)
        .shadow(color: Color.black.opacity(0.07),
                radius: 22, x: 0, y: 10)
        .onChange(of: selectedXpRange) { _, _ in
            // Switching window always voids the per-bar selection so
            // the headline returns to the aggregate for the new range
            // instead of holding a stale bar index from the prior one.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedXpIndex = nil
            }
        }
    }

    /// Eyebrow + big XP value + percent delta vs the prior period.
    /// Same reading rhythm as the segmentation card so the three cards
    /// scan as one family.
    private var xpHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(xpHeaderEyebrow.uppercased())
                    .font(.custom("Poppins-Bold", size: 10.5))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "A8A29E"))
                    .contentTransition(.opacity)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(xpHeaderValue)
                        .font(.custom("Poppins-Bold", size: 32))
                        .foregroundColor(.foreground)
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    // Switched from "XP" → coin glyph + "COINS" to
                    // match the app-wide coin economy
                    // (`HiveStatsManager.coinsBalance`).
                    HStack(spacing: 3) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LinearGradient.honeyGradient)
                        Text("COINS")
                            .font(.custom("Poppins-Bold", size: 12))
                            .tracking(0.8)
                            .foregroundColor(xpPalette.lineEnd)
                    }
                    .baselineOffset(2)
                }
            }
            .animation(.easeOut(duration: 0.22), value: selectedXpIndex == nil)
            Spacer()
            xpDeltaChip
        }
    }

    /// Week | Month pill row. Matches the visual hand of the chart
    /// range pills above so the two ranges read as the same control
    /// family even though they answer different questions. Active
    /// pill flips to the user's XP palette so the toggle and the
    /// bars below stay color-consistent.
    private var xpRangeToggle: some View {
        let palette = xpPalette
        return HStack(spacing: 6) {
            ForEach(XpRange.allCases, id: \.self) { range in
                let isActive = selectedXpRange == range
                Button {
                    HapticManager.shared.filterChange()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedXpRange = range
                    }
                } label: {
                    Text(range.label)
                        .font(.custom("Poppins-Bold", size: 12))
                        .tracking(0.3)
                        .foregroundColor(isActive ? .white : Color(hex: "78716C"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive
                                      ? LinearGradient(
                                          colors: [palette.lineStart,
                                                   palette.lineEnd],
                                          startPoint: .top,
                                          endPoint: .bottom
                                        )
                                      : LinearGradient(
                                          colors: [Color(hex: "F4F1EA"),
                                                   Color(hex: "F4F1EA")],
                                          startPoint: .top,
                                          endPoint: .bottom
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Cal-AI-style bar chart. Slim rounded bars on a faint track,
    /// gradient fill keyed to the user-selected XP palette, with the
    /// active bar lifted via a slightly stronger fill and tinted label.
    /// Tap a bar to scrub the headline to that bucket's value. Bars
    /// are capped at a max width so a week (7 bars) doesn't render
    /// the same chunky-pill silhouette as a month (4 bars).
    private var xpBarChart: some View {
        let values = xpSeriesCurrent
        let labels = xpAxisLabels
        let maxV = max(values.max() ?? 1, 1)
        return GeometryReader { geo in
            let count = max(values.count, 1)
            let spacing: CGFloat = 10
            // Cap each bar at 24pt so the column reads as a slim
            // refined bar even when the bucket count is small — the
            // bars stop ballooning into bulky pills when the month
            // view (4 buckets) gets the same horizontal lane the
            // week view (7 buckets) uses.
            let evenW = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let barW = max(min(evenW, 24), 4)
            let barAreaH = geo.size.height - 22
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                    xpBarColumn(
                        index: idx,
                        value: value,
                        maxValue: maxV,
                        label: labels.indices.contains(idx) ? labels[idx] : "",
                        width: barW,
                        areaHeight: barAreaH
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: geo.size.height, alignment: .bottom)
        }
        .contentShape(Rectangle())
    }

    /// Single bar column — Cal-AI-style refined bar. Three stacked
    /// layers: (1) almost-invisible track so empty buckets read as
    /// "we measured here" not "broken"; (2) the filled bar built from
    /// a soft palette gradient that fades subtly at the top so the
    /// bar dissolves into the card surface instead of stopping with
    /// a hard color edge; (3) a single-pixel specular highlight at
    /// the very top of the filled bar to suggest glass.
    private func xpBarColumn(index: Int,
                             value: Double,
                             maxValue: Double,
                             label: String,
                             width: CGFloat,
                             areaHeight: CGFloat) -> some View {
        let frac = CGFloat(max(0, min(value / maxValue, 1.0)))
        let isActive = selectedXpIndex == index
        let filledH = max(areaHeight * frac, value > 0 ? 6 : 2)
        let palette = xpPalette
        // Active = full palette strength; inactive = same hue softened
        // and de-saturated so the chart reads calm instead of buzzy.
        // The colors-array used for the fill takes a top alpha tier
        // (lighter at the cap) and a bottom tier (richer at the base)
        // so each bar reads as a single liquid drop rather than a
        // solid orange block.
        let topColor: Color    = isActive ? palette.lineStart.opacity(0.95)
                                          : palette.lineStart.opacity(0.55)
        let bottomColor: Color = isActive ? palette.lineEnd.opacity(0.95)
                                          : palette.lineEnd.opacity(0.65)
        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // Track — barely-there capsule so empty buckets still
                // read as measured ground (not blanks). 4% black on a
                // light card, no tint, so it stays neutral.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .frame(width: width, height: areaHeight)

                // Filled bar — soft top-to-bottom gradient, no shadow,
                // no glow. Lower corner radius (5pt) so the cap reads
                // as a clean rounded tip instead of a capsule pill.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [topColor, bottomColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: filledH)
                    .overlay(alignment: .top) {
                        // Specular highlight — narrow white sheen at
                        // the top of the bar. Capped at the filled
                        // height so it never floats above an empty bar.
                        if filledH > 8 {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.35),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: width, height: min(filledH * 0.42, 28))
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.82),
                               value: filledH)
                    .animation(.easeOut(duration: 0.2), value: isActive)
            }
            .frame(height: areaHeight)
            Text(label)
                .font(.custom("Poppins-Medium", size: 10))
                .foregroundColor(isActive
                                 ? palette.lineEnd
                                 : Color(hex: "A8A29E"))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.filterChange()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedXpIndex = (selectedXpIndex == index) ? nil : index
            }
        }
    }

    /// Delta chip for the XP card — same shape as the segmentation
    /// card's delta chip so the three cards' headlines all rhyme.
    /// Placeholder: compares the current placeholder series total
    /// against the prior placeholder series.
    private var xpDeltaChip: some View {
        let current = xpSeriesCurrent.reduce(0, +)
        let prior   = xpSeriesPrevious.reduce(0, +)
        let pct: Double = prior > 0 ? ((current - prior) / prior) * 100 : 0
        let up = pct >= 0
        let flat = abs(pct) < 1
        let tint: Color = flat
            ? Color(hex: "78716C")
            : (up ? Color(hex: "0F766E") : Color(hex: "C2410C"))
        let icon = flat ? "minus" : (up ? "arrow.up.right" : "arrow.down.right")
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(tint)
            Text("\(flat ? "0" : String(format: "%.0f", abs(pct)))%")
                .font(.custom("Poppins-Bold", size: 13))
                .foregroundColor(tint)
                .monospacedDigit()
            Text("vs \(selectedXpRange.priorLabel)")
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(Color(hex: "8C92A4"))
        }
    }

    // MARK: - XP card data (placeholder while backend lands)

    /// Eyebrow string above the value. Switches to the scrubbed bar's
    /// label when the user has a bar selected so the headline always
    /// names what the value below it refers to.
    private var xpHeaderEyebrow: String {
        if let idx = selectedXpIndex,
           xpAxisLabels.indices.contains(idx) {
            let label = xpAxisLabels[idx]
            return selectedXpRange == .week
                ? "earned on \(label)"
                : "earned \(label)"
        }
        return "earned \(selectedXpRange.scopeLabel)"
    }

    /// Headline value: the scrubbed bar's XP if a bar is selected,
    /// otherwise the period aggregate.
    private var xpHeaderValue: String {
        let value: Double
        if let idx = selectedXpIndex,
           xpSeriesCurrent.indices.contains(idx) {
            value = xpSeriesCurrent[idx]
        } else {
            value = xpSeriesCurrent.reduce(0, +)
        }
        return Self.formatXp(value)
    }

    /// XP earned in the active range, bucketed from the same backend
    /// `activities` log the segmentation + hero charts read. Each
    /// cleanup contributes `itemCount * 5 + (bytesSaved / 10_000_000)`
    /// XP — five points per item plus one per 10 MB freed, matching
    /// the coin economy in `HiveStatsManager.coinsBalance`.
    /// Falls back to a small placeholder series only when the user
    /// has zero activities at all, so a fresh install doesn't render
    /// an empty chart with no visual anchor.
    private var xpSeriesCurrent: [Double] {
        xpSeries(offsetPeriods: 0)
    }

    /// Prior comparable period — drives the "vs last week / vs last
    /// month" delta chip.
    private var xpSeriesPrevious: [Double] {
        xpSeries(offsetPeriods: 1)
    }

    private func xpSeries(offsetPeriods: Int) -> [Double] {
        let unit: Calendar.Component = (selectedXpRange == .week) ? .day : .weekOfYear
        let count = (selectedXpRange == .week) ? 7 : 4
        let cal = Calendar.current

        var sums: [Date: Double] = [:]
        for entry in activities {
            guard let date = entry.date else { continue }
            // Coin economy: 1 coin per 10 MB freed — same formula as
            // `HiveStatsManager.coinsBalance`. Drops the XP-era item
            // bonus so the bar values line up with the coin balance
            // shown in the dashboard pill.
            let coins = Double(entry.bytesSaved) / 10_000_000
            guard coins > 0 else { continue }
            let key = cal.dateInterval(of: unit, for: date)?.start ?? date
            sums[key, default: 0] += coins
        }

        // Walk back from today by `count * offsetPeriods` periods so
        // offsetPeriods=0 returns the current window, =1 returns the
        // immediately-prior window for the delta chip.
        let now = cal.date(byAdding: unit, value: -(count * offsetPeriods), to: Date()) ?? Date()
        var series: [Double] = []
        for o in (0..<count).reversed() {
            let bucket = cal.date(byAdding: unit, value: -o, to: now) ?? now
            let key = cal.dateInterval(of: unit, for: bucket)?.start ?? bucket
            series.append(sums[key] ?? 0)
        }
        // Fresh-install fallback: if we computed an all-zero series and
        // have no activities at all, surface the original placeholder
        // shape so the chart has visual hierarchy on first launch.
        if series.allSatisfy({ $0 == 0 }) && activities.isEmpty {
            return selectedXpRange == .week
                ? [240, 180, 420, 90, 350, 280, 510]
                : [1240, 980, 1530, 1820]
        }
        return series
    }

    /// X-axis labels per range. Week ⇒ weekday letters (M T W T F S S).
    /// Month ⇒ Wk 1 … Wk 4 so the bars read as relative weeks within
    /// the current month without depending on the exact start-of-month
    /// calendar math (placeholder).
    private var xpAxisLabels: [String] {
        switch selectedXpRange {
        case .week:  return ["M", "T", "W", "T", "F", "S", "S"]
        case .month: return ["Wk 1", "Wk 2", "Wk 3", "Wk 4"]
        }
    }

    /// Compact XP formatter. Drops to "1.2K" past 1,000 so the
    /// headline stays readable on small screens.
    private static func formatXp(_ value: Double) -> String {
        let v = Int(value.rounded())
        if v >= 10_000 {
            return "\(v / 1000)K"
        }
        if v >= 1_000 {
            let oneDecimal = Double(v) / 1000
            return String(format: "%.1fK", oneDecimal)
        }
        return v.formatted()
    }


    // MARK: - Segmentation Card (Cal AI–style scope picker)
    //
    // The second graph on the Progress tab. Designed so the user can
    // pivot a single chart across every Quick Access surface (Photos,
    // Videos, Emails, Compression) without flipping cards. Each scope
    // shifts the chart's data, palette, headline metric, and (where it
    // exists) an inline leaf picker — exactly the "scope a symbol,
    // watch everything narrow" model the hero chart uses for leaf
    // categories, lifted up one level to Quick Access.
    //
    // Everything is driven off the same `activities` log the hero chart
    // reads, so the two charts can never disagree. Emails switch the
    // metric from bytes → items cleared because email cleanups don't
    // surface a meaningful byte saving.
    private var segmentationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            segmentationHeader
            segmentationTopLevelChips
            if !segmentationAvailableLeaves.isEmpty {
                segmentationLeafChips
            }
            segmentationChartStage
            // Inline range row — the dedicated `breakdownRangePillRow`
            // helper was deleted with the rest of the dormant breakdown
            // surface, so the segmentation card calls `rangePillRow`
            // directly. `clearsScrub: false` is intentional: flipping
            // the segmentation range should drop only `selectedBreakdownPointIndex`,
            // handled by this card's own `onChange` below.
            rangePillRow(
                namespace: breakdownRangePillNS,
                selection: $selectedBreakdownRange,
                clearsScrub: false
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassHeroSurface)
        .overlay(glassHeroHairline)
        .shadow(color: Color.black.opacity(0.07),
                radius: 22, x: 0, y: 10)
        // Switching the top-level always voids the leaf scope so a
        // Photos→Videos flip can't carry a Photos-only leaf into the
        // Videos chart (it would silently render zeros).
        .onChange(of: selectedBreakdownTopLevel) { _, _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedBreakdownLeaf = nil
                selectedBreakdownPointIndex = nil
            }
        }
        .onChange(of: selectedBreakdownLeaf) { _, _ in
            selectedBreakdownPointIndex = nil
        }
        .onChange(of: selectedBreakdownRange) { _, _ in
            selectedBreakdownPointIndex = nil
        }
    }

    /// Glass-polished chart stage that gives the segmentation card a
    /// visually distinct silhouette from the hero card above. The
    /// chart itself is the same `ActivityLineChart` primitive (so all
    /// the scrub + draw-in machinery is shared), but it sits inside a
    /// translucent inset pane with a hairline border + soft top
    /// specular sheen — the Cal-AI dashboard "data lives in its own
    /// glass tray" treatment.
    ///
    /// When there's nothing to plot for the active scope, the pane
    /// renders an empty-state pill in place of the chart so the card
    /// never reads as "broken / flat line" — same surface, no chart.
    @ViewBuilder
    private var segmentationChartStage: some View {
        let hasData = segmentationTotalCurrent > 0
        let stageShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            // Translucent inset pane — pure-white wash at the top
            // fading into a near-transparent base. Matches the card's
            // `glassHeroSurface` so the chart tray reads as a slice of
            // the same glass material, not a foreign panel.
            stageShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            stageShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.7),
                            Color.black.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )

            if hasData {
                ActivityLineChart(
                    values: segmentationSeriesCurrent,
                    previousPeriod: segmentationSeriesPrevious,
                    maxValue: segmentationMax,
                    bestIndex: segmentationBestIndex,
                    selectedIndex: $selectedBreakdownPointIndex,
                    xAxisLabels: segmentationXAxisLabels,
                    tooltip: segmentationTooltipLines,
                    palette: segmentationPalette
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                // Force a clean recreate every time the scope changes
                // so the line redraws from zero — same primitive the
                // hero chart uses to re-fire its draw-in animation on
                // chip switches.
                .id("seg-\(selectedBreakdownRange.label)-\(selectedBreakdownTopLevel?.rawValue ?? "all")-\(selectedBreakdownLeaf?.rawValue ?? "all")")
            } else {
                segmentationEmptyState
            }
        }
        .frame(height: 200)
    }

    /// Calm in-pane message for scopes with zero activity. Lets the
    /// card stay structurally identical (same stage height, same
    /// chrome) regardless of whether there's something to plot.
    private var segmentationEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(segmentationPalette.lineEnd.opacity(0.55))
            Text("No activity yet")
                .font(.custom("Poppins-Bold", size: 13))
                .foregroundColor(Color(hex: "57534E"))
            Text(emptyStateHint)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(Color(hex: "8C92A4"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    /// Scope-aware hint copy for the empty state.
    private var emptyStateHint: String {
        if let leaf = selectedBreakdownLeaf {
            return "Run a \(leaf.displayName) cleanup to see it land here."
        }
        if let top = selectedBreakdownTopLevel {
            return "Clean some \(top.displayName.lowercased()) and the trend will show up."
        }
        return "Pick a cleanup flow from the dashboard to start charting activity."
    }

    /// Eyebrow + headline + delta chip. Mirrors the hero chart header
    /// so the two cards read as one family — same type hierarchy, same
    /// scrub-aware swap between aggregate total and per-bucket value.
    private var segmentationHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(segmentationEyebrowText.uppercased())
                    .font(.custom("Poppins-Bold", size: 10.5))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "A8A29E"))
                    .contentTransition(.opacity)
                Text(segmentationHeadlineText)
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(.foreground)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            // Animate only on selection enter/exit, NOT on every drag-
            // tick index change — same fix the hero header got.
            .animation(.easeOut(duration: 0.22),
                       value: selectedBreakdownPointIndex == nil)
            Spacer()
            segmentationDeltaChip
        }
    }

    /// Top-level chip row — All + the canonical Quick Access surfaces.
    /// Auto-sized chips inside a horizontal scroll: equal-width packing
    /// truncated the longest label ("Compress") on iPhone-SE-width
    /// devices. Natural-width chips never truncate, and the scroll
    /// surface is a Cal-AI-standard interaction so it doesn't read as
    /// a bug when the row overflows.
    private var segmentationTopLevelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                segmentationChip(
                    label: "All",
                    accent: Color(hex: "78716C"),
                    isActive: selectedBreakdownTopLevel == nil,
                    fillsWidth: false
                ) {
                    if selectedBreakdownTopLevel != nil {
                        HapticManager.shared.filterChange()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedBreakdownTopLevel = nil
                        }
                    }
                }
                ForEach(Self.segmentationTopLevels, id: \.self) { top in
                    segmentationChip(
                        label: top.shortLabel,
                        accent: top.accentColor,
                        isActive: selectedBreakdownTopLevel == top,
                        fillsWidth: false
                    ) {
                        let next: TopLevelCategory? =
                            selectedBreakdownTopLevel == top ? nil : top
                        HapticManager.shared.filterChange()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedBreakdownTopLevel = next
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// Leaf chip row — appears only when a top-level with leaves is
    /// selected AND that leaf has activity in the current range. Empty
    /// leaves are hidden so the chips never offer dead options. Leaf
    /// labels can be 2-4 words ("Similar Screenshots") so this row
    /// uses horizontal scroll instead of equal-width packing, with
    /// the rest of the chip styling matching the top-level row.
    private var segmentationLeafChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let tint = segmentationActiveTint
                segmentationChip(
                    label: "All",
                    accent: tint,
                    isActive: selectedBreakdownLeaf == nil,
                    fillsWidth: false
                ) {
                    if selectedBreakdownLeaf != nil {
                        HapticManager.shared.filterChange()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedBreakdownLeaf = nil
                        }
                    }
                }
                ForEach(segmentationAvailableLeaves, id: \.self) { leaf in
                    segmentationChip(
                        label: leaf.displayName,
                        accent: tint,
                        isActive: selectedBreakdownLeaf == leaf,
                        fillsWidth: false
                    ) {
                        let next: SavedFindSourceCategory? =
                            selectedBreakdownLeaf == leaf ? nil : leaf
                        HapticManager.shared.filterChange()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedBreakdownLeaf = next
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// One chip — same visual treatment used by the hero chart's chip
    /// row so the two surfaces feel like one set. Active chip swaps the
    /// fill from neutral to the scope's accent.
    private func segmentationChip(
        label: String,
        accent: Color,
        isActive: Bool,
        fillsWidth: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Poppins-Bold", size: 11))
                .foregroundColor(isActive ? .white : Color(hex: "57534E"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 6 : 11)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? accent : Color(hex: "F4EFE3"))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isActive ? Color.clear : accent.opacity(0.14),
                            lineWidth: 0.8
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Delta chip — % change vs the same window one period back. Same
    /// shape as the hero chart's deltaChip; reads the segmentation
    /// totals instead of the hero series so each card answers its own
    /// "doing better than last time?" question independently.
    private var segmentationDeltaChip: some View {
        let current = segmentationTotalCurrent
        let prior = segmentationTotalPrevious
        let pct: Double = prior > 0 ? ((current - prior) / prior) * 100 : 0
        let up = pct >= 0
        let flat = abs(pct) < 1
        let tint: Color = flat
            ? Color(hex: "78716C")
            : (up ? Color(hex: "0F766E") : Color(hex: "C2410C"))
        let icon = flat ? "minus" : (up ? "arrow.up.right" : "arrow.down.right")
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(tint)
            Text("\(flat ? "0" : String(format: "%.0f", abs(pct)))%")
                .font(.custom("Poppins-Bold", size: 13))
                .foregroundColor(tint)
                .monospacedDigit()
            Text("vs \(previousPeriodLabel)")
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(Color(hex: "8C92A4"))
        }
    }

    // MARK: - Segmentation data helpers

    /// Canonical Quick Access order. Contacts is intentionally excluded
    /// here even though `TopLevelCategory` carries the case — the user
    /// wants the four QA tiles only.
    private static let segmentationTopLevels: [TopLevelCategory] = [
        .photos, .videos, .emails, .compression
    ]

    /// Tint that drives the leaf chips + the chart palette. Falls back
    /// to a neutral honey for the All scope so the chart still reads.
    private var segmentationActiveTint: Color {
        selectedBreakdownTopLevel?.accentColor ?? Color(hex: "FFB300")
    }

    /// Map the active top-level onto one of the existing ChartPalettes
    /// so the chart's gradient, area fill, shadow, and BEST marker
    /// re-tint as the user pivots scopes. Reuses the existing palette
    /// system instead of inventing one-off colors per category.
    ///
    /// User override takes precedence: when the user picks a palette
    /// from the chart customization sheet, that palette wins across
    /// every scope (and the chip-flip color cue is intentionally
    /// disabled so their explicit choice doesn't get clobbered).
    private var segmentationPalette: ChartPalette {
        if let user = ChartPalette(rawValue: segmentationPaletteRaw) {
            return user
        }
        switch selectedBreakdownTopLevel {
        case .photos:      return .honey
        case .videos:      return .aurora
        case .emails:      return .cobalt
        case .compression: return .forest
        case .contacts:    return .lilac
        case .none:        return .honey
        }
    }

    /// Whether the active scope tracks item counts (Emails) vs bytes
    /// (every other top-level). Drives the chart's y-axis meaning and
    /// the headline string formatting.
    private var segmentationUsesItemCount: Bool {
        selectedBreakdownTopLevel == .emails
    }

    /// Activity entries that pass the active scope (top-level + leaf).
    /// Top-level nil = every entry that maps to one of the QA top-levels.
    /// Leaf nil = every leaf inside the chosen top-level.
    private var segmentationFilteredActivities: [ActivityEntry] {
        activities.filter { entry in
            guard let top = entry.topLevelCategory else { return false }
            if let scope = selectedBreakdownTopLevel, scope != top {
                return false
            }
            if let leaf = selectedBreakdownLeaf {
                guard entry.category == leaf else { return false }
            }
            return true
        }
    }

    /// Leaves present in the current top-level's filtered activity for
    /// the active range. Hidden when the top-level has no leaf concept
    /// (Emails) or when no leaves have any data in the range — keeps
    /// the chip row from advertising dead options.
    private var segmentationAvailableLeaves: [SavedFindSourceCategory] {
        guard let top = selectedBreakdownTopLevel,
              !top.leafCategories.isEmpty else { return [] }

        let unit = selectedBreakdownRange.unit
        let count = selectedBreakdownRange.pointCount
        guard count > 0 else { return [] }

        let now = Date()
        let earliestKey = bucketKey(
            for: bucketDate(byAdding: -(count - 1), unit: unit, from: now),
            unit: unit
        )
        let latestKey = bucketKey(for: now, unit: unit)

        var present: Set<SavedFindSourceCategory> = []
        for entry in activities {
            guard entry.topLevelCategory == top,
                  let leaf = entry.category,
                  top.leafCategories.contains(leaf),
                  let date = entry.date else { continue }
            let key = bucketKey(for: date, unit: unit)
            guard key >= earliestKey && key <= latestKey else { continue }
            // Bytes for everything except Emails (which doesn't reach
            // this branch — emails have no leaves); item counts also
            // count as "present" so a Compression leaf with only items
            // logged still surfaces.
            if entry.bytesSaved > 0 || entry.itemCount > 0 {
                present.insert(leaf)
            }
        }
        return top.leafCategories.filter { present.contains($0) }
    }

    /// Bytes-or-items per bucket for the active scope + range.
    /// `offsetPeriods = 0` → current window, `1` → comparison window
    /// (yesterday / last week / prior month / last year).
    private func segmentationSeries(offsetPeriods: Int) -> [Double] {
        let unit = selectedBreakdownRange.unit
        let count = selectedBreakdownRange.pointCount
        guard count > 0 else { return [] }
        let useItems = segmentationUsesItemCount
        let filtered = segmentationFilteredActivities

        var sums: [Date: Double] = [:]
        for entry in filtered {
            guard let date = entry.date else { continue }
            let value = useItems
                ? Double(entry.itemCount)
                : Double(entry.bytesSaved)
            guard value > 0 else { continue }
            let key = bucketKey(for: date, unit: unit)
            sums[key, default: 0] += value
        }

        let anchor = bucketDate(byAdding: -(count * offsetPeriods),
                                unit: unit, from: Date())
        var series: [Double] = []
        for offset in (0..<count).reversed() {
            let bucket = bucketDate(byAdding: -offset, unit: unit, from: anchor)
            let key = bucketKey(for: bucket, unit: unit)
            series.append(sums[key] ?? 0)
        }
        return series
    }

    private var segmentationSeriesCurrent: [Double] {
        segmentationSeries(offsetPeriods: 0)
    }
    private var segmentationSeriesPrevious: [Double] {
        segmentationSeries(offsetPeriods: 1)
    }
    private var segmentationMax: Double {
        max(segmentationSeriesCurrent.max() ?? 1, 1)
    }
    private var segmentationBestIndex: Int? {
        let s = segmentationSeriesCurrent
        guard let m = s.max(), m > 0,
              let i = s.firstIndex(of: m) else { return nil }
        return i
    }
    private var segmentationTotalCurrent: Double {
        segmentationSeriesCurrent.reduce(0, +)
    }
    private var segmentationTotalPrevious: Double {
        segmentationSeriesPrevious.reduce(0, +)
    }

    /// X-axis labels for the segmentation chart — same recipe as the
    /// hero chart, but reads the segmentation's own range pill so the
    /// two cards' time axes stay independent.
    private var segmentationXAxisLabels: [String] {
        switch selectedBreakdownRange {
        case .oneDay:    return ["12a", "6a", "12p", "6p", "Now"]
        case .sevenDay:  return weekdayLetters
        case .thirtyDay: return ["30D", "20D", "10D", "Today"]
        case .oneYear:   return ["12mo", "8mo", "4mo", "Now"]
        }
    }

    /// Per-bucket tooltip — formats the value with the right noun
    /// (bytes vs items) and reuses `tooltipWhen` for the relative
    /// time copy.
    private var segmentationTooltipLines: (value: String, when: String) {
        let s = segmentationSeriesCurrent
        let cnt = s.count
        guard cnt > 0 else { return ("", "") }
        let raw = selectedBreakdownPointIndex ?? (cnt - 1)
        let idx = max(0, min(cnt - 1, raw))
        let value = segmentationFormatValue(s[idx], includingNoun: true)
        let when = Self.tooltipWhen(idx: idx,
                                    total: cnt,
                                    unit: selectedBreakdownRange.unit)
        return (value, when)
    }

    /// Headline value — swaps between the active period total and the
    /// scrubbed bucket value as the user drags the chart. The two
    /// formats share the same noun ("cleared" / "emails cleared") so
    /// the headline stays parseable while scrubbing.
    private var segmentationHeadlineText: String {
        if let idx = selectedBreakdownPointIndex,
           segmentationSeriesCurrent.indices.contains(idx) {
            return segmentationFormatValue(
                segmentationSeriesCurrent[idx],
                includingNoun: false
            )
        }
        return segmentationFormatValue(
            segmentationTotalCurrent,
            includingNoun: false
        )
    }

    /// Eyebrow — Cal-AI-style minimal label. Names the scope on its
    /// own and drops the time window (the range pills below already
    /// answer that), so the eyebrow stays a single short phrase even
    /// at narrow widths. Switches to the scrubbed bucket's relative
    /// time copy ("Today / 3d ago / Wk 2") when the user scrubs.
    private var segmentationEyebrowText: String {
        if selectedBreakdownPointIndex != nil {
            return segmentationTooltipLines.when
        }
        if let leaf = selectedBreakdownLeaf {
            return leaf.displayName
        }
        if let top = selectedBreakdownTopLevel {
            return top.displayName
        }
        return "All sources"
    }

    /// Human-readable scope label that respects whether a leaf is
    /// pinned ("Duplicates"), a top-level is pinned ("Photos"), or
    /// neither ("Everything"). Used by the eyebrow + subtitle.
    private var segmentationScopeLabel: String {
        if let leaf = selectedBreakdownLeaf { return leaf.displayName }
        if let top = selectedBreakdownTopLevel { return top.displayName }
        return "Everything"
    }

    /// Same time-scope tail the hero chart uses, scoped to the
    /// segmentation's own range so flipping one card doesn't drag the
    /// other along.
    private var segmentationRangeScopeWord: String {
        switch selectedBreakdownRange {
        case .oneDay:    return "today"
        case .sevenDay:  return "this week"
        case .thirtyDay: return "this month"
        case .oneYear:   return "this year"
        }
    }

    /// Format a value with the right unit. Bytes → ByteCountFormatter;
    /// Emails → "N emails" / "N email". `includingNoun=false` skips the
    /// noun so the headline can read "24.5 GB" / "412" without trailing
    /// chrome — the eyebrow above carries the "cleared" verb.
    private func segmentationFormatValue(_ value: Double,
                                         includingNoun: Bool) -> String {
        if segmentationUsesItemCount {
            let count = Int(value.rounded())
            if includingNoun {
                return "\(count.formatted()) email\(count == 1 ? "" : "s")"
            }
            return count.formatted()
        }
        // ByteCountFormatter renders 0 as "Zero KB" which reads as a
        // copy bug on the dashboard headline. Force "0 KB" so the
        // empty state stays clean + consistent with the numeric tick
        // animation on non-zero values.
        if value <= 0 {
            return includingNoun ? "0 KB cleared" : "0 KB"
        }
        let bytes = Self.formatBytes(value)
        if includingNoun {
            return "\(bytes) cleared"
        }
        return bytes
    }

    /// Graph section content (header + chart + range pills). Strips
    /// the surrounding card chrome that the standalone card had —
    /// the combined card owns the glass surface now.
    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            graphHeader
            categoryChipRow
            ActivityLineChart(
                values: activitySeries,
                previousPeriod: previousPeriodSeries,
                maxValue: activityMax,
                bestIndex: bestActivityIndex,
                selectedIndex: $selectedPointIndex,
                xAxisLabels: xAxisLabels,
                tooltip: selectedTooltipLines,
                palette: heroPalette
            )
            // Force a clean recreate on every range switch OR category
            // flip — guarantees `.onAppear` re-fires + the draw-in
            // animation runs, even when consecutive ranges/filters
            // happen to share a max/count value. Without `category` in
            // the id, a chip-row filter switch could leave the chart
            // showing the prior pose silently.
            .id("\(selectedRange.label)-\(selectedProgressCategory?.rawValue ?? "all")")
            .frame(height: 200)
            rangeSelector
        }
    }

    /// Horizontal chip strip — one chip per category that has tagged
    /// activity, ordered by the canonical SavedFinds category sequence
    /// so Duplicates leads and videos trail. Renders nothing when
    /// there's only 0 or 1 category present (single-source account
    /// doesn't need a filter). Mirrors the SavedFindsView chip row's
    /// look + haptic so the two surfaces feel like one feature.
    @ViewBuilder
    private var categoryChipRow: some View {
        let visible = visibleProgressCategories
        if visible.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    progressChip(label: "All", isActive: selectedProgressCategory == nil) {
                        if selectedProgressCategory != nil {
                            HapticManager.shared.filterChange()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selectedProgressCategory = nil
                                selectedPointIndex = nil
                            }
                        }
                    }
                    ForEach(visible, id: \.self) { category in
                        progressChip(
                            label: category.displayName,
                            isActive: selectedProgressCategory == category
                        ) {
                            HapticManager.shared.filterChange()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                // Re-tap clears, same one-tap escape
                                // as the SavedFinds chip row.
                                selectedProgressCategory =
                                    (selectedProgressCategory == category) ? nil : category
                                selectedPointIndex = nil
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    /// Categories with at least one tagged activity entry in the live
    /// log. Ordered using the canonical sequence shared with
    /// SavedFindsView so the chip row reads identically across the two
    /// surfaces.
    private var visibleProgressCategories: [SavedFindSourceCategory] {
        let present = Set(activities.compactMap(\.category))
        return Self.progressCategoryOrder.filter { present.contains($0) }
    }

    private static let progressCategoryOrder: [SavedFindSourceCategory] = [
        .duplicates,
        .similarPhotos,
        .similarScreenshots,
        .screenshots,
        .blurredPhotos,
        .otherPhotos,
        .similarVideos,
        .screenRecordings,
        .shortRecordings,
        .longVideos
    ]

    /// Honey-amber active treatment matches the SavedFinds chip + the
    /// Recent Wins streak pill so the user's "active scope" cue is
    /// consistent app-wide.
    private func progressChip(
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Poppins-Bold", size: 11))
                .tracking(0.4)
                .foregroundColor(isActive ? .white : Color(hex: "1C1917"))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        isActive
                            ? Color(hex: "FF7A1A")
                            : Color(hex: "F5F4F0")
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isActive
                            ? Color(hex: "FF7A1A").opacity(0.6)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.6
                    )
                )
        }
        .buttonStyle(.plain)
    }

    /// The lower module under the chart. Used to be "Recent Wins" with
    /// an "XP Gained" column — the XP system was fake (10 per item + 1
    /// per MB) and read as gamification cruft. Now: a streak chip + the
    /// range scope chip up top, then two real, useful stats — items
    /// cleaned and the user's best single day in the active window —
    /// each with a Stripe-style sparkline showing the trend behind the
    /// headline number.
    private var cleanupStatsSection: some View {
        let items = itemsCleanedCurrent
        let itemsDelta = items - itemsCleanedPrevious
        let streak = max(stats.currentStreak, 0)
        let itemsDeltaSuffix = "vs \(previousPeriodLabel)"
        return VStack(alignment: .leading, spacing: 16) {
            // Header row — streak chip on the left so the dopamine cue
            // leads, range chip on the right so the user can flip
            // scope without leaving the section. Eyebrow text removed
            // entirely: the chips already say what scope you're in.
            HStack(alignment: .center, spacing: 10) {
                if streak > 0 {
                    streakHeaderChip(streak: streak)
                }
                Spacer()
                rangeMenuChip
            }

            // 2-column stat row separated by a thin vertical hairline.
            // Both columns share the same chrome — label, value, a
            // contextual sub-line, and a sparkline trace below.
            HStack(alignment: .top, spacing: 0) {
                statColumn(
                    label: "Items Cleaned",
                    value: items.formatted(),
                    delta: itemsDelta,
                    deltaSuffix: itemsDeltaSuffix,
                    sparkline: itemsSparklineSeries,
                    palette: itemsPalette
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color(hex: "1C1917").opacity(0.07))
                    .frame(width: 0.6, height: 78)

                bestDayColumn
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Shared streak-reveal chip — extracted so the new header row stays
    /// readable and the chip can be reused elsewhere if needed.
    private func streakHeaderChip(streak: Int) -> some View {
        Button {
            HapticManager.shared.streakReveal()
            showStreakDetail = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(Color(hex: "FF7A1A"))
                Text("\(streak)-day streak")
                    .font(.custom("Poppins-Bold", size: 10.5))
                    .tracking(0.3)
                    .foregroundColor(.foreground)
                ChevronGlyph(size: .small, tint: Color(hex: "C8CCD4"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Range menu chip — same control as before but lives on the right
    /// side of the new header row, paired with the streak chip.
    private var rangeMenuChip: some View {
        Menu {
            ForEach(ProgressRange.allCases, id: \.self) { range in
                Button {
                    // Same primitive the range-pill row uses below —
                    // both controls drive `selectedRange`, both should
                    // feel identical so the user can't tell them apart
                    // by touch alone.
                    HapticManager.shared.chartRangeFlip()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        selectedRange = range
                        selectedPointIndex = nil
                    }
                } label: {
                    if selectedRange == range {
                        Label(menuLabel(for: range), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(for: range))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(rangeWinsLabel)
                    .font(.custom("Poppins-Bold", size: 10.5))
                    .tracking(0.8)
                    .foregroundColor(Color(hex: "8C92A4"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(Color(hex: "C8CCD4"))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Change range, currently \(rangeWinsLabel)")
    }

    /// Best Day column — replaces the old fake "XP Gained" with a
    /// concrete, motivating fact: the user's biggest single cleanup
    /// day in the active window. No delta line (it's a single peak,
    /// not a comparison), just a contextual "on Tuesday" / "in March"
    /// label below the bytes.
    private var bestDayColumn: some View {
        let series = activitySeries
        let bestIdx = bestActivityIndex
        let bestValue: Double = bestIdx.flatMap { series.indices.contains($0) ? series[$0] : nil } ?? 0
        let whenText: String = {
            guard let idx = bestIdx else { return "no data yet" }
            return Self.tooltipWhen(idx: idx, total: series.count, unit: selectedRange.unit).lowercased()
        }()
        let hasData = bestValue > 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("BEST DAY")
                .font(.custom("Poppins-Bold", size: 9.5))
                .tracking(1.2)
                .foregroundColor(Color(hex: "A8A29E"))
            Text(hasData ? Self.formatBytes(bestValue) : "—")
                .font(.custom("Poppins-Bold", size: 30))
                .foregroundColor(.foreground)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Image(systemName: hasData ? "calendar" : "minus")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(Color(hex: "8C92A4"))
                Text(hasData ? whenText : "no cleanups in window")
                    .font(.custom("Poppins-Medium", size: 10.5))
                    .foregroundColor(.foregroundSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            MiniSparkline(values: series, tint: bestDayPalette.lineEnd)
                .frame(height: 22)
                .padding(.top, 2)
        }
    }

    /// Type-only stat column. Tiny eyebrow → giant mono value →
    /// signed delta line → Stripe-style sparkline. The sparkline tint
    /// follows the delta color, so a column trending up reads green
    /// top-to-bottom and a trending-down column reads warm.
    private func statColumn(label: String, value: String,
                            delta: Int, deltaSuffix: String,
                            sparkline: [Double],
                            palette: ChartPalette) -> some View {
        let isUp = delta >= 0
        let isFlat = delta == 0
        let deltaColor = isFlat
            ? Color(hex: "8C92A4")
            : (isUp ? Color(hex: "0F766E") : Color(hex: "C2410C"))
        return VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.custom("Poppins-Bold", size: 9.5))
                .tracking(0.9)
                .foregroundColor(Color(hex: "8C92A4"))
            Text(value)
                .font(.custom("Poppins-Bold", size: 30))
                .foregroundColor(.foreground)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Image(systemName: isFlat
                      ? "minus"
                      : (isUp ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(deltaColor)
                Text(
                    isFlat
                        ? "no change"
                        : "\(isUp ? "+" : "")\(abs(delta).formatted()) \(deltaSuffix)"
                )
                    .font(.custom("Poppins-Medium", size: 10.5))
                    .foregroundColor(deltaColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // Sparkline tinted by the user's chosen palette. Delta
            // direction is still carried by the arrow + text above —
            // so the user keeps the "up/down" semantic while owning
            // the line's color.
            MiniSparkline(values: sparkline, tint: palette.lineEnd)
                .frame(height: 22)
                .padding(.top, 2)
        }
    }

    private var rangeWinsLabel: String {
        switch selectedRange {
        case .oneDay:    return "TODAY"
        case .sevenDay:  return "THIS WEEK"
        case .thirtyDay: return "THIS MONTH"
        case .oneYear:   return "THIS YEAR"
        }
    }

    /// Title-case label used inside the dropdown menu.
    private func menuLabel(for range: ProgressRange) -> String {
        switch range {
        case .oneDay:    return "Today"
        case .sevenDay:  return "This Week"
        case .thirtyDay: return "This Month"
        case .oneYear:   return "This Year"
        }
    }

    // MARK: Items + XP — derived from live activity log

    private var itemsCleanedCurrent: Int {
        itemsForRange(offsetPeriods: 0)
    }

    private var itemsCleanedPrevious: Int {
        itemsForRange(offsetPeriods: 1)
    }

    private func itemsForRange(offsetPeriods: Int) -> Int {
        // Use the live `activities` log when available; falls back to
        // a synthetic estimate from current vs previous bytes so the
        // tile never reads "0" pre-data. When a category filter is
        // active and the log has no tagged data, fall through to 0
        // (the synthetic estimator can't honestly attribute to a
        // category, so skip it instead of inventing a number).
        guard !activities.isEmpty else {
            if selectedProgressCategory != nil { return 0 }
            let bytes = offsetPeriods == 0
                ? activitySeries.reduce(0, +)
                : previousPeriodSeries.reduce(0, +)
            return max(Int(bytes / 8_000_000), 1)
        }
        let unit = selectedRange.unit
        let count = selectedRange.pointCount
        let anchor = bucketDate(byAdding: -(count * offsetPeriods),
                                unit: unit, from: Date())
        // Earliest bucket key in the window
        let earliestBucket = bucketDate(byAdding: -(count - 1), unit: unit, from: anchor)
        let earliestKey = bucketKey(for: earliestBucket, unit: unit)
        let latestKey = bucketKey(for: anchor, unit: unit)
        return activities.reduce(0) { acc, entry in
            guard let date = entry.date else { return acc }
            // Category filter — skip entries that don't match the
            // active chip when one is set. Untagged legacy entries
            // are skipped under any specific filter.
            if let selectedProgressCategory,
               entry.category != selectedProgressCategory { return acc }
            let key = bucketKey(for: date, unit: unit)
            return (key >= earliestKey && key <= latestKey)
                ? acc + max(entry.itemCount, 0)
                : acc
        }
    }

    /// Per-bucket item counts across the active range. Drives the
    /// Items column sparkline so the trend line under the headline
    /// number matches the bucketing the rest of the tab uses.
    /// Falls back to a synthetic shape derived from `activitySeries`
    /// when the activity log hasn't backfilled — same pattern
    /// `bucketedActivities` uses for bytes so the chart never reads
    /// dead on a fresh install.
    private var itemsSparklineSeries: [Double] {
        let unit = selectedRange.unit
        let count = selectedRange.pointCount
        guard count > 0 else { return [] }

        // Real data path
        if !activities.isEmpty {
            var sums: [Date: Double] = [:]
            for entry in activities {
                guard let date = entry.date, entry.itemCount > 0 else { continue }
                // Same category gate as `bucketedActivities` so the
                // sparkline always matches the hero chart's filter.
                if let selectedProgressCategory,
                   entry.category != selectedProgressCategory { continue }
                let key = bucketKey(for: date, unit: unit)
                sums[key, default: 0] += Double(entry.itemCount)
            }
            let anchor = Date()
            var series: [Double] = []
            for offset in (0..<count).reversed() {
                let bucket = bucketDate(byAdding: -offset, unit: unit, from: anchor)
                let key = bucketKey(for: bucket, unit: unit)
                series.append(sums[key] ?? 0)
            }
            if series.contains(where: { $0 > 0 }) { return series }
        }

        // Synthetic fallback — derive item counts from the bytes
        // series so the sparkline shape mirrors the hero chart's
        // rhythm without needing a separate fake distribution.
        // Skip the fallback when a category filter is active — the
        // bytes series is already zeroed out under that filter, so
        // there's nothing honest to derive from.
        if selectedProgressCategory != nil {
            return Array(repeating: 0, count: count)
        }
        let bytes = activitySeries
        return bytes.map { $0 > 0 ? max($0 / 8_000_000, 1) : 0 }
    }


    private var graphHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headerEyebrowText.uppercased())
                    .font(.custom("Poppins-Bold", size: 10.5))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "A8A29E"))
                    .contentTransition(.opacity)
                Text(headerBytesText)
                    .font(.custom("Poppins-Bold", size: 36))
                    .foregroundColor(.foreground)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
            // Animate only on selection enter/exit, NOT on every drag-tick
            // index change. Firing a fresh `.easeOut(0.22)` 60–120× per
            // second during scrub stacked overlapping animations that
            // bogged down the whole graph header.
            .animation(.easeOut(duration: 0.22), value: selectedPointIndex == nil)
            Spacer()
            deltaChip
        }
    }

    /// Headline bytes — Robinhood-style live-scrub. With no scrub
    /// active, shows the period total (rolled in on appear via
    /// `heroBytesAnimated`). While scrubbing, swaps to the value at
    /// the highlighted bucket so the headline always reflects what
    /// the user's finger is pointing at.
    private var headerBytesText: String {
        if let idx = selectedPointIndex,
           activitySeries.indices.contains(idx) {
            return Self.formatBytes(activitySeries[idx])
        }
        return Self.formatBytes(heroBytesAnimated)
    }

    /// Headline eyebrow — switches between the period summary
    /// ("CLEARED THIS WEEK") and the scrubbed-point timestamp
    /// ("ON THU", "AT 3PM", "IN MAR") so the user's gaze never has
    /// to leave the headline area to read the chart.
    private var headerEyebrowText: String {
        if selectedPointIndex != nil {
            // Reuse the tooltip's `when` string — already formats
            // "Today / Yesterday / N days ago / This month / etc."
            // per range. Prefix with "on" so it reads as a phrase.
            return "on \(selectedTooltipLines.when)"
        }
        // When a category chip is active, replace "cleared this week"
        // with "duplicates this week" / "screenshots this year" /
        // etc — Bloomberg-style scoping where the headline always
        // names the symbol you're looking at.
        if let category = selectedProgressCategory {
            return "\(category.displayName) \(rangeScopeWord)"
        }
        return rangeTotalCopy
    }

    /// Just the time-scope tail ("this week", "this year", etc) used
    /// to compose the filtered eyebrow without duplicating the verb.
    private var rangeScopeWord: String {
        switch selectedRange {
        case .oneDay:    return "today"
        case .sevenDay:  return "this week"
        case .thirtyDay: return "this month"
        case .oneYear:   return "this year"
        }
    }

    /// Momentum tag — Cal AI style: tinted text only, no chip chrome.
    /// Sits at the top right of the graph header, reads as a quiet
    /// note next to the bytes anchor instead of a competing badge.
    private var deltaChip: some View {
        let current = activitySeries.reduce(0, +)
        let prior = previousPeriodSeries.reduce(0, +)
        let pct: Double = prior > 0 ? ((current - prior) / prior) * 100 : 0
        let up = pct >= 0
        let flat = abs(pct) < 1
        let tint: Color = flat
            ? Color(hex: "78716C")
            : (up ? Color(hex: "0F766E") : Color(hex: "C2410C"))
        let icon = flat ? "minus" : (up ? "arrow.up.right" : "arrow.down.right")
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(tint)
            Text("\(flat ? "0" : String(format: "%.0f", abs(pct)))%")
                .font(.custom("Poppins-Bold", size: 13))
                .foregroundColor(tint)
                .monospacedDigit()
            Text("vs \(previousPeriodLabel)")
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(Color(hex: "8C92A4"))
        }
    }

    private var previousPeriodLabel: String {
        switch selectedRange {
        case .oneDay:    return "yesterday"
        case .sevenDay:  return "last week"
        case .thirtyDay: return "prior month"
        case .oneYear:   return "last year"
        }
    }


    private var rangeTotalCopy: String {
        switch selectedRange {
        case .oneDay:    return "cleared today"
        case .sevenDay:  return "cleared this week"
        case .thirtyDay: return "cleared this month"
        case .oneYear:   return "cleared this year"
        }
    }

    /// The existing chart-card range selector — keeps its name for
    /// every existing caller, just forwards to the parameterized
    /// helper now that we have two cards rendering the same pill row
    /// against independent state.
    private var rangeSelector: some View {
        rangePillRow(
            namespace: rangePillNS,
            selection: $selectedRange,
            clearsScrub: true
        )
    }

    /// Sliding-pill range row. Each call site passes its own namespace
    /// (so two instances on screen each own their own
    /// `matchedGeometryEffect` pill without colliding) AND its own
    /// `selection` binding (so the top card can hold 30D while the
    /// breakdown card holds 1D — truly independent time scopes).
    /// `clearsScrub` is true only for the chart card — flipping the
    /// breakdown's range shouldn't blow away an in-progress scrub on
    /// the chart above.
    private func rangePillRow(
        namespace: Namespace.ID,
        selection: Binding<ProgressRange>,
        clearsScrub: Bool
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(ProgressRange.allCases, id: \.self) { range in
                let isSelected = selection.wrappedValue == range
                Button {
                    HapticManager.shared.chartRangeFlip()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        selection.wrappedValue = range
                        if clearsScrub { selectedPointIndex = nil }
                    }
                } label: {
                    Text(range.label)
                        .font(.custom("Poppins-Bold", size: 12.5))
                        .tracking(0.4)
                        .foregroundColor(isSelected ? .white : Color(hex: "78716C"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(alignment: .center) {
                            if isSelected {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "1C1917"), Color(hex: "292524")],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "rangePill", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color(hex: "F5F4F0"))
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.04), lineWidth: 0.5)
                )
        )
    }


    // MARK: 4. Cleanup Mix — where your bytes came from
    //
    // Stacked horizontal bar + four chip rows. Reads at-a-glance as
    // "you cleaned mostly photos this period" without needing legends.
    // Categories derive from the live DashboardSnapshot so the split
    // matches what the user actually saw in the scan; lifetime total
    // is the anchor number so the card has weight without a graph.

    /// Cleanup Mix — reframed as an interactive recommendation card.
    /// Picks the highest-impact category as the hero "Bee's Pick" and
    /// renders the other categories as tappable swap chips below.
    /// This is a feature card, not a chart — it drives action.



    // MARK: - Storage Cleared chart data
    //
    // One non-cumulative series — bytes cleared per bucket (day / week /
    // month depending on range). 7D feeds straight from real
    // `lastSevenDays` buckets. Other ranges use deterministic shaped
    // placeholders derived from `lifetimeBytesSaved` so the chart looks
    // believable without backend history wiring.

    private var activitySeries: [Double] {
        seriesEndingAt(offsetPeriods: 0)
    }

    /// The 2nd line on the chart: the same range shifted back by one
    /// full period. 1D ⇒ yesterday, 7D ⇒ last 7 days, 30D ⇒ prior month,
    /// 1Y ⇒ prior year. This is the comparison that actually means
    /// something: "am I doing more than last time?"
    private var previousPeriodSeries: [Double] {
        seriesEndingAt(offsetPeriods: 1)
    }

    /// Generic series builder. `offsetPeriods = 0` returns current
    /// window; `1` returns the previous comparable window. When a
    /// chip-row category filter is active, only entries tagged with
    /// that leaf category contribute; the synthetic fallbacks return
    /// an all-zero series so a filtered view of a backfill-empty
    /// account doesn't fake activity that didn't happen.
    private func seriesEndingAt(offsetPeriods: Int) -> [Double] {
        // 1. Try real backend activity log first.
        let real = bucketedActivities(unit: selectedRange.unit,
                                      count: selectedRange.pointCount,
                                      offsetPeriods: offsetPeriods,
                                      category: selectedProgressCategory)
        if real.contains(where: { $0 > 0 }) { return real }

        // When a category filter is active and the real log has no
        // tagged data for it, return zeros — don't fall back to the
        // synthetic shapes, which are derived from total lifetime and
        // would fabricate a category-specific shape that isn't real.
        if selectedProgressCategory != nil {
            return Array(repeating: 0, count: selectedRange.pointCount)
        }

        // 2. Range-specific local fallback so the unfiltered chart
        // never reads dead.
        switch selectedRange {
        case .oneDay:
            return offsetPeriods == 0 ? oneDayActivity() : oneDayActivity(scale: 0.78)
        case .sevenDay:
            let buckets = stats.lastSevenDays
            if offsetPeriods == 0,
               !buckets.allSatisfy({ $0.bytes == 0 }) {
                return buckets.map { Double($0.bytes) }
            }
            let base: [Double] = [80, 0, 120, 50, 0, 200, 90].map { $0 * 1_000_000 }
            let scale = offsetPeriods == 0 ? 1.0 : 0.72
            return base.map { $0 * scale }
        case .thirtyDay:
            return thirtyDayActivity(scale: offsetPeriods == 0 ? 1.0 : 0.82)
        case .oneYear:
            return monthlyActivity(months: selectedRange.pointCount,
                                   scale: offsetPeriods == 0 ? 1.0 : 0.68)
        }
    }

    /// 1D — 24 hourly buckets across today. Shaped so daytime hours
    /// pop and overnight hours stay quiet, which matches real-world
    /// phone cleanup behavior.
    private func oneDayActivity(scale: Double = 1.0) -> [Double] {
        let dailyAvg = max(Double(stats.lifetimeBytesSaved) / 365, 80_000_000)
        return (0..<24).map { h in
            // Peak around 10-11am and 8-9pm, low overnight
            let peakA = exp(-pow(Double(h) - 10.5, 2) / 9)
            let peakB = exp(-pow(Double(h) - 20.5, 2) / 11) * 0.85
            let shape = peakA + peakB
            let wobble = sin(Double(h) * 0.6) * 0.15 + 1.0
            return max(0, dailyAvg * 0.12 * shape * wobble * scale)
        }
    }

    /// Roll the live `activities` log into time buckets matching the
    /// selected range. Empty bucket = 0, never nil — keeps the chart
    /// shape stable as data trickles in. When `category` is non-nil,
    /// only entries tagged with that leaf category are summed, which
    /// is how the chip-row filter narrows the chart to one source
    /// (e.g. only Duplicates bytes per day).
    private func bucketedActivities(unit: BucketUnit, count: Int,
                                    offsetPeriods: Int,
                                    category: SavedFindSourceCategory? = nil) -> [Double] {
        guard !activities.isEmpty, count > 0 else {
            return Array(repeating: 0, count: count)
        }
        var sums: [Date: Double] = [:]
        for entry in activities {
            guard let date = entry.date, entry.bytesSaved > 0 else { continue }
            // Category filter — when active, only entries that parsed
            // out a matching `category` (via the action-tag suffix)
            // contribute. Untagged legacy entries fall out of every
            // specific filter, which is the correct behavior.
            if let category, entry.category != category { continue }
            let key = bucketKey(for: date, unit: unit)
            sums[key, default: 0] += Double(entry.bytesSaved)
        }
        let anchor = bucketDate(byAdding: -(count * offsetPeriods),
                                unit: unit, from: Date())
        var series: [Double] = []
        for offset in (0..<count).reversed() {
            let bucketDate = bucketDate(byAdding: -offset, unit: unit, from: anchor)
            let key = bucketKey(for: bucketDate, unit: unit)
            series.append(sums[key] ?? 0)
        }
        return series
    }

    private func bucketKey(for date: Date, unit: BucketUnit) -> Date {
        switch unit {
        case .hour:
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
            return cal.date(from: comps) ?? cal.startOfDay(for: date)
        case .day:
            return cal.startOfDay(for: date)
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return cal.date(from: comps) ?? cal.startOfDay(for: date)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            return cal.date(from: comps) ?? cal.startOfDay(for: date)
        }
    }

    private func bucketDate(byAdding offset: Int, unit: BucketUnit, from base: Date) -> Date {
        let component: Calendar.Component = {
            switch unit {
            case .hour:  return .hour
            case .day:   return .day
            case .week:  return .weekOfYear
            case .month: return .month
            }
        }()
        return cal.date(byAdding: component, value: offset, to: base) ?? base
    }

    /// Per-day cleared bytes for the 30D view. The most recent 7 days
    /// are real; the prior 23 are extrapolated from lifetime with a
    /// weekend-leaning rhythm so the bars feel like genuine history.
    /// `scale < 1` is used to dim the previous-period comparison line.
    private func thirtyDayActivity(scale: Double = 1.0) -> [Double] {
        let recent7 = stats.lastSevenDays
        let recentSum = Double(recent7.reduce(Int64(0)) { $0 + $1.bytes })
        let lifetime = max(Double(stats.lifetimeBytesSaved),
                           max(recentSum * 4, 500_000_000))
        let earlierTotal = max(lifetime - recentSum, lifetime * 0.5)
        let earlierDays = 30 - recent7.count
        let avgEarlier = earlierDays > 0 ? earlierTotal / Double(earlierDays) : 0

        var series: [Double] = []
        for i in 0..<earlierDays {
            let dayOfWeek = (i + 6) % 7
            let weekendBoost: Double = dayOfWeek >= 5 ? 1.45 : 0.85
            let wobble = sin(Double(i) * 0.55) * 0.18 + 1.0
            series.append(max(0, avgEarlier * weekendBoost * wobble * scale))
        }
        for b in recent7 { series.append(Double(b.bytes) * scale) }
        return series
    }

    /// 1Y — 12 monthly buckets. Shaped to accelerate toward the most
    /// recent month so the user feels their pace improving.
    private func monthlyActivity(months: Int, scale: Double = 1.0) -> [Double] {
        let lifetime = max(Double(stats.lifetimeBytesSaved), 2_000_000_000)
        let avg = lifetime / Double(months)
        return (0..<months).map { i in
            let ratio = Double(i) / Double(max(months - 1, 1))
            let momentum = 0.4 + ratio * ratio * 1.6   // 0.4 → 2.0
            let wobble = sin(Double(i) * 1.1 + 0.3) * 0.18 + 1.0
            return max(0, avg * momentum * wobble * scale)
        }
    }

    /// Y-axis ceiling.
    private var activityMax: Double {
        max(activitySeries.max() ?? 1, 1)
    }

    /// Index of the user's best bucket (the trophy/burnt-orange bar).
    /// Nil when every value is zero so we don't crown a "best" of 0.
    private var bestActivityIndex: Int? {
        let series = activitySeries
        guard let m = series.max(), m > 0,
              let idx = series.firstIndex(of: m) else { return nil }
        return idx
    }

    private var xAxisLabels: [String] {
        switch selectedRange {
        case .oneDay:     return ["12a", "6a", "12p", "6p", "Now"]
        case .sevenDay:   return weekdayLetters
        case .thirtyDay:  return ["30D", "20D", "10D", "Today"]
        case .oneYear:    return ["12mo", "8mo", "4mo", "Now"]
        }
    }

    private var selectedTooltipLines: (value: String, when: String) {
        let series = activitySeries
        let cnt = series.count
        guard cnt > 0 else { return ("", "") }
        let raw = selectedPointIndex ?? (cnt - 1)
        let idx = max(0, min(cnt - 1, raw))
        return (
            "\(Self.formatBytes(series[idx])) cleared",
            Self.tooltipWhen(idx: idx, total: cnt, unit: selectedRange.unit)
        )
    }

    private static func tooltipWhen(idx: Int, total: Int, unit: BucketUnit) -> String {
        if idx == total - 1 {
            switch unit {
            case .hour:  return "This hour"
            case .day:   return "Today"
            case .week:  return "This week"
            case .month: return "This month"
            }
        }
        let back = (total - 1) - idx
        switch unit {
        case .hour:
            return back == 1 ? "1 hour ago" : "\(back) hours ago"
        case .day:
            if back == 1 { return "Yesterday" }
            return "\(back) days ago"
        case .week:
            return back == 1 ? "1 week ago" : "\(back) weeks ago"
        case .month:
            return back == 1 ? "1 month ago" : "\(back) months ago"
        }
    }

    fileprivate static func formatBytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(value, 0)), countStyle: .file)
    }

    /// Compact byte string — drops the decimal when value is a whole
    /// number of the unit so hex labels stay punchy ("2 GB", not "2.0 GB").
    fileprivate static func formatBytesShort(_ value: Double) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        fmt.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        fmt.allowsNonnumericFormatting = false
        fmt.zeroPadsFractionDigits = false
        return fmt.string(fromByteCount: Int64(max(value, 0)))
    }


    // MARK: - Weekday + activity helpers

    private var weekdayLetters: [String] {
        let base = ["S","M","T","W","T","F","S"]
        let todayWeekday = cal.component(.weekday, from: Date()) - 1
        return (0..<7).map { i in
            let offset = -6 + i
            let idx = (todayWeekday + offset + 70) % 7
            return base[idx]
        }
    }

    private func dayHadActivity(_ idx: Int) -> Bool {
        let buckets = stats.lastSevenDays
        guard idx >= 0, idx < buckets.count else { return false }
        let b = buckets[idx]
        return b.items > 0 || b.bytes > 0
    }

    // MARK: - Glass card chrome (premium dashboard treatment)
    //
    // Replaces the flat-white `heroCardSurface` with a pure-color
    // "glass catching light" look. No `.ultraThinMaterial` — that
    // reads as iOS-system and competes with the cool-gray canvas.
    // Instead: white base + a subtle top-edge specular highlight +
    // a faint warm radial wash near the top-right (where the donut /
    // chart focal point sits) + an almost-imperceptible bottom-edge
    // darken so the card has depth without looking heavy.
    //
    // Tuned for the Progress hero cards (combinedActivityCard +
    // breakdownCard). Other cards in the file can opt in later by
    // swapping their `.background(heroCardSurface)` for
    // `.background(glassHeroSurface)`.

    private var glassHeroSurface: some View {
        GlassHeroSurface()
    }

    private var glassHeroHairline: some View {
        GlassHeroHairline()
    }
}

/// Light: bright-white liquid-glass recipe — pure white base + a thin
/// top→bottom luminance fade + a single specular meniscus at the top
/// edge. No warm/yellow wash, no bottom shading; reads as a clean
/// frosted glass pane catching light from above.
/// Dark: flat stealth — deep black fill, thin off-white edge.
private struct GlassHeroSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if colorScheme == .dark {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "232328"), Color(hex: "1A1A1D")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 1)
                        .padding(.horizontal, 36)
                        .padding(.top, 0.6)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8)
        } else {
            shape
                // Pure white base — the warm radial wash + bottom
                // darken were what made the card read as "yellowed
                // glass"; bright white reads as fresh frost.
                .fill(Color.white)
                .overlay(
                    // Top→middle luminance fade. Bright white at the
                    // crown softens to ~96% by the card center so the
                    // surface has subtle depth without leaving a hard
                    // edge against the canvas.
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.96)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                )
                .overlay(alignment: .top) {
                    // Top specular meniscus — single bright pixel-thin
                    // band at the very top, blended with `.screen` so
                    // it adds light cleanly over the white below.
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(height: 1)
                        .padding(.horizontal, 36)
                        .padding(.top, 0.6)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct GlassHeroHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if colorScheme == .dark {
            shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75)
        } else {
            // Bright neutral hairline — top is near-white, bottom
            // fades to a soft mid-gray. The previous gold accent
            // (`CFAF5F`) read as a warm tint on the bright-white
            // glass surface; a neutral edge keeps the card cleanly
            // monochrome.
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.5),
                        Color.black.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
    }
}


// MARK: - Tab Switch Notification
//
// The CTAs on the Progress tab fire this so ContentView can switch
// the user back to Home where the cleanup flows actually live. We
// don't duplicate deletion surfaces here.
// MARK: - Progress backend sync modifier
//
// Bundles all the reactive hooks the Progress tab needs onto a single
// view so SwiftUI's type-checker doesn't have to walk a chain of 6+
// modifiers on the page root. Each hook calls back into the parent's
// `reloadFromBackend` via the closure pair.
private struct ProgressBackendSync: ViewModifier {
    let lifetimeBytes: Int64
    let lifetimeItems: Int
    let currentStreak: Int
    let scenePhase: ScenePhase
    let onLightSync: () -> Void
    let onFullSync:  () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: lifetimeBytes) { _, _ in onLightSync() }
            .onChange(of: lifetimeItems) { _, _ in onLightSync() }
            .onChange(of: currentStreak) { _, _ in onFullSync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { onFullSync() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCleanupCategory)) { _ in
                onLightSync()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                onLightSync()
            }
    }
}

extension Notification.Name {
    static let switchToHomeTab = Notification.Name("BeeClean.switchToHomeTab")
    /// Posted by `CleanupRingTile` with the category label (`"Photos"`,
    /// `"Videos"`, `"Screenshots"`, `"Other"`) as the `object`. A parent
    /// view listens and routes to the matching cleanup flow.
    static let openCleanupCategory = Notification.Name("BeeClean.openCleanupCategory")
}




/// Tight press feedback for color swatches — quiet scale + dim that
/// reads as "tapped" without the over-eager button bounce.
private struct DotPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - ChartCustomizationSheet
//
// Single Cal-AI customization sheet for ALL three charts. Opened from
// the paint button at the top right of the Progress header. Replaces
// the three per-chart corner dots that each owned a separate picker
// sheet — one surface, one entry point, three accordion rows.
//
// Layout: heading + three card rows (Activity / Items Cleaned /
// Best Day). Each card shows the chart name, the currently-selected
// palette name, a small palette dot, and a chevron. Tapping a card
// expands a 3-column grid of palette swatches beneath it. Tapping a
// swatch writes through the binding immediately so the chart behind
// the translucent sheet repaints live (the user sees the change
// before deciding whether to keep it).
struct ChartCustomizationSheet: View {
    @Binding var hero: ChartPalette
    @Binding var items: ChartPalette
    @Binding var bestDay: ChartPalette
    @Binding var xp: ChartPalette
    @Binding var segmentation: ChartPalette
    /// True when the segmentation card is in its "Auto" mode — falls
    /// back to the per-scope palette (Photos→honey, Videos→aurora…)
    /// instead of the user-pinned palette. Toggle from the sheet to
    /// switch between auto-tint-on-chip-flip and a fixed look.
    @Binding var segmentationIsAuto: Bool
    @Environment(\.dismiss) private var dismiss
    /// Which row is open. Starts on `.hero` so the sheet doesn't feel
    /// empty on first open — the user sees the palette grid for the
    /// most-prominent chart without having to expand a row first.
    @State private var expanded: ChartSlot? = .hero

    enum ChartSlot: String, Hashable {
        case hero, xp, segmentation, items, bestDay

        var title: String {
            switch self {
            case .hero:         return BCLoc.activity.tr
            case .xp:           return "Coins"
            case .segmentation: return "Segmentation"
            case .items:        return BCLoc.itemsCleaned.tr
            case .bestDay:      return BCLoc.bestDay.tr
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
            ScrollView(showsIndicators: false) {
                // Three outer cards mirror the three dashboard cards:
                // (1) Combined Activity (Activity + Items Cleaned +
                // Best Day all live inside it on the Progress tab —
                // so they share one outer card here), (2) XP, (3)
                // Segmentation.
                VStack(spacing: 12) {
                    combinedActivityChartCard
                    chartRow(.xp, palette: xp) { xp = $0 }
                    segmentationChartRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Combined Activity card — groups the three sub-charts that all
    /// live inside the dashboard's first card (the activity line +
    /// the Items Cleaned sparkline + the Best Day sparkline) under
    /// one outer card. Each sub-row keeps its own palette dot and
    /// expands its own grid in-place; the outer card chrome ties
    /// them together as "Combined Activity" the way the dashboard
    /// surfaces them.
    private var combinedActivityChartCard: some View {
        VStack(spacing: 0) {
            // Card header — names the dashboard surface the three
            // sub-charts belong to so the grouping reads explicitly.
            HStack {
                Text(BCLoc.activity.tr)
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.foreground)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            combinedActivitySubRow(.hero,
                                   label: BCLoc.activity.tr,
                                   palette: hero) { hero = $0 }
            combinedActivitySubDivider
            combinedActivitySubRow(.items,
                                   label: BCLoc.itemsCleaned.tr,
                                   palette: items) { items = $0 }
            combinedActivitySubDivider
            combinedActivitySubRow(.bestDay,
                                   label: BCLoc.bestDay.tr,
                                   palette: bestDay) { bestDay = $0 }
        }
        .background(
            // Pure-white card surface — the previous 62%-white wash
            // read as a dirty gray on the off-white sheet background.
            // Stroke bumped to a more visible 1pt 12%-black so the
            // outline between adjacent cards is unmistakable.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
    }

    /// Divider between sub-rows inside the Combined Activity card.
    /// Bumped from a near-invisible 5%-black hairline (0.5pt) to a
    /// visible 12%-black 1pt line so the user can clearly see which
    /// row they're about to tap — same opacity as the outer card
    /// strokes elsewhere in the sheet. Inset from both edges so the
    /// line reads as a divider, not a full-width slash that touches
    /// the card's outer rounded stroke.
    private var combinedActivitySubDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    /// One row inside the combined activity card. Same accordion
    /// behavior as `chartRow(_:)` but without its own outer card
    /// chrome — the parent `combinedActivityChartCard` owns that.
    @ViewBuilder
    private func combinedActivitySubRow(_ slot: ChartSlot,
                                        label: String,
                                        palette: ChartPalette,
                                        onPick: @escaping (ChartPalette) -> Void) -> some View {
        let isOpen = expanded == slot
        VStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    expanded = isOpen ? nil : slot
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.custom("Poppins-Medium", size: 13.5))
                            .foregroundColor(.foreground)
                        Text(palette.displayName)
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(.foregroundSecondary)
                    }
                    Spacer()
                    paletteDot(palette, size: 12)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "A8A29E"))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                paletteGrid(current: palette, onPick: onPick)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    /// Segmentation row with an extra Auto toggle on top. Auto = use
    /// the per-scope palette that flips when the user changes chip
    /// selection (Photos→honey, Videos→aurora). Off = pin the
    /// user-selected palette across every scope. Visually shaped like
    /// the other rows so it still scans as part of the same family.
    private var segmentationChartRow: some View {
        let slot = ChartSlot.segmentation
        let isOpen = expanded == slot
        return VStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    expanded = isOpen ? nil : slot
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(.custom("Poppins-Bold", size: 15))
                            .foregroundColor(.foreground)
                        Text(segmentationIsAuto
                             ? "Auto · matches the active scope"
                             : segmentation.displayName)
                            .font(.custom("Poppins-Medium", size: 11.5))
                            .foregroundColor(.foregroundSecondary)
                    }
                    Spacer()
                    if !segmentationIsAuto {
                        paletteDot(segmentation, size: 14)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "A8A29E"))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-tint by selected scope", isOn: $segmentationIsAuto)
                        .font(.custom("Poppins-Medium", size: 12.5))
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "F59E0B")))
                    if !segmentationIsAuto {
                        paletteGrid(current: segmentation) { segmentation = $0 }
                    }
                }
                .padding(16)
            }
        }
        // Segmentation card surface now matches the sibling chart
        // rows above it — pure white fill, 1pt 12%-black stroke, and
        // the same soft drop-shadow. The previous `Color.surfaceLight`
        // wash read as a beige patch sitting in the middle of an
        // otherwise white card column. Black hairline outline is what
        // tells the user "this is the card I'm about to tap" — the
        // half-pt `Color.border` it used before was too thin to read
        // against the surrounding sheet background.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
    }

    private var headerRow: some View {
        // Cal-AI header: single bold title, no explanatory subtitle.
        // The cards below speak for themselves — adding "Tap a chart
        // then pick its palette" is the kind of hand-holding copy
        // Cal AI strips out.
        HStack {
            Text(BCLoc.chartColors.tr)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(.foreground)
            Spacer(minLength: 12)
            Button {
                HapticManager.shared.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.foreground)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.surfaceLight))
                    .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func chartRow(_ slot: ChartSlot,
                          palette: ChartPalette,
                          onPick: @escaping (ChartPalette) -> Void) -> some View {
        let isOpen = expanded == slot
        VStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    expanded = isOpen ? nil : slot
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(.custom("Poppins-Bold", size: 15))
                            .foregroundColor(.foreground)
                        Text(palette.displayName)
                            .font(.custom("Poppins-Medium", size: 11.5))
                            .foregroundColor(.foregroundSecondary)
                    }
                    Spacer()
                    paletteDot(palette, size: 14)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "A8A29E"))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                paletteGrid(current: palette, onPick: onPick)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
        }
        .background(
            // Pure-white card surface — the previous 62%-white wash
            // read as a dirty gray on the off-white sheet background.
            // Stroke bumped to a more visible 1pt 12%-black so the
            // outline between adjacent cards is unmistakable.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
        )
    }

    private func paletteGrid(current: ChartPalette,
                             onPick: @escaping (ChartPalette) -> Void) -> some View {
        // Cal-AI grid: just colored dots. No labels under each
        // swatch — the active palette name already shows on the
        // collapsed row header above ("Activity — Honey"), so
        // labeling every swatch is redundant chrome. Wider dots
        // (22pt) since they no longer share vertical room with text.
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(ChartPalette.allCases) { palette in
                Button {
                    // Live-preview write — flips the binding so the
                    // chart behind the translucent sheet repaints
                    // before the user moves on to the next swatch.
                    withAnimation(.easeInOut(duration: 0.18)) {
                        onPick(palette)
                    }
                    HapticManager.shared.filterChange()
                } label: {
                    ZStack {
                        // Selection ring — 1.5pt ink stroke around
                        // the dot. Cal-AI confirmation: present
                        // only on the active swatch, absent everywhere
                        // else. No checkmarks, no badges.
                        Circle()
                            .stroke(Color(hex: "1C1917"), lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                            .opacity(palette == current ? 1 : 0)
                        paletteDot(palette, size: 22)
                    }
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DotPressStyle())
                .accessibilityLabel(palette.displayName)
                .accessibilityAddTraits(palette == current ? [.isSelected, .isButton] : [.isButton])
            }
        }
    }

    /// Glass-polished palette swatch — soft top-left highlight, full-
    /// hue body, subtle bottom shadow vignette. Reads as a translucent
    /// bead of color catching light from above rather than a flat dot.
    @ViewBuilder
    private func paletteDot(_ palette: ChartPalette, size: CGFloat) -> some View {
        ZStack {
            // Body — diagonal palette gradient (lineStart → lineEnd) so
            // every swatch already shows the two-stop ramp the chart
            // will paint on the line, not just one terminal color.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.lineStart, palette.lineEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            // Top-left specular highlight — single bright crescent that
            // sells "glass bead." `.screen` blend so it brightens any
            // palette tint cleanly.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .blendMode(.screen)
                .allowsHitTesting(false)
            // Hairline rim — subtle dark edge so the swatch reads
            // against the bright-white card behind it.
            Circle()
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.6)
                .frame(width: size, height: size)
        }
    }
}
