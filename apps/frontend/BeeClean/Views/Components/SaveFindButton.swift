import SwiftUI
import Photos

// MARK: - SaveFindButton
//
// Cal AI–grade Save / Saved pill, overlaid on top of media review surfaces
// (MediaSwipeView, ZoomablePreviewOverlay). Independent from any swipe /
// keep / delete gesture in the host — tapping Save adds the asset to
// Saved Finds and leaves the rest of the review flow untouched.
//
// Renders only when `context` is non-nil; surfaces shared with banned
// flows (Guided Cleanup, Compress) pass nil and no button appears.
//
// Tactile model:
//  - tapSensation() haptic (sharp click + warm echo) on save.
//  - selection() haptic on re-tap of an already-saved asset.
//  - Spring scale-on-press (1.0 → 0.94 → 1.0) ties the haptic to a
//    visible pulse so the press visibly "lands". Same Cal-AI rhythm
//    the nav bar / FAB use elsewhere in the app.
//  - Symbol bounce on the bookmark glyph when state crosses unsaved→saved.

struct SaveFindButton: View {
    let assetId: String
    let context: SavedFindContext
    var onSaved: (() -> Void)? = nil
    var onAlreadySaved: (() -> Void)? = nil
    /// Optional unsave path. When provided AND the item is already saved,
    /// tapping the button removes the asset from Saved Finds instead of
    /// firing `onAlreadySaved`. Only the Saved Finds grid preview wires
    /// this — every other surface leaves it nil and keeps the "already
    /// saved" toast behavior.
    var onUnsave: (() -> Void)? = nil
    var style: Style = .light

    enum Style { case light, dark }

    @ObservedObject private var store = SavedFindsStore.shared
    @State private var bounceTrigger: Int = 0

    private var isSaved: Bool {
        store.isSaved(assetLocalIdentifier: assetId)
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12.5, weight: .bold))
                    .symbolEffect(.bounce, value: bounceTrigger)

                Text(isSaved ? "Saved" : "Save")
                    .font(.custom("Poppins-Bold", size: 12.5))
                    .tracking(0.15)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(backgroundFill)
            .overlay(specularRim)
            .overlay(borderStroke)
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule())
        }
        // Press feedback lives in a ButtonStyle now. The previous
        // `.simultaneousGesture(DragGesture(minimumDistance: 0))` pattern
        // competed with the Button's own tap recognizer inside
        // gesture-heavy parents (the swipe deck in MediaSwipeView,
        // pinch/pan in ZoomablePreviewOverlay) and dropped taps silently.
        // `configuration.isPressed` is wired straight to the Button's
        // own tap, so there's nothing to compete with.
        .buttonStyle(SaveFindPressStyle(restingShadow: shadowColor))
        .animation(.easeOut(duration: 0.22), value: isSaved)
        .accessibilityLabel(isSaved ? "Saved to Finds" : "Save to Finds")
    }

    // MARK: - Layered fill (glass / honey)

    @ViewBuilder
    private var backgroundFill: some View {
        if isSaved {
            // Honey gradient with a tiny inset highlight up top — gives
            // the "filled" state a physical pressed-glass surface.
            ZStack {
                LinearGradient(
                    colors: [
                        Color.categoryHoney,
                        Color.categoryHoney.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.28),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .blendMode(.plusLighter)
            }
        } else {
            switch style {
            case .light:
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .dark:
                ZStack {
                    Color.black.opacity(0.42)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .blendMode(.plusLighter)
                }
            }
        }
    }

    // Thin specular line near the top edge — same lit-from-above
    // treatment Quick Access tiles and YourSpaceRow use.
    private var specularRim: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(specularOpacity),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.7
            )
            .blendMode(.plusLighter)
    }

    private var borderStroke: some View {
        Capsule(style: .continuous)
            .stroke(borderColor, lineWidth: 0.7)
    }

    // MARK: - Style maps

    private var foreground: Color {
        if isSaved { return .white }
        switch style {
        case .light: return Color(hex: "1C1917")
        case .dark:  return .white
        }
    }

    private var borderColor: Color {
        if isSaved { return Color.white.opacity(0.30) }
        switch style {
        case .light: return Color.black.opacity(0.10)
        case .dark:  return Color.white.opacity(0.22)
        }
    }

    private var specularOpacity: Double {
        if isSaved { return 0.45 }
        switch style {
        case .light: return 0.85
        case .dark:  return 0.18
        }
    }

    private var shadowColor: Color {
        // Cal-AI saved-state: quiet black drop shadow, no honey halo.
        // The pill's honey FILL carries the "saved" signal — adding a
        // colored glow underneath made it read like a notification
        // badge rather than a tactile control. A flat 12% shadow keeps
        // it grounded without the chroma noise.
        if isSaved {
            return style == .dark
                ? Color.black.opacity(0.28)
                : Color.black.opacity(0.12)
        }
        switch style {
        case .light: return Color.black.opacity(0.08)
        case .dark:  return Color.black.opacity(0.32)
        }
    }

    // MARK: - Tap

    private func handleTap() {
        if isSaved {
            if let onUnsave {
                // Saved Finds grid preview path — tapping the "Saved"
                // pill in the preview header removes the item rather
                // than just toasting "already saved". The warn-haptic
                // matches the rest of the app's destructive confirm
                // moments (delete alerts, etc.).
                HapticManager.shared.destructiveConfirm()
                onUnsave()
            } else {
                HapticManager.shared.selection()
                onAlreadySaved?()
            }
            return
        }
        let didSave = store.saveFind(
            assetLocalIdentifier: assetId,
            mediaType: context.mediaType,
            sourceCategory: context.sourceCategory,
            sourceApp: context.sourceApp
        )
        if didSave {
            HapticManager.shared.tapSensation()
            bounceTrigger &+= 1
            onSaved?()
        } else {
            HapticManager.shared.selection()
            onAlreadySaved?()
        }
    }
}

// MARK: - SaveFindPressStyle
//
// Press feedback as a `ButtonStyle` rather than a parallel
// `DragGesture(minimumDistance: 0)`. The drag-gesture approach reads
// nicely on a plain canvas but fails inside SwiftUI parents that
// already own drag/pinch gestures (MediaSwipeView's swipe deck,
// ZoomablePreviewOverlay's pinch-to-zoom) — the inner gesture claims
// the touch first and the Button's tap recognizer never fires. Reading
// `configuration.isPressed` from the style ties the press visual
// directly to the Button's own tap, so taps always land.
private struct SaveFindPressStyle: ButtonStyle {
    let restingShadow: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .shadow(
                color: restingShadow,
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .animation(
                .interactiveSpring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

// MARK: - BeeToast
//
// Tiny floating capsule used by the Save flow. Lives in the host view's
// coordinate space so it anchors above the swipe deck / preview content.
// Auto-dismisses after ~1.8s. Glass material gives it the same lit
// surface treatment the rest of the BeeClean chrome uses.

struct BeeToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let icon: String
}

struct BeeToastView: View {
    let toast: BeeToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .symbolRenderingMode(.hierarchical)

            Text(toast.message)
                .font(.custom("Poppins-Bold", size: 13))
                .tracking(0.15)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            }
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
        .compositingGroup()
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -6)),
                removal: .opacity.combined(with: .offset(y: -4))
            )
        )
    }
}

// MARK: - Toast presenter modifier

private struct BeeToastModifier: ViewModifier {
    @Binding var toast: BeeToast?
    var topInset: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    BeeToastView(toast: toast)
                        .padding(.top, topInset)
                        .id(toast.id)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: toast?.id)
            .onChange(of: toast?.id) { _, newId in
                guard let newId else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    if toast?.id == newId {
                        toast = nil
                    }
                }
            }
    }
}

extension View {
    func beeToast(_ toast: Binding<BeeToast?>, topInset: CGFloat = 70) -> some View {
        modifier(BeeToastModifier(toast: toast, topInset: topInset))
    }
}
