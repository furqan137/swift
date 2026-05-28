import SwiftUI

// MARK: - Swipe Card Action Rail
//
// Vertical column of three glass icons (heart / bookmark / share) that
// sits on the right edge of the Quick Cleanup swipe deck. Each button
// is a self-contained toggle / action:
//
//   • Heart    → toggles `SavedFindKind.hearted` on the active asset.
//   • Bookmark → toggles `SavedFindKind.bookmarked` on the active asset.
//   • Share    → opens MediaShareSheet for the active asset.
//
// Independent from swipe-left (delete) / swipe-right (keep). The rail
// is purely additive — tapping it never advances the deck or removes
// the card.
struct SwipeCardActionRail: View {
    let assetId: String
    let context: SavedFindContext
    var onShareRequested: () -> Void

    @ObservedObject private var store = SavedFindsStore.shared

    private var isHearted: Bool {
        store.isSaved(assetLocalIdentifier: assetId, kind: .hearted)
    }

    private var isBookmarked: Bool {
        store.isSaved(assetLocalIdentifier: assetId, kind: .bookmarked)
    }

    var body: some View {
        // TikTok-style column: three identical-footprint glyphs in a
        // tight vertical stack. Every button is the same 48pt circle
        // with the same scrim, so the column reads as one cohesive
        // control instead of three loose icons.
        VStack(spacing: 16) {
            iconButton(
                systemName: isHearted ? "heart.fill" : "heart",
                tint: isHearted ? Color(hex: "FF3B5C") : .white,
                action: toggleHeart
            )
            iconButton(
                systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                tint: isBookmarked ? Color(hex: "FFC648") : .white,
                action: toggleBookmark
            )
            iconButton(
                systemName: "arrowshape.turn.up.right.fill",
                tint: .white,
                action: {
                    HapticManager.shared.impact(.light)
                    onShareRequested()
                }
            )
        }
    }

    private func iconButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(Color.black.opacity(0.32))
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
        }
        .buttonStyle(RailPressStyle())
    }

    // MARK: - Toggles

    private func toggleHeart() {
        if isHearted {
            HapticManager.shared.selection()
            store.removeFind(assetLocalIdentifier: assetId, kind: .hearted)
        } else {
            HapticManager.shared.tapSensation()
            store.saveFind(
                assetLocalIdentifier: assetId,
                mediaType: context.mediaType,
                sourceCategory: context.sourceCategory,
                sourceApp: context.sourceApp,
                kind: .hearted
            )
        }
    }

    private func toggleBookmark() {
        if isBookmarked {
            HapticManager.shared.selection()
            store.removeFind(assetLocalIdentifier: assetId, kind: .bookmarked)
        } else {
            HapticManager.shared.tapSensation()
            store.saveFind(
                assetLocalIdentifier: assetId,
                mediaType: context.mediaType,
                sourceCategory: context.sourceCategory,
                sourceApp: context.sourceApp,
                kind: .bookmarked
            )
        }
    }
}

private struct RailPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
