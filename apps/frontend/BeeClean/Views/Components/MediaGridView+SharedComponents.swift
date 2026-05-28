import SwiftUI


// MARK: - Category Empty State
//
// Shared empty/error state used by every photo-category screen
// (Duplicates, Similar Photos, Similar Screenshots, Similar Videos,
// plus the MediaGridView-backed All Screenshots / Blurry / Other /
// Recordings screens). One visual treatment everywhere:
//
//   • A blurred accent-color halo behind a single SF Symbol icon
//   • A bold title
//   • A muted subtitle
//   • No retry button — empty states stay passive, the user navigates
//     back or pulls to refresh if they want to rescan
//
// Per-screen branding lives in the `iconName` + `accentColor` arguments
// so each category retains its own identity while sharing the layout.
// Lives inside MediaGridView.swift so the four Similar/Duplicate views
// can use it without a separate pbxproj entry; the type is `internal`
// (default) so it's visible across the module.
// MARK: - BitePal Select Pill
//
// Shared label component for every Select / Deselect / Select All button
// in the app. One look across the entire surface area:
//   • Resting:  hairline-outlined white capsule, espresso text
//   • Active:   solid espresso capsule, white text, soft shadow
// Drop in via `BitePalSelectPillLabel(text:isActive:)` inside any Button
// label closure. Replaces the per-screen ad-hoc pill stylings that
// looked "vibe-coded" — every screen now shares one polished surface.
struct BitePalSelectPillLabel: View {
    let text: String
    let isActive: Bool
    /// Optional SF Symbol shown to the LEFT of the text. The active /
    /// resting glyph is chosen via `activeIcon` / `restingIcon` — pass
    /// nil to either to omit. Caller patterns:
    ///   • Just text:                      `BitePalSelectPillLabel(text:isActive:)`
    ///   • Toggle with checkmark switch:   `restingIcon: "checkmark.circle", activeIcon: "checkmark.circle.fill"`
    var restingIcon: String? = nil
    var activeIcon: String? = nil
    var minWidth: CGFloat = 0

    var body: some View {
        let icon = isActive ? activeIcon : restingIcon
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(text)
                .font(.custom("Poppins-SemiBold", size: 13))
        }
        .foregroundColor(isActive ? .white : Color(hex: "1C1917"))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minWidth: minWidth)
        .background(
            Capsule()
                .fill(isActive ? Color(hex: "1C1917") : Color.white)
        )
        .overlay(
            Capsule()
                .stroke(
                    isActive ? Color.clear : Color.black.opacity(0.10),
                    lineWidth: 0.8
                )
        )
        .shadow(
            color: Color.black.opacity(isActive ? 0.18 : 0.04),
            radius: isActive ? 4 : 2,
            y: isActive ? 2 : 1
        )
        .animation(.easeOut(duration: 0.18), value: isActive)
    }
}

struct CategoryEmptyState: View {
    let iconName: String
    let accentColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Image(systemName: iconName)
                    .font(.system(size: 44))
                    .foregroundColor(accentColor)
            }

            Text(title)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.foreground)

            Text(subtitle)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

