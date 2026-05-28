import SwiftUI

// MARK: - Scroll Offset Preference Key
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Collapsing Header Layout
struct CollapsingHeaderLayout<Content: View>: View {
    let title: String
    let subtitle: String?
    let trailingContent: AnyView?
    /// Trailing pill that lives inside the large-title row (right of
    /// the big title text), independent of the compact-bar trailing.
    /// Used for the "Newest" sort filter pill on similar/duplicate
    /// review screens — it fades out alongside the large title as the
    /// user scrolls so the compact bar stays uncluttered at the top.
    let largeTitleTrailing: AnyView?
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0

    private let compactBarHeight: CGFloat = 36
    private let largeTitleHeight: CGFloat = 80
    private let collapseDistance: CGFloat = 60

    private var titleProgress: CGFloat {
        let raw = -scrollOffset / collapseDistance
        return min(max(raw, 0), 1)
    }

    private var subtitleProgress: CGFloat {
        let raw = -scrollOffset / (collapseDistance * 0.45)
        return min(max(raw, 0), 1)
    }

    private var heightProgress: CGFloat {
        let eased = titleProgress * titleProgress * (3 - 2 * titleProgress)
        return eased
    }

    private var currentLargeTitleHeight: CGFloat {
        largeTitleHeight * (1 - heightProgress)
    }

    private var totalHeaderHeight: CGFloat {
        compactBarHeight + currentLargeTitleHeight
    }

    init(
        title: String,
        subtitle: String? = nil,
        trailingContent: AnyView? = nil,
        largeTitleTrailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingContent = trailingContent
        self.largeTitleTrailing = largeTitleTrailing
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Shared BitePal canvas — cool blue-lavender → warm
            // light-gray gradient used by every secondary surface
            // (Email, Settings, Compress, Progress, More, Photos,
            // Videos, media review/preview). One unified ground
            // across every screen the user can navigate into.
            bitepalCanvasGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("collapsingScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    Color.clear
                        .frame(height: compactBarHeight + largeTitleHeight)

                    content()
                }
            }
            .coordinateSpace(name: "collapsingScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                // Two-stage filter so a smooth scroll (60Hz preference
                // updates) doesn't invalidate the entire header overlay
                // 60 times per second:
                //   1. Clamp to the visually meaningful range — past
                //      -collapseDistance the title is fully collapsed,
                //      past 0 the header sits at rest. Further updates
                //      outside that window never change pixel output.
                //   2. Quantize to 0.5pt — sub-pixel jitter from
                //      SwiftUI's GeometryReader doesn't change layout
                //      either, so we shed those state writes.
                let clamped = max(-collapseDistance - 1, min(0, value))
                let quantized = (clamped * 2).rounded() / 2
                if quantized != scrollOffset {
                    scrollOffset = quantized
                }
            }

            headerOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header Overlay
    private var headerOverlay: some View {
        VStack(spacing: 0) {
            compactBar
            largeTitleArea
            separator
        }
        .background(
            // Pinned header surface mirrors the body gradient so the
            // transition between scrolled content and the pinned
            // header reads as one continuous canvas.
            bitepalCanvasGradient.ignoresSafeArea()
        )
    }

    /// Shared blue-lavender canvas used by every secondary surface
    /// in the app. Now a TIGHT two-stop gradient that holds the
    /// lavender tone the whole way down — the previous third stop
    /// (`#EDEEEF`) faded the bottom of tall scrollable screens
    /// (Duplicate Photos, Similar Videos) to near-white, which read
    /// as a different surface from the email screen the user wanted
    /// to match.
    private var bitepalCanvasGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Compact Bar
    private var compactBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
            }

            Spacer(minLength: 0)

            // Collapsed-title gating. At rest (titleProgress == 0) the
            // large title up top is the canonical title — this small
            // duplicate is invisible. Previously the `.opacity(0)` Text
            // still claimed its full intrinsic width in the layout,
            // squeezing the trailing pills against the screen edge and
            // truncating "Deselect All" to "Sel..." on titles like
            // "Similar Screenshots." Skipping the Text entirely when
            // titleProgress is 0 frees that space; the Text fades in
            // (and its width starts contributing) only once the user
            // has actually scrolled past the threshold.
            if titleProgress > 0.05 {
                Text(title)
                    .font(.custom("Poppins-Bold", size: 17))
                    .foregroundColor(Color(hex: "1C1917"))
                    .opacity(titleProgress)
                    .scaleEffect(0.92 + 0.08 * titleProgress)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }

            if let trailing = trailingContent {
                trailing
                    .layoutPriority(1)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: compactBarHeight)
    }

    // MARK: - Large Title Area
    private var largeTitleArea: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(Color(hex: "1C1917"))
                    .opacity(1 - titleProgress)
                    .offset(y: -8 * heightProgress)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .opacity(1 - subtitleProgress)
                        .offset(y: -4 * subtitleProgress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Large-title-trailing pill (e.g. "Newest" sort filter).
            // Rides the same opacity ramp as the title so it fades
            // cleanly into the compact bar instead of jumping out of
            // view all at once on scroll.
            if let largeTrailing = largeTitleTrailing {
                largeTrailing
                    .opacity(1 - titleProgress)
                    .offset(y: -8 * heightProgress)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: currentLargeTitleHeight)
        .clipped()
    }

    // MARK: - Separator
    private var separator: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08 * titleProgress))
            .frame(height: 0.5)
    }
}
