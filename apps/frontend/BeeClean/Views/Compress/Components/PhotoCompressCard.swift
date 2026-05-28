import SwiftUI
import Photos

// MARK: - Photo Compress Card
struct PhotoCompressCard: View {
    let photo: PhotoAsset
    @State private var thumbnail: UIImage?
    @State private var showDetail = false
    /// Tier 2 EXIF source for Instagram (and any other source the
    /// background sweep enriches after launch) lives in
    /// `SimilarPhotosStore.analyzedIndex`. Resolve via the store first so
    /// the Compress grid shares the same provenance the rest of the app
    /// uses; fall back to the local Tier 1 (filename) field when the
    /// index hasn't been populated for this asset yet.
    @Environment(SimilarPhotosStore.self) private var similarStore

    private var resolvedSource: PhotoSource? {
        similarStore.sourceApp(for: photo.id) ?? photo.sourceApp
    }

    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            showDetail = true
        } label: {
            // Cleanup-tile parity: the photo IS the card. The white-haloed
            // GlassPanel chrome is gone so every Compress card visually
            // matches the bigger Cleanup video tiles — image edge-to-edge,
            // 14pt corner, savings as a small espresso pill at bottom-
            // leading. iCloud chip stays as a tiny glyph in the top
            // corner so it doesn't compete with the savings CTA.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let thumbnail = thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // Favorite micro-button — top-leading is the only
                // consistently empty corner (top-trailing carries iCloud
                // chip + source badge, bottom-leading carries the "Save
                // X" savings pill). One-tap routes the asset into Saved
                // Finds under the `.photoCompression` bucket so the
                // user can revisit favorited compress targets later.
                .overlay(alignment: .topLeading) {
                    MediaFavoriteButton(
                        assetId: photo.id,
                        mediaType: .photo,
                        sourceCategory: .photoCompression,
                        sourceApp: resolvedSource
                    )
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if photo.isInCloud {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .accessibilityLabel("Stored in iCloud")
                        }
                        // Provenance pill — renders the brand-tinted monogram
                        // for Snapchat / Instagram / TikTok / WhatsApp /
                        // Telegram / Messenger when the photo's source was
                        // detected. `SocialSourceBadge` no-ops on nil and
                        // `.camera` so vanilla camera shots stay clean.
                        SocialSourceBadge(source: resolvedSource, size: 22)
                    }
                    .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    if photo.potentialSavings > 0 {
                        Text("Save \(photo.formattedSavings)")
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color(hex: "1C1917").opacity(0.85))
                            )
                            .padding(8)
                    }
                }
        }
        .buttonStyle(VideoCardButtonStyle())
        .fullScreenCover(isPresented: $showDetail) {
            PhotoCompressionDetailView(photo: photo)
        }
        .task {
            // Kick off lazy source classification the instant the tile
            // appears. Idempotent + dedup'd on the store so a fast scroll
            // past 200 tiles doesn't queue redundant work. Result writes
            // to `liveSourceCache` and the @Observable refresh re-renders
            // this card with the new badge — typically <100ms after
            // appear, often instant on first paint (Tier 1 inline).
            similarStore.requestSourceClassification(
                assetId: photo.id,
                asset: photo.asset
            )
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let asset = photo.asset else { return }
        // Capture the photo id so we can discard the result if the card's
        // asset swapped underneath us while the request was in flight
        // (SwiftUI may recycle the same view for a different photo as the
        // grid scrolls, filters change, or the sort reshuffles the list).
        let requestedPhotoId = photo.id
        let size = CGSize(width: 300, height: 400)

        // Fast path: cache hit returns synchronously.
        if let hit = AssetThumbnailCache.shared.cached(assetId: requestedPhotoId, size: size) {
            thumbnail = hit
            return
        }

        // Opportunistic fetch — the cache callback may fire twice (degraded
        // then full). Show the degraded thumb immediately so the grid never
        // flashes a gray placeholder on scroll; the HQ version replaces it
        // on the second callback.
        AssetThumbnailCache.shared.loadThumbnail(
            for: asset,
            assetId: requestedPhotoId,
            size: size
        ) { image, _ in
            guard requestedPhotoId == photo.id else { return }
            thumbnail = image
        }
    }
}

#Preview {
    Text("Photo Compress Card requires PHAsset")
        .preferredColorScheme(.light)
}
