import SwiftUI

// MARK: - Swipe To Dismiss
/// Adds a left-edge swipe-right-to-dismiss gesture that matches iOS's native
/// interactive pop behavior. Needed on screens that hide the nav bar (which
/// disables UIKit's interactivePopGestureRecognizer) and on `.sheet` /
/// `.fullScreenCover` presentations where the system gesture isn't provided.
/// Uses `simultaneousGesture` so inner ScrollViews and buttons still receive
/// their own touches — only drags starting within the leftmost `edgeWidth`
/// points are claimed.
struct SwipeToDismissModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    /// Max distance from the left edge where a drag may start (pt).
    var edgeWidth: CGFloat = 30
    /// Minimum rightward distance to commit the dismiss (pt).
    var commitDistance: CGFloat = 100
    /// Predicted-end translation for flick-to-dismiss (pt).
    var flickDistance: CGFloat = 250

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard value.startLocation.x < edgeWidth else { return }
                        let translation = max(0, value.translation.width)
                        // Soft resistance past 300pt so the feel stays bounded.
                        dragOffset = translation < 300
                            ? translation
                            : 300 + (translation - 300) * 0.35
                    }
                    .onEnded { value in
                        let fromEdge = value.startLocation.x < edgeWidth
                        let crossedDistance = value.translation.width > commitDistance
                        let flicked = value.predictedEndTranslation.width > flickDistance

                        if fromEdge && (crossedDistance || flicked) {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
    }
}

extension View {
    /// Adds left-edge swipe-right-to-dismiss. Pair with a hidden navigation bar
    /// or a sheet / fullScreenCover where the system gesture isn't available.
    func swipeToDismiss() -> some View {
        modifier(SwipeToDismissModifier())
    }

    /// Variant for screens that dismiss through a caller-supplied closure
    /// (e.g. `onDismiss: () -> Void`) rather than the `\.dismiss` environment.
    func swipeToDismissUsing(_ action: @escaping () -> Void) -> some View {
        modifier(SwipeToDismissActionModifier(action: action))
    }
}

/// Same left-edge swipe behavior as `SwipeToDismissModifier` but fires a
/// caller-provided closure instead of `@Environment(\.dismiss)` — needed for
/// sheets that bind their presentation to an external callback.
struct SwipeToDismissActionModifier: ViewModifier {
    let action: () -> Void
    @State private var dragOffset: CGFloat = 0

    var edgeWidth: CGFloat = 30
    var commitDistance: CGFloat = 100
    var flickDistance: CGFloat = 250

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard value.startLocation.x < edgeWidth else { return }
                        let translation = max(0, value.translation.width)
                        dragOffset = translation < 300
                            ? translation
                            : 300 + (translation - 300) * 0.35
                    }
                    .onEnded { value in
                        let fromEdge = value.startLocation.x < edgeWidth
                        let crossedDistance = value.translation.width > commitDistance
                        let flicked = value.predictedEndTranslation.width > flickDistance

                        if fromEdge && (crossedDistance || flicked) {
                            action()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
    }
}

/// Applies `SwipeToDismissModifier` only when `enabled` is true so the gesture
/// can be bound to a state (e.g. AppLayout only attaches it when a back button
/// is present).
struct ConditionalSwipeToDismiss: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.modifier(SwipeToDismissModifier())
        } else {
            content
        }
    }
}

