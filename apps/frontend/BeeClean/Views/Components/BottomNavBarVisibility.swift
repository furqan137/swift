import SwiftUI

// MARK: - Bottom Nav Bar Visibility
//
// The floating tab bar (BottomNavBar) lives at the OUTER ZStack of
// ContentView so theme changes / safe-area insets / per-tab toggles
// inside the NavigationStack can never displace it. That positioning
// also means a view pushed by `.navigationDestination` cannot directly
// hide the bar — there's no parent boundary to attach a `.toolbar` /
// `.tabBar` modifier to.
//
// Any pushed view that wants the bar hidden (Duplicate Photos, Similar
// Photos, Contact List, etc.) calls `.hidesBottomNavBar()` on its body.
// The modifier flips this `@Published` flag on appear and clears it on
// disappear; ContentView observes it and gates the bar's render.

@MainActor
final class BottomNavBarVisibility: ObservableObject {
    static let shared = BottomNavBarVisibility()

    /// Number of pushed views currently requesting hide. Counter (not
    /// Bool) so a stack like Tab → DuplicatePhotosView → DetailSheet
    /// can keep the bar hidden across nested levels and only restore
    /// when ALL of them disappear.
    @Published private(set) var hideRequests: Int = 0

    /// Hard override — when true, the bar is hidden regardless of the
    /// `hideRequests` counter. Wired to Quick Access pushes so the
    /// nav bar can never reappear over a category screen, even if a
    /// race in the modifier lifecycle would otherwise let the counter
    /// drop to zero. ChargingView flips this on push, off on pop.
    @Published private(set) var forceHidden: Bool = false

    /// Bar hides whenever any pushed view has requested it, OR the
    /// hard override is on. The hard override exists because the
    /// counter-based path is subject to SwiftUI lifecycle races (a
    /// `.task` cancellation can release the hide BEFORE the next
    /// pushed view's `.task` requests it); the flag short-circuits
    /// the whole counter for the Quick Access flow.
    var isHidden: Bool { forceHidden || hideRequests > 0 }

    private init() {}

    func requestHide() { hideRequests += 1 }
    func releaseHide() { hideRequests = max(0, hideRequests - 1) }

    /// Hard-hide override — set true to hide the bar unconditionally
    /// until cleared. Use sparingly; the counter is the normal path.
    func setForceHidden(_ value: Bool) {
        if forceHidden != value { forceHidden = value }
    }

    /// Force-clear all hide requests. Wire this to tab changes so a
    /// dangling counter from a half-released modifier can't keep the
    /// bar hidden across screens. Also clears the hard override so a
    /// stale `setForceHidden(true)` doesn't leak across tabs.
    func forceClear() {
        hideRequests = 0
        forceHidden = false
    }
}

extension View {
    /// Hides the floating BottomNavBar for as long as the receiver is
    /// on screen. Use on detail views pushed from the tab roots so the
    /// nav bar doesn't sit on top of category content (Duplicate Photos,
    /// Email category list, Compress detail, etc.).
    func hidesBottomNavBar() -> some View {
        modifier(HidesBottomNavBarModifier())
    }
}

private struct HidesBottomNavBarModifier: ViewModifier {
    // Track whether THIS view instance is currently holding a hide
    // request, so we never double-release if SwiftUI fires both the
    // .task cancellation AND .onDisappear for the same disappearance.
    @State private var didRequest = false

    func body(content: Content) -> some View {
        content
            // `.task` cancellation fires at the *start* of the disappear
            // transition (before the pop animation completes). Belt: we
            // release here so the bar pops back in WITH the transition.
            .task {
                guard !didRequest else { return }
                didRequest = true
                BottomNavBarVisibility.shared.requestHide()
                defer {
                    if didRequest {
                        BottomNavBarVisibility.shared.releaseHide()
                        didRequest = false
                    }
                }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            // Suspenders: if for any reason .task's defer didn't fire
            // (SwiftUI sometimes drops async cancellation across full-
            // screen-cover dismissals), .onDisappear catches it after
            // the animation completes. Idempotent — we only release if
            // this view still holds a request.
            .onDisappear {
                if didRequest {
                    BottomNavBarVisibility.shared.releaseHide()
                    didRequest = false
                }
            }
    }
}
