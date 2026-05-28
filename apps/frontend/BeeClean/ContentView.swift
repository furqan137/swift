import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .charging
    @State private var isExpanded = false
    @State private var quickActionDestination: QuickActionDestination?
    @State private var showAskBee = false
    @StateObject private var theme = ThemeService.shared
    @ObservedObject private var indexingService = IndexingService.shared
    // NOTE: BottomNavBarVisibility is intentionally observed inside the
    // NavBarSlot wrapper (see below), NOT here. Every nav into/out of a
    // detail view flips `hideRequests`, and previously that fired a full
    // ContentView body recompute — re-evaluating the keptAliveTabs +
    // NavigationStack + all four tab roots — visible as 1-2 frames of
    // nav-bar lag on every push/pop. Scoping the subscription to the
    // slot lets only the bar's container re-render on visibility flips.

    /// Tabs whose root views have actually been mounted. Cold start
    /// includes ONLY the active tab so the post-splash first frame
    /// paints just the bee/Charging hierarchy instead of stalling on
    /// four simultaneous `.task` kickoffs (one per tab). The other
    /// three mount on a deferred tick — by which point the user has
    /// already seen a stable Home screen. User-driven taps to a not-
    /// yet-mounted tab insert it immediately so the first nav switch
    /// stays responsive.
    @State private var mountedTabs: Set<Tab> = [.charging]
/// Observes app foreground/background transitions. Used to force
    /// the theme to re-evaluate the moment the user comes back —
    /// otherwise an app left running overnight stays in night mode
    /// past 06:00 until either ChargingView re-appears (`.task`) or
    /// the 5-min ThemeManager timer ticks. Both singletons recompute
    /// from the device's local hour on demand, so this is cheap.
    @Environment(\.scenePhase) private var scenePhase

    private let secondaryTabBottomInset: CGFloat = 132

    enum Tab: String, CaseIterable, Hashable {
        case charging = "Charging"
        case progress = "Progress"
        case more = "More"

        var symbolImage: String {
            switch self {
            case .charging: return "house"
            case .progress: return "chart.bar"
            case .more: return "ellipsis.circle"
            }
        }
    }

    enum QuickActionDestination: String, Identifiable {
        case askBee
        case widgets
        case secretSpace
        case rateUs
        case email
        case compress

        var id: String { rawValue }
    }

    var body: some View {
        // Outer ZStack is the absolute root of the view hierarchy. The nav
        // bar attaches HERE, outside the NavigationStack — that means none
        // of the per-tab modifiers (background, color scheme, safe-area
        // insets, toolbar visibility) live in a container that the bar
        // shares. SwiftUI cannot re-layout the bar in response to any
        // per-tab change because the bar's container never changes.
        //
        // The bar is hidden only while a `quickActionDestination` is
        // pushed onto the NavigationStack — those routes (Ask Bee, Secret
        // Space, etc) are full-screen modal-like flows that intentionally
        // own the whole canvas.
        ZStack(alignment: .bottom) {
            NavigationStack {
                ZStack(alignment: .bottomTrailing) {
                    // All four tab roots mounted at once via ZStack +
                    // opacity toggle. Switching `selectedTab` no longer
                    // tears down + reconstructs the view, so .task closures
                    // don't refire and view-body computation is preserved.
                    // Result: tab switches are instant — same feel as a
                    // native UITabBarController with kept-alive children.
                    // Memory cost is bounded since most state lives in
                    // shared singletons (ContactsViewModel.shared, etc.).
                    keptAliveTabs
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isExpanded {
                        // Dimmed overlay — app clearly visible underneath
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                HapticManager.shared.impact(.light, intensity: 0.4)
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                    isExpanded = false
                                }
                            }
                    }

                    if isExpanded {
                        // Bottom scrim — masks whatever's directly behind the
                        // quick-action tiles so dense per-tab content (the
                        // contacts-permission "Allow Contacts Access" CTA in
                        // particular) doesn't visually crowd Ask Bee /
                        // Secret Space.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.0),
                                    Color.black.opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 280)
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                    // NOTE: quickActionsContent moved to the OUTER ZStack —
                    // see below — so its y-position is consistent across
                    // tabs. When it lived here, per-tab safe-area handling
                    // (Contacts permission view's bottom CTA, Email's
                    // nested NavigationStack inset) shifted the tiles to
                    // different y values per tab. Anchoring it to the same
                    // outer ZStack as the nav bar gives one stable origin.
                }
                .background(backgroundView(for: selectedTab))
                .ignoresSafeArea(.keyboard)
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                // Window scheme is owned by BeeCleanApp's root modifier
                // (drives status bar + every child's default colorScheme env).
                // HomeView locally overrides via `.environment(\.colorScheme, …)`
                // so its subtree ignores the user's Light/Dark pick.
                // Defer mounting non-active tabs until ~700ms after the
                // first frame paints. By then the splash has finished
                // fading, the bee mascot is on screen, and the user is
                // looking at a stable Home view — running Contacts /
                // Email / Compress `.task` kickoffs at THAT moment is
                // invisible. Doing it on the first frame instead (the
                // old behavior) stacked four simultaneous initial loads
                // onto the same render pass that the splash crossfade
                // was animating through, producing the post-splash
                // stutter the user reported.
                .task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    let rest: Set<Tab> = [.progress, .more]
                    let toMount = rest.subtracting(mountedTabs)
                    if !toMount.isEmpty {
                        mountedTabs.formUnion(toMount)
                    }
                }
                // User-driven tab tap before the deferred mount lands:
                // mount the destination tab immediately so the first
                // nav switch never feels delayed. Idempotent; once
                // mounted a tab stays mounted.
                .onChange(of: selectedTab) { _, newTab in
                    if !mountedTabs.contains(newTab) {
                        mountedTabs.insert(newTab)
                    }
                    // Safety: a dangling hide-counter (modifier didn't get
                    // a chance to release) would otherwise keep the nav
                    // bar hidden across tabs. Tab switch is a clean reset
                    // point — no pushed view should outlive its tab.
                    BottomNavBarVisibility.shared.forceClear()
                }
                // Progress tab's "Start today's cleanup" CTA fires this
                // notification — switch to the Home (charging) tab where
                // the actual cleanup flows live so Progress never has to
                // duplicate them.
                .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = .charging
                    }
                }
                // Progress > Cleanup Mix > tap on a category ring →
                // jump back to Home where the per-category preview
                // cards live. Future: route directly into the matching
                // cleanup flow once Progress carries deep-link state.
                .onReceive(NotificationCenter.default.publisher(for: .openCleanupCategory)) { _ in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = .charging
                    }
                }
                .onChange(of: quickActionDestination) { _, newValue in
                    // When the dashboard's quick-action navigation pops,
                    // clear any leftover hide so the bar reappears
                    // instantly with the pop animation.
                    if newValue == nil {
                        BottomNavBarVisibility.shared.forceClear()
                    }
                }
                .navigationDestination(item: $quickActionDestination) { destination in
                    switch destination {
                    case .askBee:
                        EmptyView() // Handled by .fullScreenCover
                    case .widgets:
                        WidgetsView()
                    case .secretSpace:
                        SecretSpaceView()
                    case .rateUs:
                        RateUsView()
                    case .email:
                        EmailView(showsBackButton: true)
                    case .compress:
                        CompressView()
                    }
                }
            }
            .ignoresSafeArea(.keyboard)

            // Plus-menu (Ask Bee + Secret Space tile popover) removed —
            // the FAB now navigates straight into Ask Bee via the
            // BottomNavBar's onAskBee callback. Secret Space is reachable
            // from the More tab.

            // Nav bar slot — scoped observation of BottomNavBarVisibility
            // lives here, NOT in ContentView, so hide/show flips don't
            // invalidate the parent body.
            NavBarSlot(
                // Hidden whenever the user is inside a Quick Access
                // destination (Photos / Videos / Emails / Compress) and
                // restored instantly on exit. `forceClear()` runs on the
                // destination-flip so the bar pops back in with the pop
                // animation, not after it.
                hidden: quickActionDestination != nil,
                selectedTab: $selectedTab,
                isPlusMenuOpen: $isExpanded,
                onAskBee: { showAskBee = true }
            )
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showAskBee) {
            NavigationStack {
                AskAIView()
            }
        }
    }

    /// Root tabs ZStack. SwiftUI keeps every mounted child alive across
    /// selection changes, so re-entering an already-visited tab is
    /// INSTANT — no `.task` re-fire, no @State reset, no view-body
    /// recompute. Hidden mounted tabs stop receiving touches via
    /// `.allowsHitTesting(false)`.
    ///
    /// Cold-start trick: only the currently-selected tab is mounted on
    /// the first frame. The other three are inserted into `mountedTabs`
    /// after a deferred tick (see `body.task`) so their `.task`
    /// kickoffs (each of which fires Gmail/Contacts/Photos work) don't
    /// land on the SAME frame the splash dismisses on. User-driven tab
    /// switches mount the destination immediately, so the first nav tap
    /// after launch never feels delayed either.
    @ViewBuilder
    private var keptAliveTabs: some View {
        ZStack {
            if mountedTabs.contains(.charging) {
                ChargingView()
                    .opacity(selectedTab == .charging ? 1 : 0)
                    .allowsHitTesting(selectedTab == .charging)
            }

            if mountedTabs.contains(.progress) {
                ProgressTabView()
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: secondaryTabBottomInset)
                    }
                    .opacity(selectedTab == .progress ? 1 : 0)
                    .allowsHitTesting(selectedTab == .progress)
            }

            if mountedTabs.contains(.more) {
                MoreView(showsBackButton: false)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: secondaryTabBottomInset)
                    }
                    .opacity(selectedTab == .more ? 1 : 0)
                    .allowsHitTesting(selectedTab == .more)
            }
        }
    }

    @ViewBuilder
    private func backgroundView(for tab: Tab) -> some View {
        switch tab {
        case .charging:
            // Day → bee_bg_structured, Night → bee_bg_night.
            // ThemeService decides based on the user's local hour
            // (driven by backend, falls back to local compute).
            ZStack {
                // Top-aligned so vertical crop lands on the asset's blank
                // green field at the bottom instead of clipping the sky.
                // The night asset's two clouds (upper-left + upper-right)
                // disappear under `.scaledToFill`'s default center-crop
                // when the device aspect drifts a few pixels off the
                // asset's 0.46 ratio.
                Image(theme.scheduleMode == .dark ? "bee_bg_night" : "bee_bg_structured")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .ignoresSafeArea()
                    .id(theme.scheduleMode)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.6), value: theme.scheduleMode)
        case .more:
            // Adaptive canvas — same `Color.background` token MoreView's
            // own body uses, so a cross-tab transition doesn't flash a
            // hardcoded shade against the new in-tab dark/light surface.
            Color.background.ignoresSafeArea()
        default:
            // Progress + every other in-scope tab.
            Color.background.ignoresSafeArea()
        }
    }

    private var isFailedState: Bool {
        if case .failed = indexingService.state { return true }
        return false
    }

    private var askBeeSubtitle: String? {
        switch indexingService.state {
        case .complete, .notStarted:
            return nil
        case .inProgress(_, let progress):
            return "Getting ready · \(Int(progress * 100))%"
        case .paused:
            return "Paused — will resume soon"
        case .failed:
            return "Tap to retry"
        case .blockedNoPhotoPermission:
            return "Photo access needed"
        }
    }

    @ViewBuilder
    private var quickActionsContent: some View {
        HStack(spacing: 12) {
            askBeeTile
            secretSpaceTile
        }
        .padding(0)
    }

    // MARK: - Ask Bee Tile (sleek "talk to the bee" treatment)
    //
    // Distinguished from Secret Space deliberately — Ask Bee is the
    // app's marquee AI surface, so the tile reads as "tap to chat":
    //   • Dark honey-charcoal gradient (premium AI tile look)
    //   • Custom chat-bubble + bee-hexagon glyph (signals conversation)
    //   • "ASK" pill chip beside "Bee" so the verb is immediate
    //   • Indexing subtitle in dim warm-white so the state stays legible
    //     on the dark surface
    private var askBeeTile: some View {
        Button {
            showAskBee = true
            // Press → commit two-beat (28ms apart). Same primitive the
            // four Home Quick Access tiles use, so Ask Bee feels
            // continuous with the rest of the app's entry-points
            // instead of like a one-off rigid pop.
            HapticManager.shared.quickAccessCommit()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 12) {
                // Glyph: chat bubble with a honey-yellow hexagon (bee)
                // tucked inside. Telegraphs "talk to the bee" without
                // needing a literal photographic mascot.
                ZStack {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.white)
                    Image(systemName: "hexagon.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "F5B400"))
                        .offset(y: -2)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("ASK")
                            .font(.custom("Poppins-Bold", size: 9))
                            .tracking(1.2)
                            .foregroundStyle(Color(hex: "0F0F12"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "F5B400"))
                            )
                        Text("Bee")
                            .font(.custom("Poppins-Bold", size: 16))
                            .foregroundStyle(Color.white)
                    }

                    Text(askBeeSubtitle ?? "Tap to chat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            isFailedState
                                ? Color(hex: "FF6B6B")
                                : Color.white.opacity(0.65)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "2C2C2E"),
                                Color(hex: "0A0A0A")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(QuickActionPressStyle())
    }

    // MARK: - Secret Space Tile (standard white tile)
    private var secretSpaceTile: some View {
        Button {
            quickActionDestination = .secretSpace
            // `buttonTap()` — this is a nav tile, not a destructive
            // action. The prior `impact(.rigid, 0.7)` read as a hard
            // warning thump which made the lock chip feel scarier than
            // it should; the lock is a navigation affordance, the PIN
            // gate is what protects the content.
            HapticManager.shared.buttonTap()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                isExpanded = false
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.foreground.opacity(0.85))

                Text("Secret Space")
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundStyle(Color.foreground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(QuickActionPressStyle())
    }
}

// MARK: - Quick Action Press Style
//
// Tactile spring feedback for the + menu's Ask Bee / Secret Space tiles.
// `.buttonStyle(.plain)` left these completely flat on press — no scale,
// no shadow change — so taps didn't read as taps. This style:
//   • Scales down to 0.94 on press, with a snappy spring response (0.18s)
//   • Springs back with a tiny overshoot for the "rubber" bounce feel
//   • Compresses the shadow on press so the card visually sits closer to
//     the surface, then lifts back when released
//   • Mild brightness dim (0.92) so the press registers visually even
//     before the scale lands
private struct QuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.18, dampingFraction: 0.55)
                    : .spring(response: 0.36, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}

private struct QuickAction: Identifiable {
    let id = UUID()
    let destination: ContentView.QuickActionDestination
    let icon: String
    let title: String
}

private let quickActions: [QuickAction] = [
    QuickAction(destination: .askBee, icon: "hexagon.fill", title: "Ask Bee"),
    QuickAction(destination: .secretSpace, icon: "lock.fill", title: "Secret Space")
]

// MARK: - Nav Bar Slot
//
// Tight wrapper that owns the BottomNavBarVisibility subscription so
// hide/show flips only invalidate this view, not the entire ContentView
// body. Previously the @StateObject sat on ContentView, and every
// push/pop of a detail view (which flipped `hideRequests`) re-evaluated
// keptAliveTabs + NavigationStack + all tab roots — 1-2 frames of
// visible nav-bar lag on every navigation. This wrapper isolates the
// reactive surface.
private struct NavBarSlot: View {
    let hidden: Bool
    @Binding var selectedTab: ContentView.Tab
    @Binding var isPlusMenuOpen: Bool
    let onAskBee: () -> Void

    @StateObject private var navVisibility = BottomNavBarVisibility.shared

    private var shouldShow: Bool { !hidden && !navVisibility.isHidden }

    var body: some View {
        // ALWAYS mount BottomNavBar — control visibility via opacity +
        // allowsHitTesting instead of `if`. Previously the `if` toggled
        // mount/unmount, which made the bar take 1-2 frames to rebuild
        // its gradient/shadow stack on every reappear. With always-mount,
        // the bar's view tree is built once and the show/hide is a single
        // opacity flip — no rebuild, no transition delay, instant pop-in
        // when a detail view dismisses.
        BottomNavBar(
            selectedTab: $selectedTab,
            isPlusMenuOpen: $isPlusMenuOpen,
            onAskBee: onAskBee
        )
        .padding(.bottom, LockedNavBarModifier.bottomInset)
        .padding(.horizontal, LockedNavBarModifier.horizontalInset)
        .zIndex(LockedNavBarModifier.stackingOrder)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .opacity(shouldShow ? 1 : 0)
        .allowsHitTesting(shouldShow)
        // No animation on the opacity flip — the bar should pop in/out
        // instantly. A fade compounded with SwiftUI's natural onDisappear
        // delay used to stack visible lag past one second.
        .animation(nil, value: shouldShow)
    }
}

#Preview {
    ContentView()
}
