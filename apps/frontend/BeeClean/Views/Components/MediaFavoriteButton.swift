import SwiftUI

// MARK: - MediaFavoriteButton
//
// Compact heart-glyph micro-button overlaid on media tiles (Compress
// grid, MediaGridView cells, Similar/Duplicate group thumbnails). One
// tap saves the asset to Saved Finds; tap again removes it.
//
// Why a dedicated component instead of reusing SaveFindButton:
//   • SaveFindButton is a labeled pill ("Save" / "Saved") — fine on a
//     full-canvas review surface (MediaSwipeView, ZoomablePreviewOverlay)
//     but visually too loud on a 110-160pt tile. The pill competes with
//     the savings / size pill the tiles already render at bottom-leading.
//   • Tiles need a glyph-only control that reads as decoration until
//     activated. Heart is the universal "favorite" affordance and pairs
//     naturally with the bookmark pill on review surfaces — they're not
//     in the same view at the same time.
//
// Tactile contract — matches GuidedFavoriteButton so the user only has
// one heart sensation to learn across every "favorite into Saved Finds"
// surface:
//   • Save  → `tapSensation()` (sharp click + warm echo) + symbol bounce
//             + foreground morphs to brand-crimson `#FF4D6A`
//   • Unsave → `selection()` tick + foreground returns to white
//
// Placement contract:
//   • Sits at top-leading by default — the only consistently empty
//     corner across every tile type the app has (top-trailing carries
//     SocialSourceBadge + iCloud chip + duration; bottom-leading carries
//     size / savings pill; bottom-trailing carries selection chip / best
//     badge).
//   • Hit region is tight around the 28pt circle so swipe/long-press
//     gestures on the parent tile aren't disrupted.
struct MediaFavoriteButton: View {
    let assetId: String
    let mediaType: SavedFindMediaType
    let sourceCategory: SavedFindSourceCategory
    /// Optional source-app override — Compress + group cells already
    /// resolve provenance via the lazy classifier; passing it here means
    /// the saved entry carries the brand badge into Saved Finds without
    /// a second classify pass.
    var sourceApp: PhotoSource? = nil
    var size: CGFloat = 28

    @ObservedObject private var store = SavedFindsStore.shared
    @State private var bounceTrigger: Int = 0

    private var isSaved: Bool {
        store.isSaved(assetLocalIdentifier: assetId)
    }

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundColor(isSaved ? Color(hex: "FF4D6A") : .white)
                .symbolEffect(.bounce, value: bounceTrigger)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSaved ? 0.5 : 0.18),
                                lineWidth: 0.7)
                )
                .shadow(color: Color.black.opacity(0.25),
                        radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from Saved Finds" : "Save to Saved Finds")
    }

    private func handleTap() {
        if isSaved {
            HapticManager.shared.selection()
            store.removeFind(assetLocalIdentifier: assetId)
            return
        }
        let didSave = store.saveFind(
            assetLocalIdentifier: assetId,
            mediaType: mediaType,
            sourceCategory: sourceCategory,
            sourceApp: sourceApp
        )
        if didSave {
            HapticManager.shared.tapSensation()
            bounceTrigger &+= 1
        }
    }
}
