import SwiftUI

// MARK: - Segmented Control
//
// Sibling of the bottom nav bar — same gradient ground (`F1F1F3 → E8E8EB`),
// same lighting model (top rim-light, bottom bevel, outer hairline, stacked
// shadows), white active pill matching the active-tab indicator. Picking a
// shared visual language across surfaces is the difference between "looks
// designed" and "looks slapped together."
struct SegmentedControl: View {
    let options: [String]
    /// Optional SF Symbol per option. Pass nil for a text-only segment.
    /// Index-aligned with `options`.
    var icons: [String?] = []
    @Binding var selected: String
    @Namespace private var animation

    var body: some View {
        // No outer padding — buttons fill the container edge-to-edge so
        // the active pill goes flush with the container's outer rounded
        // corners. Same pattern the bottom nav bar uses for its active-
        // tab indicator: indicator and ground are both `Capsule()` at
        // the same height, so the rounded ends align mathematically and
        // there's no clip-out artefact at the corners.
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                SegmentButton(
                    title: option,
                    icon: index < icons.count ? icons[index] : nil,
                    isSelected: selected == option,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        selected = option
                    }
                }
            }
        }
        .frame(height: 56)
        .background(pillBackground)
    }

    // Ground — mirrors `BottomNavBar.stripBackground`.
    private var pillBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(hex: "F1F1F3"), Color(hex: "E8E8EB")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Top rim-light — single most effective cue that this is a
            // lit physical surface, not a flat sticker.
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
                    .blendMode(.plusLighter)
            )
            // Bottom bevel — faint dark stroke only along the bottom half.
            // Pairs with the rim-light to suggest a curved 3D edge.
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.06)],
                            startPoint: .center,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            )
            // Outer hairline — keeps the silhouette crisp.
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
    }
}

// MARK: - Segment Button
struct SegmentButton: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    /// Cached `Font` — `Font.custom(...)` was being called per-render on
    /// every selection change (parent runs `withAnimation(.spring...)`),
    /// which churns the custom-font registry. Loading once at type init
    /// avoids the repeated lookup.
    private static let titleFont = Font.custom("Poppins-Bold", size: 16)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(Self.titleFont)
            }
            // `#1C1917` espresso ink on the active white pill / `#4F4F54`
            // graphite on the gray ground — same pair the nav bar uses
            // for activeText / mutedText.
            .foregroundColor(isSelected ? Color(hex: "1C1917") : Color(hex: "4F4F54"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(activePill)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // Active indicator — mirrors `BottomNavBar.indicator`.
    @ViewBuilder
    private var activePill: some View {
        if isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(hex: "FAFAFB")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.plusLighter)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                )
                .matchedGeometryEffect(id: "segment", in: namespace)
                .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 3)
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SegmentedControl(
            options: ["Duplicates", "Incomplete"],
            selected: .constant("Duplicates")
        )

        SegmentedControl(
            options: ["Photos", "Videos"],
            icons: ["photo", "video.fill"],
            selected: .constant("Photos")
        )
    }
    .padding()
    .background(Color.background)
}
