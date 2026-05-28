import SwiftUI

// MARK: - Card Surface
struct CardSurface<Content: View>: View {
    let style: CardStyle
    @ViewBuilder let content: () -> Content

    enum CardStyle {
        case standard
        case elevated
        case glass
        case interactive
        case honeycomb
    }

    var body: some View {
        content()
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.border.opacity(borderOpacity), lineWidth: 0.5)
            )
            .overlay(topEdgeHighlight)
            .shadow(color: shadowColor.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: Color.black.opacity(contactShadowOpacity), radius: 2, x: 0, y: 1)
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .standard: return DesignTokens.Radius.lg
        case .elevated: return DesignTokens.Radius.xl
        case .glass, .interactive: return DesignTokens.Radius.xl
        case .honeycomb: return DesignTokens.Radius.lg
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .standard:
            ZStack {
                Color.card
                LinearGradient.cardSheen
            }
        case .elevated:
            ZStack {
                Color.card
                LinearGradient.cardSheen
                Color.primaryColor.opacity(0.015)
            }
        case .glass:
            ZStack {
                Color.card.opacity(0.75)
                    .background(.ultraThinMaterial)
                LinearGradient.glassGradient
            }
        case .interactive:
            ZStack {
                Color.card
                LinearGradient.cardSheen
            }
        case .honeycomb:
            ZStack {
                Color.card
                LinearGradient.cardSheen
            }
        }
    }

    private var borderOpacity: Double {
        switch style {
        case .standard: return 0.4
        case .elevated: return 0.3
        case .glass: return 0.5
        case .interactive: return 0.4
        case .honeycomb: return 0.3
        }
    }

    @ViewBuilder
    private var topEdgeHighlight: some View {
        switch style {
        case .elevated, .glass:
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        default:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        switch style {
        case .honeycomb: return .primaryColor
        default: return .black
        }
    }

    private var shadowOpacity: Double {
        switch style {
        case .standard: return 0.08
        case .elevated: return 0.10
        case .glass: return 0.08
        case .interactive: return 0.08
        case .honeycomb: return 0.08
        }
    }

    private var contactShadowOpacity: Double {
        switch style {
        case .standard: return 0.04
        case .elevated: return 0.05
        case .glass: return 0.04
        case .interactive: return 0.04
        case .honeycomb: return 0.04
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .standard: return 14
        case .elevated: return 22
        case .glass: return 16
        case .interactive: return 14
        case .honeycomb: return 10
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .standard: return 5
        case .elevated: return 8
        case .glass: return 6
        case .interactive: return 5
        case .honeycomb: return 4
        }
    }
}

// MARK: - Card Surface Modifier
extension View {
    func cardSurface(_ style: CardSurface<AnyView>.CardStyle = .standard) -> some View {
        CardSurface(style: style) {
            AnyView(self)
        }
    }
}

// MARK: - Action Bar
//
// Bitepal-style sticky CTA. Used at the bottom of every selection
// surface: MediaGridView (Other Photos / Blurry / Screenshots), the
// per-group detail pages (Similar Photos, Duplicates, Similar Videos /
// Screenshots), and the Cleanup category-detail review screen. One
// shared component → one consistent footer treatment.
//
// Visual design (destructive variant — the dominant case):
//   • Floating capsule (not a flat rounded rectangle). The pill silhouette
//     reads as a deliberate floating CTA on top of the content scroll
//     instead of a hard-edged toolbar.
//   • Espresso-deep crimson gradient (top-left → bottom-right) — same
//     ink-toned palette Bitepal uses for its primary destructive
//     surfaces. Saturation is intentionally one notch below the system
//     red so the bar doesn't read as an alert / iOS error banner.
//   • Hairline top rim-light + bottom inner-shadow on the capsule for
//     the subtle "lit hardware" look the rest of the app uses.
//   • Trash glyph lives in its own soft circular chip on the leading
//     edge so the icon has visual presence without bloating the title
//     line. Selection-count chip on the trailing edge surfaces the
//     "(162.9 MB)" parenthetical from the title — separating it into
//     a chip turns the bar into a tri-column composition (icon |
//     primary text | numeric chip) that scans like a banking summary
//     row rather than a single oversized label.
//
// Title parsing: the call sites already pass a single combined string
// like "Delete 183 photos (162.9 MB)". To get the count chip without
// changing every call site, we split the trailing parenthetical out at
// render time. If no parenthetical is present (older / non-MB titles),
// the chip is hidden and the title flows full-width — both usages
// already in the codebase produce the parenthetical, so the chip
// surfaces in every real call site.
struct ActionBar: View {
    let title: String
    let buttonTitle: String
    let buttonIcon: String
    let isDestructive: Bool
    let action: () -> Void

    private var primaryText: String {
        // Strip a trailing "(…)" so it can render as a separate chip.
        guard let openIdx = title.lastIndex(of: "("),
              title.last == ")"
        else { return title }
        return title[..<openIdx].trimmingCharacters(in: .whitespaces)
    }

    private var trailingChipText: String? {
        guard let openIdx = title.lastIndex(of: "("),
              title.last == ")"
        else { return nil }
        let inner = title[title.index(after: openIdx)..<title.index(before: title.endIndex)]
        return String(inner)
    }

    private var capsuleFill: LinearGradient {
        if isDestructive {
            // Espresso-deep crimson — top-left bright, bottom-right
            // sinks toward an ink-tinted maroon. Reads as premium
            // destructive (think Bitepal's "Delete day log" CTA), not
            // iOS-alert red.
            return LinearGradient(
                colors: [
                    Color(hex: "C13A3A"),
                    Color(hex: "8E1F1F")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient.honeyGradient
        }
    }

    private var glowColor: Color {
        isDestructive ? Color(hex: "8E1F1F") : Color.primaryColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Leading icon chip — inset white-on-translucent circle
                // so the trash glyph is the focal point of the leading
                // edge without competing with the title text weight.
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: buttonIcon)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                }

                Text(primaryText)
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                if let chip = trailingChipText {
                    Text(chip)
                        .font(.custom("Poppins-Bold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.22))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(capsuleFill)

                    // Top rim-light — same lighting model as the
                    // BottomNavBar / merge-preview cards so the bar
                    // reads as the same family of "lit hardware".
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.plusLighter)

                    // Bottom edge ink — gentle inner shadow at the
                    // lower half so the capsule has weight.
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.22)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )

                    // Hairline silhouette so the bar stays crisp on
                    // bright backgrounds.
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                }
            )
            // Stacked shadows: a tight contact shadow + a wider ambient
            // glow tinted by the bar's own color. Mirrors the nav-bar
            // shadow signature.
            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
            .shadow(color: glowColor.opacity(0.32), radius: 18, y: 10)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Checkbox
struct Checkbox: View {
    @Binding var isChecked: Bool
    let size: CGFloat

    init(isChecked: Binding<Bool>, size: CGFloat = 22) {
        self._isChecked = isChecked
        self.size = size
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isChecked.toggle()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .stroke(isChecked ? Color.primaryColor : Color.border, lineWidth: 1.5)
                    .frame(width: size, height: size)

                if isChecked {
                    RoundedRectangle(cornerRadius: size * 0.25)
                        .fill(LinearGradient.honeyGradient)
                        .frame(width: size, height: size)

                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        CardSurface(style: .standard) {
            Text("Standard Card")
                .foregroundColor(.foreground)
                .padding()
        }

        CardSurface(style: .elevated) {
            Text("Elevated Card")
                .foregroundColor(.foreground)
                .padding()
        }

        CardSurface(style: .honeycomb) {
            Text("Honeycomb Card")
                .foregroundColor(.foreground)
                .padding()
        }

        HStack(spacing: 16) {
            Checkbox(isChecked: .constant(false))
            Checkbox(isChecked: .constant(true))
        }
    }
    .padding()
    .background(Color.background)
}
