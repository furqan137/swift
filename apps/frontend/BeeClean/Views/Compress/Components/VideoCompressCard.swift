import SwiftUI
import Photos

// MARK: - Video Compress Card
struct VideoCompressCard: View {
    let video: VideoAsset
    @State private var thumbnail: UIImage?
    @State private var showDetail = false
    /// Same cross-flow source resolution as PhotoCompressCard — the
    /// background EXIF sweep on the similar-photos scan writes into
    /// `analyzedIndex`, and reading from there lets the Compress grid
    /// pick up Instagram saves and other Tier 2 detections without
    /// running its own EXIF pass.
    @Environment(SimilarPhotosStore.self) private var similarStore

    private var resolvedSource: PhotoSource? {
        similarStore.sourceApp(for: video.id) ?? video.sourceApp
    }

    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            showDetail = true
        } label: {
            // Cleanup-tile parity: the thumbnail IS the card. No glass
            // panel chrome, no white halo around the image — just the
            // video edge-to-edge with the savings pill overlaid at
            // bottom-leading using the same espresso capsule the Cleanup
            // video grid uses for its size badge. iCloud chip + duration
            // sit on top in the corners as compact glyphs so the visual
            // hierarchy matches the cleanup detail screens.
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
                // Favorite micro-button — top-leading slot. Tap saves
                // the video into Saved Finds under `.videoCompression`
                // so favorited compress targets survive across sessions
                // and surface in the dedicated Saved Finds grid filter.
                .overlay(alignment: .topLeading) {
                    MediaFavoriteButton(
                        assetId: video.id,
                        mediaType: .video,
                        sourceCategory: .videoCompression,
                        sourceApp: resolvedSource
                    )
                    .padding(8)
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 4) {
                        if video.isInCloud {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .accessibilityLabel("Stored in iCloud")
                        }
                        // Source-app provenance — TikTok / Snapchat /
                        // Instagram / WhatsApp / Telegram / Messenger
                        // detected from the resource filename at load
                        // time. Left of the duration pill so the user
                        // reads provenance → length, matching the
                        // similar/duplicate tile order.
                        SocialSourceBadge(source: resolvedSource, size: 22)
                        Spacer()
                        Text(video.formattedDuration)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                    .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    if video.potentialSavings > 0 {
                        Text("Save \(video.formattedSavings)")
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
            CompressionDetailView(video: video)
        }
        .task {
            // Lazy source classification — see PhotoCompressCard for
            // rationale. Video assets generally classify on Tier 1 (the
            // filename signal is very clean for Snapchat / TikTok /
            // WhatsApp / Telegram video saves) so the badge typically
            // lands within one frame of the tile appearing.
            similarStore.requestSourceClassification(
                assetId: video.id,
                asset: video.asset
            )
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let asset = video.asset else { return }
        let requestedVideoId = video.id
        let size = CGSize(width: 300, height: 400)

        if let hit = AssetThumbnailCache.shared.cached(assetId: requestedVideoId, size: size) {
            thumbnail = hit
            return
        }

        // See PhotoCompressCard.loadThumbnail for rationale — this is the
        // same two-phase opportunistic fetch with a shared NSCache behind it.
        AssetThumbnailCache.shared.loadThumbnail(
            for: asset,
            assetId: requestedVideoId,
            size: size
        ) { image, _ in
            guard requestedVideoId == video.id else { return }
            thumbnail = image
        }
    }
}

// MARK: - Card Button Style
struct VideoCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    Text("Video Compress Card requires PHAsset")
        .preferredColorScheme(.light)
}
