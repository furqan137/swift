import SwiftUI

// MARK: - Nav Tab Item (icon + label, no own background)
struct NavTabItem: View {
    let tab: ContentView.Tab
    let isSelected: Bool

    private var isHome: Bool { tab == .charging }

    /// Cached `Font` values — loaded once at type init instead of via
    /// `Font.custom(...)` on every body re-render. The drag gesture
    /// updates `selectedTab` ~60×/sec while gliding, so without this
    /// cache the registry was getting hammered for 4 tab labels per tick.
    static let activeFont = Font.custom("Poppins-Bold", size: 10)
    static let restingFont = Font.custom("Poppins-SemiBold", size: 10)

    var body: some View {
        // BitePal layout: icon-only, no labels under the icons.
        Image(systemName: displayedIconName)
            .font(.system(size: 22, weight: isSelected ? .heavy : .semibold))
            .foregroundColor(isSelected ? NavPalette.activeText : NavPalette.mutedText)
            .frame(width: 28, height: 28)
            .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    private var displayedTitle: String {
        if isHome { return "Home" }
        return tab.rawValue
    }

    private var displayedIconName: String {
        if isHome {
            return isSelected ? "house.fill" : "house"
        }
        if isSelected {
            switch tab {
            case .progress: return "chart.bar.fill"
            // Plain `ellipsis` (3 dots) instead of `ellipsis.circle.fill`
            // so the More tab's selected glyph has the same optical
            // weight as `house.fill` / `chart.bar.fill` — no chunky
            // outer circle dominating the cell's center.
            case .more:     return "ellipsis"
            default:        return tab.symbolImage
            }
        }
        return tab.symbolImage
    }
}

// MARK: - Locked Nav Bar Position Modifier
//
// Canonical way to attach the BottomNavBar to the app. This modifier is the
// single source of truth for the nav bar's position. Apply it once at the
// highest screen-level container (currently `ContentView`'s root ZStack) and
// the bar is guaranteed to stay pinned in place across:
//
//   • Tab switches (`safeAreaInset` toggles on per-tab rootViews)
//   • Keyboard appearance (the modifier ignores `.keyboard` safe area)
//   • Scroll content underneath (overlays render above content)
//   • Per-screen overlays / sheets / loading states (zIndex pushes the bar
//     above anything inside the modified content)
//
// Position contract — encoded in code, not convention:
//   • Vertical: the FAB cluster's centerline sits 24pt above the system safe
//     area's bottom edge (home indicator clearance), regardless of which
//     screen is in front.
//   • Horizontal: 20pt total inset from each screen edge (4pt outer margin
//     + 16pt inner padding from inside `BottomNavBar`).
//   • zIndex 1000 — chosen to leave headroom under the Apple-reserved
//     ~10000 range used by alerts/status overlays. No per-screen overlay
//     reaches anywhere near 1000, so the bar is unobscurable in practice.
//
// Future screens that try to move the bar will need to either remove this
// modifier or add a higher-zIndex overlay — both are obvious red flags in
// review. That's the point.
struct LockedNavBarModifier: ViewModifier {
    @Binding var selectedTab: ContentView.Tab
    @Binding var isPlusMenuOpen: Bool
    var onAskBee: () -> Void = {}

    /// Bottom inset in points above the safe area's home-indicator zone.
    /// Centralised so changing the bar's height never desyncs with the
    /// reserved space the rest of the layout has been tuned around.
    /// Bumped from 16 → 26 to lift both the tab nav and the Ask Bee FAB
    /// a touch higher off the home-indicator so they don't crowd it.
    static let bottomInset: CGFloat = 26
    /// Horizontal screen-edge inset in points. Combined with the 16pt
    /// padding inside `BottomNavBar`, total side margin is 20pt.
    static let horizontalInset: CGFloat = 4
    /// Stacking order for the locked bar. Anything inside the modified
    /// content rendering at or above this would visually displace the bar,
    /// so this is intentionally well above any per-screen overlay zIndex.
    static let stackingOrder: Double = 1000

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                BottomNavBar(
                    selectedTab: $selectedTab,
                    isPlusMenuOpen: $isPlusMenuOpen,
                    onAskBee: onAskBee
                )
                .padding(.bottom, Self.bottomInset)
                .padding(.horizontal, Self.horizontalInset)
                .zIndex(Self.stackingOrder)
                // Keyboard avoidance is the user's job, not the nav bar's:
                // the bar must not slide up when a text field appears.
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
    }
}

// MARK: - Plus Glyph
//
// Two rounded capsules forming a "+" cross. Replaces `Image(systemName: "plus")`
// which, even at .medium weight, has a slightly chunky bowl + uneven stroke
// thickness on bold weights and never quite reads as "premium." A custom
// glyph gives us:
//   • perfect rounded line caps (Capsule does this automatically)
//   • exact stroke thickness control independent of point size
//   • dead-center symmetry — no font hinting drift
//   • crisp rendering at any scale (rotates smoothly to 45° for the close
//     state without anti-aliasing artefacts)
//
// `strokeWidth` is the thickness of each arm; `armLength` is the total
// length tip-to-tip. Both are tuned for a 60-pt FAB — bump them
// proportionally if the button size changes.
struct PlusGlyph: View {
    let armLength: CGFloat
    let strokeWidth: CGFloat
    var color: Color = .white

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: strokeWidth, height: armLength)
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: armLength, height: strokeWidth)
        }
    }
}

extension View {
    /// Locks the BeeClean nav bar at the bottom of this view, pinned by
    /// `LockedNavBarModifier` so its position is invariant across tab
    /// changes, safe-area shifts, keyboard, and per-screen overlays.
    /// Apply once at the app's top-level container — never inside a tab.
    func lockedNavBar(
        selectedTab: Binding<ContentView.Tab>,
        isPlusMenuOpen: Binding<Bool>,
        onAskBee: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            LockedNavBarModifier(
                selectedTab: selectedTab,
                isPlusMenuOpen: isPlusMenuOpen,
                onAskBee: onAskBee
            )
        )
    }
}

#Preview {
    ZStack {
        Color(hex: "FBF9F6").ignoresSafeArea()
        VStack {
            Spacer()
            BottomNavBar(selectedTab: .constant(.charging), isPlusMenuOpen: .constant(false))
                .padding(.bottom, 4)
        }
    }
    .preferredColorScheme(.light)
}
