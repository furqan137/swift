import SwiftUI

// MARK: - Nav Cluster Palette
//
// BitePal-mirrored nav cluster: NEUTRAL frosted gray pill — `regularMaterial`
// + a near-white wash for body, with a subtle warm-neutral gradient
// (`F0F0F2 → EBEBED`) on top. The previous cool-lavender stops
// (`DDE1F2 → EDEEEF`) read as too blue against the BitePal reference,
// which uses a flat-ish system-gray pill with a hint of translucence.
//
// Active tab indicator: pure white CIRCLE-ish pill with a stronger
// drop shadow to mimic BitePal's distinct lifted look — the indicator
// floats above the gray pill as its own surface.
enum NavPalette {
    static let pillGradientTop      = Color(hex: "F1F1F3")   // warm-neutral light gray
    static let pillGradientBottom   = Color(hex: "E8E8EB")   // a touch darker for depth
    static let pillBorder           = Color.black.opacity(0.05)
    // Resting (unselected) tabs. The previous `#9C9CA1` was a true mid-
    // gray that washed out against the bar's `#F1F1F3 → #E8E8EB`
    // gradient — labels became almost illegible without focus.
    // `#4F4F54` is a deeper graphite that holds clear contrast against
    // the bar surface while staying visibly subordinate to the
    // active-tab espresso ink (`#1C1917`).
    static let mutedText            = Color(hex: "4F4F54")
    static let activeText           = Color(hex: "1C1917")   // espresso ink on white indicator

    // Indicator (selected pill) — pure white pops cleanly off the warm
    // gray. Stronger drop shadow (matches BitePal's lifted-circle look).
    static let indicatorFill    = Color.white

    // + button — clean matte black
    static let plusInkTop       = Color(hex: "2C2C2E")
    static let plusInkBottom    = Color(hex: "0A0A0A")
}

// MARK: - Bottom Navigation Bar
struct BottomNavBar: View {
    /// Finger must travel this far (in points) before the gesture switches
    /// from tap-mode (animated snap to tab center) into drag-mode (indicator
    /// tracks finger 1:1). Tuned to feel decisive without eating fast swipes.
    fileprivate static let dragActivationDistance: CGFloat = 6

    @Binding var selectedTab: ContentView.Tab
    /// Kept on the type to avoid breaking the existing public API the
    /// LockedNavBarModifier passes through, but no longer drives any UI —
    /// the FAB now opens Ask Bee directly via `onAskBee`.
    @Binding var isPlusMenuOpen: Bool
    var onAskBee: () -> Void = {}

    /// Live finger position (nil when not touching). Indicator follows this
    /// while dragging, then animates back to the resting tab on release.
    /// Using @GestureState so SwiftUI auto-resets it if the gesture is
    /// cancelled (prevents stuck indicator that can freeze interaction).
    @GestureState private var dragX: CGFloat? = nil
    @State private var lastHapticIndex: Int = -1
    @State private var isDragging: Bool = false

    // + button tap interaction
    @State private var plusPressed: Bool = false

    private var tabs: [ContentView.Tab] { ContentView.Tab.allCases }
    private var selectedIndex: Int {
        tabs.firstIndex(of: selectedTab) ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            tabStripCluster
            Spacer(minLength: 12)
            plusButton
                .frame(width: plusSize, height: plusSize)
        }
        // Symmetric leading + trailing insets so the bar's negative
        // space reads as a balanced frame around the cluster instead
        // of the strip hugging the left rail with the FAB pinned far
        // out on the right. 16pt on each side matches the bar's outer
        // shadow radius so the FAB and strip both sit one shadow-width
        // inboard from the bar edge — the cluster feels intentionally
        // centered inside its capsule rather than docked at the ends.
        .padding(.leading, 16)
        .padding(.trailing, 16)
    }

    // BitePal-style layout: the tab cluster is a fixed-width pill pinned to
    // the LEFT, with the FAB pinned to the RIGHT. Compile-time constants —
    // no GeometryReader — so the drag gesture's hot path reads scalars, not
    // geometry, and the strip never balloons to fill the screen width.
    // BitePal-cloned proportions. Cells are narrow (icon-only, no
    // label to make room for), strip is substantial (60pt), FAB
    // matches strip height for embedded baseline.
    private let tabCellWidth: CGFloat = 56
    private let stripHeight: CGFloat = 60
    private var stripWidth: CGFloat { CGFloat(tabs.count) * tabCellWidth }

    /// Plus button diameter. Trimmed from 68 → 60 so the FAB sits flush
    /// with the tab strip's vertical extent — the prior 68 was the
    /// "premium anchor" treatment which the user found read as too
    /// chunky against the slimmer strip. 60pt matches `stripHeight`
    /// exactly, so the chat circle now reads as a refined sibling of
    /// the tabs rather than a heavier satellite.
    private let plusSize: CGFloat = 60

    /// Active indicator pill — flush with the cell edges (no insets).
    /// On the leftmost / rightmost tab the white capsule's rounded
    /// ends mathematically match the gray pill's curve.
    private let indicatorHorizontalInset: CGFloat = 0
    private let indicatorVerticalInset: CGFloat = 0

    // MARK: - Tab Strip Cluster — fixed-width left-pinned pill
    private var tabStripCluster: some View {
        let indicatorX = indicatorCenterX(tabWidth: tabCellWidth, stripWidth: stripWidth)

        return ZStack(alignment: .leading) {
            // Gliding active indicator — single source of truth for X.
            // While dragging: no implicit animation, indicator tracks finger 1:1.
            // On release: spring snaps to selected tab.
            indicator(tabWidth: tabCellWidth, stripHeight: stripHeight)
                .position(x: indicatorX, y: stripHeight / 2)
                .animation(
                    isDragging ? nil : .spring(response: 0.42, dampingFraction: 0.82),
                    value: indicatorX
                )

            // Tab content sits on top of indicator
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    NavTabItem(tab: tab, isSelected: index == selectedIndex)
                        .frame(width: tabCellWidth, height: stripHeight)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false) // gesture lives on parent
                }
            }
        }
        .frame(width: stripWidth, height: stripHeight)
        // Force the indicator's silhouette to share the bar's exact
        // Capsule curve. Without this clip, sub-pixel rendering of two
        // independently-drawn Capsules (bar background vs. indicator)
        // leaves a visible gray crescent at the leftmost/rightmost tabs.
        .clipShape(Capsule())
        .contentShape(Capsule())
        .background(stripBackground)
        .gesture(stripDragGesture(stripW: stripWidth, tabW: tabCellWidth))
    }

    private func stripDragGesture(stripW: CGFloat, tabW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragX) { value, state, _ in
                // Only feed the indicator the live finger X once the finger
                // has actually moved. Pure taps leave dragX nil so the
                // indicator stays driven by `selectedIndex` and the implicit
                // `.animation(value: indicatorX)` springs it smoothly to the
                // tapped tab's center — no teleport.
                let travel = hypot(value.translation.width, value.translation.height)
                guard travel > Self.dragActivationDistance else { return }
                let touchX = value.location.x
                state = min(max(touchX, tabW / 2), stripW - tabW / 2)
            }
            .onChanged { value in
                let touchX = value.location.x
                let travel = hypot(value.translation.width, value.translation.height)
                if !isDragging && travel > Self.dragActivationDistance {
                    isDragging = true
                }
                let idx = min(max(Int(touchX / tabW), 0), tabs.count - 1)
                guard idx != lastHapticIndex else { return }
                lastHapticIndex = idx
                // Crisp single-transient "switch click" — brighter than
                // a stock selection tick so the tab change reads as a
                // deliberate hop, but light enough that sweeping across
                // tabs in one drag still feels musical.
                HapticManager.shared.navTabTap()
                if selectedTab != tabs[idx] {
                    selectedTab = tabs[idx]
                }
                if isPlusMenuOpen {
                    isPlusMenuOpen = false
                }
            }
            .onEnded { _ in
                isDragging = false
                lastHapticIndex = -1
            }
    }

    private func indicatorCenterX(tabWidth: CGFloat, stripWidth: CGFloat) -> CGFloat {
        if let dragX = dragX { return dragX }
        return CGFloat(selectedIndex) * tabWidth + tabWidth / 2
    }

    // MARK: - Indicator
    //
    // Full-height, full-cell-width capsule. The user reported visible
    // bar background around the active tab — that was caused by the
    // previous version's 6 pt horizontal + vertical insets. With this
    // version:
    //   • Height = strip height → no top/bottom gap (fills the bar
    //     vertically edge-to-edge).
    //   • Width  = tab cell width → no left/right gap inside its cell.
    //
    // Capsule-on-Capsule corner alignment: both the strip background
    // and this indicator are Capsules with height = strip height, so
    // their rounded ends share radius = stripHeight/2. When the active
    // tab is the leftmost (Home) or rightmost, the indicator's rounded
    // end mathematically matches the parent capsule's curve exactly —
    // no exposed wedge of bar background, no clip-out artefacts.
    //
    // The drop shadows then visually lift the active pill above the
    // bar without changing its shape, so the active tab reads as a
    // pill resting flush with the strip's edges, not a smaller pill
    // floating inside it.
    private func indicator(tabWidth: CGFloat, stripHeight: CGFloat) -> some View {
        indicatorSurface
            .frame(
                width: max(tabWidth - indicatorHorizontalInset * 2, 0),
                height: max(stripHeight - indicatorVerticalInset * 2, 0)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    /// Indicator base capsule with all its overlays — extracted to keep
    /// the view-builder happy. Without the split SwiftUI's type-checker
    /// gives up trying to resolve the indicator + plusButton + body in
    /// one pass.
    private var indicatorSurface: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(hex: "FAFAFB")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(indicatorRimLight)
            .overlay(indicatorHairline)
    }

    private var indicatorRimLight: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.8
            )
            .blendMode(.plusLighter)
    }

    private var indicatorHairline: some View {
        Capsule()
            .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
    }

    // MARK: - Bar Background
    //
    // The bar needs to read as a distinctly elevated surface against the
    // GlassPanel cards above it — the user reported the previous flat
    // pill blended into the screen and didn't pop. We lift it with:
    //   • A solid (less translucent) gradient body so the bar holds its
    //     color against the canvas behind it instead of bleeding through.
    //   • A bright rim-light along the top edge — gives the impression
    //     of light catching the front-facing curve of a physical pill.
    //   • Stacked drop shadows: one tight + dark for shape definition,
    //     one wide + soft for ambient lift. Together they make the bar
    //     visibly float above the cards.
    private var stripBackground: some View {
        stripBackgroundSurface
            .shadow(color: Color.black.opacity(0.16), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    /// Strip background base capsule + the rim-light / bevel / hairline
    /// overlay stack — extracted so the SwiftUI view-builder can resolve
    /// each piece in isolation instead of one 4-overlay deep chain.
    private var stripBackgroundSurface: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        NavPalette.pillGradientTop,
                        NavPalette.pillGradientBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(stripRimLight)
            .overlay(stripBottomBevel)
            .overlay(stripHairline)
    }

    private var stripRimLight: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.8
            )
            .blendMode(.plusLighter)
    }

    private var stripBottomBevel: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.06)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                ),
                lineWidth: 0.6
            )
    }

    private var stripHairline: some View {
        Capsule()
            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
    }

    // MARK: - Ask Bee FAB — dark circle with a honey-yellow bee hex glyph
    //
    // Direct shortcut into Ask Bee — no more plus-menu, no xmark
    // transition. One tap, one destination. The hex is the BeeClean brand
    // cue (mirrors the Ask Bee tile's internal glyph) so the button
    // telegraphs "tap to talk to the bee."
    private var plusButton: some View {
        Button {
            handleAskBeeTap()
        } label: {
            plusButtonLabel
        }
        .buttonStyle(.plain)
    }

    private var plusButtonLabel: some View {
        ZStack {
            plusButtonSurface
            // Chat-bubble glyph — solid Color (not LinearGradient) so
            // SwiftUI can smoothly INTERPOLATE between white and
            // iMessage blue. With the two-LinearGradient swap the
            // color flipped instantly; with Color values it morphs
            // gradually over the animation duration, which is the
            // "watching it shift from white to blue" effect the user
            // asked for before the screen transitions.
            Image(systemName: "message.fill")
                // Scaled down with the FAB (was 26 for the 68pt disc) so
                // the glyph keeps the same ~38% proportional weight
                // inside the slimmed 60pt circle.
                .font(.system(size: 22, weight: .semibold))
                // Light: white icon, morphs to iMessage blue (`#0A84FF`)
                // when pressed against the obsidian disc. Dark: button
                // background is already iMessage blue, so the icon stays
                // white at all times (a blue glyph would vanish on the
                // blue disc). Press feedback is the scale + shadow shift.
                .foregroundColor(messageIconColor)
                .offset(y: -1)
        }
        .frame(width: plusSize, height: plusSize)
        .scaleEffect(plusPressed ? 0.92 : 1.0)
        .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 12)
    }

    /// Obsidian circle with its full stack of rim + inner-glow + hairline
    /// overlays — extracted from `plusButton` to keep SwiftUI's view-
    /// builder from blowing past its type-check budget on the surrounding
    /// `BottomNavBar` body. Each overlay is its own typed value, so the
    /// inferred return is just `some View` instead of a 4-deep
    /// `ModifiedContent<…>` chain.
    private var plusButtonSurface: some View {
        // Adaptive fill — light mode keeps the signature obsidian disc.
        // Dark mode lifts to a slightly brighter slate so the button
        // pops on the polished glass canvas instead of sinking into it.
        // The morph from #0A84FF (pressed) → white still reads on either.
        Circle()
            .fill(plusButtonGradient)
            .overlay(plusButtonRimLight)
            .overlay(plusButtonInnerGlow)
            .overlay(plusButtonHairline)
    }

    @Environment(\.colorScheme) private var plusButtonScheme

    private var plusButtonGradient: LinearGradient {
        // iMessage-blue disc — same `#0A84FF → #0066CC` ramp Apple
        // uses on outbound iMessage bubbles. The user explicitly
        // wants this back: the chat-bubble glyph + blue disc is the
        // universal "tap to chat" cue and reads better than the
        // recent obsidian treatment.
        return LinearGradient(
            colors: [
                Color(hex: "0A84FF"),
                Color(hex: "0066CC")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Icon tint — white on the iMessage-blue disc in every state. The
    /// previous white→blue morph-on-press was specific to the obsidian
    /// disc; against a blue background a blue glyph would vanish.
    private var messageIconColor: Color { .white }

    private var plusButtonRimLight: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 1
            )
            .blendMode(.plusLighter)
    }

    private var plusButtonInnerGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: plusSize * 0.45
                )
            )
            .blendMode(.plusLighter)
    }

    private var plusButtonHairline: some View {
        Circle()
            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
    }

    // MARK: - Ask Bee Tap Handling
    //
    // The icon color is the visible signal here — driven by `plusPressed`
    // it lerps from white → iMessage blue over ~220ms before the screen
    // transitions to Ask Bee. The compression spring runs in parallel
    // (tighter response so it doesn't compete with the color morph).
    private func handleAskBeeTap() {
        // FAB gets the signature Cal-AI "thock" — the dedicated
        // CoreHaptics click+echo pattern (vs a flat selection tick)
        // that makes the primary entry point feel deliberately
        // tactile. `tapSensation()` is what this wrapper exists for.
        HapticManager.shared.tapSensation()

        // 0.7s color morph — slow enough for the user to actually
        // watch the bubble lerp from white → iMessage blue. Anything
        // shorter and it reads as a flash; this duration lets the
        // transition feel like a deliberate "preparing to chat" cue.
        withAnimation(.easeInOut(duration: 0.72)) {
            plusPressed = true
        }

        // Wait for the morph + a short "fully blue" beat before
        // firing navigation, so AskBee opens over a locked-blue
        // bubble (not a still-morphing one).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            onAskBee()

            // Reset behind the fullScreenCover so the next tap starts
            // from white again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    plusPressed = false
                }
            }
        }
    }
}

