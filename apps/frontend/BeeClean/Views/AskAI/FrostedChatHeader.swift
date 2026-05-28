import SwiftUI

// MARK: - Frosted Chat Header
//
// Chat header with three independently-floating solid-white pills
// pinned to the top of the chat surface — leading (back chevron +
// optional unread badge), center (avatar + name capsule), and trailing
// (optional icon). The pills NEVER join into a single bar; the space
// between them stays fully transparent so chat content scrolls visibly
// through the gaps as the user scrolls.
//
// USAGE
//   ZStack(alignment: .top) {
//       ScrollView { Color.clear.frame(height: headerHeight); ... }
//       FrostedChatHeader(...)
//           .ignoresSafeArea(edges: .top)
//   }
//
// IMPLEMENTATION RULES (matching the design spec)
// • Pill fill is `Color.white` — same token as the Compress storage
//   card — so Ask Bee and Compress share one visual language.
// • No divider lines or shadows on the pills.
// • Do NOT pair with `NavigationStack`'s `.toolbarBackground(...)` —
//   that prevents content from scrolling under the blur. Use this
//   component as a ZStack overlay above the ScrollView instead.

struct FrostedChatHeader<Avatar: View>: View {

    // MARK: - Inputs

    let contactName: String
    let unreadCount: Int
    let onBack: () -> Void
    let onContactTap: () -> Void
    let trailingIcon: String?
    let trailingAction: (() -> Void)?
    @ViewBuilder let avatar: () -> Avatar

    // MARK: - Layout constants

    private let avatarSize: CGFloat = 60
    private let edgePadding: CGFloat = 16
    private let topGap: CGFloat = 6      // gap between status bar and pills
    private let stackSpacing: CGFloat = 4 // avatar ↔ name capsule gap

    // MARK: - Body

    var body: some View {
        // Use a ZStack so the center column stays dead-centered regardless
        // of the leading/trailing pills' widths (the unread badge can make
        // the leading pill wider than the trailing pill). HStack with
        // Spacer-Spacer would shift the center off-axis when widths differ.
        ZStack(alignment: .top) {
            centerColumn
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 0) {
                leadingPill
                Spacer(minLength: 0)
                trailingPill
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, edgePadding)
        .padding(.top, safeAreaTop + topGap)
    }

    // MARK: - Leading pill (back + optional unread badge)

    private var leadingPill: some View {
        Button {
            // Haptic mirrors what the previous custom header did so the
            // pill swap doesn't feel "deader" than the old chrome.
            HapticManager.shared.impact(.light, intensity: 0.6)
            onBack()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    // Dark chevron via semantic primary (~black light, flipped in dark mode
                    // for contrast on the frosted capsule).
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.black, in: Capsule())
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, unreadCount > 0 ? 6 : 12)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center column (avatar + name capsule)

    private var centerColumn: some View {
        VStack(spacing: stackSpacing) {
            // The avatar isn't wrapped in a frosted pill — it's already a
            // self-contained circular image (mascot or contact photo).
            // Apple Messages does the same: contact monogram circles use
            // their own gradient, not the pill blur.
            Button {
                HapticManager.shared.filterChange()
                onContactTap()
            } label: {
                avatar()
                    .frame(width: avatarSize, height: avatarSize)
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.filterChange()
                onContactTap()
            } label: {
                HStack(spacing: 3) {
                    Text(contactName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Trailing pill (optional)

    @ViewBuilder
    private var trailingPill: some View {
        if let trailingAction, let trailingIcon {
            Button {
                HapticManager.shared.impact(.light, intensity: 0.6)
                trailingAction()
            } label: {
                Image(systemName: trailingIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 19, height: 19)
                    .padding(10)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Safe area top
    //
    // Reads from the active window's safe area. UIApplication-based
    // lookups don't work inside SwiftUI previews, so we fall back to a
    // sensible default (44pt — matches modern notched iPhones). The
    // existing AskAIView header uses the same pattern.

    private var safeAreaTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
    }

}

// MARK: - Public height helper
//
// The chat ScrollView needs a transparent leading spacer with the exact
// pixel height of this header so messages start visible below the pills
// and then scroll up under them. Exposing the computed height keeps
// that spacer in sync if the layout constants change later. Lives
// outside `FrostedChatHeader<Avatar>` so callers don't have to spell
// the generic placeholder just to read a CGFloat.

enum FrostedChatHeaderMetrics {
    /// Total visual height of the header, including the device's status
    /// bar safe area. Use as the height of the leading `Color.clear`
    /// spacer inside the chat `ScrollView`.
    static func totalHeight(safeAreaTop: CGFloat) -> CGFloat {
        // safe area + topGap (6) + avatar (60) + stackSpacing (4) +
        // name capsule (~24 = font 13 line height + vertical padding 5×2)
        safeAreaTop + 6 + 60 + 4 + 24
    }
}

// MARK: - Preview

#Preview("Light") {
    ZStack(alignment: .top) {
        // Stand-in for the chat content so we can sanity-check the
        // material in the preview. The real app uses MessageBubbleView.
        ScrollView {
            VStack(spacing: 12) {
                Color.clear.frame(height: 140)
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "FFD84D"))
                        .frame(height: 60)
                        .padding(.horizontal, 60)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "E5E5E7"))
                        .frame(height: 60)
                        .padding(.horizontal, 60)
                }
            }
        }

        FrostedChatHeader(
            contactName: "BeeBuddy",
            unreadCount: 0,
            onBack: {},
            onContactTap: {},
            trailingIcon: "line.3.horizontal",
            trailingAction: {},
            avatar: { AppIconAvatar(size: 60) }
        )
        .ignoresSafeArea(edges: .top)
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ZStack(alignment: .top) {
        ScrollView {
            VStack(spacing: 12) {
                Color.clear.frame(height: 140)
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "FFD84D"))
                        .frame(height: 60)
                        .padding(.horizontal, 60)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(hex: "3A3A3C"))
                        .frame(height: 60)
                        .padding(.horizontal, 60)
                }
            }
        }

        FrostedChatHeader(
            contactName: "Paul",
            unreadCount: 4,
            onBack: {},
            onContactTap: {},
            trailingIcon: "video.fill",
            trailingAction: {},
            avatar: {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Color(hex: "9CA8FF"), Color(hex: "C9CFFF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    Text("P")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        )
        .ignoresSafeArea(edges: .top)
    }
    .preferredColorScheme(.dark)
}
