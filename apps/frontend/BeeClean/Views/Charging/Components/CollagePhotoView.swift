import SwiftUI

// MARK: - Contained Photo Stack
/// Neatly stacked photo thumbnails — symmetrical offsets, contained within parent, never bleeds.
struct CollagePhotoView: View {
    let assetIds: [String]
    let isScanning: Bool
    let accentColor: Color

    private let thumbnailSize = CGSize(width: 400, height: 400)
    private let photoRadius: CGFloat = 14
    private let photoHeight: CGFloat = 130

    // Deliberate, symmetrical transforms — index 0 is top (front)
    private static let yOffsets: [CGFloat]  = [0, 7, 14, 21]
    private static let scales: [CGFloat]    = [1.0, 0.97, 0.94, 0.91]
    private static let rotations: [Double]  = [0, -1.0, 0.8, -0.6]

    @State private var appeared = false
    @State private var scanPhase = false

    var body: some View {
        let photos = Array(assetIds.prefix(4))

        GeometryReader { geo in
            ZStack(alignment: .center) {
                // Honey-gold glow behind top photo
                if !photos.isEmpty {
                    RoundedRectangle(cornerRadius: photoRadius + 2)
                        .fill(accentColor.opacity(0.08))
                        .frame(width: geo.size.width, height: photoHeight + 6)
                        .blur(radius: 8)
                        .opacity(appeared ? 1 : 0)
                }

                // Render bottom-to-top so index 0 is on top
                ForEach(Array(photos.enumerated()).reversed(), id: \.offset) { index, assetId in
                    photoLayer(assetId: assetId, index: index, total: photos.count, availableWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: photoHeight + 24)
        .clipped()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .onChange(of: isScanning) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    scanPhase = true
                }
            } else {
                withAnimation { scanPhase = false }
            }
        }
    }

    private func photoLayer(assetId: String, index: Int, total: Int, availableWidth: CGFloat) -> some View {
        let yOff = Self.yOffsets[safe: index] ?? 21
        let scale = Self.scales[safe: index] ?? 0.91
        let rotation = Self.rotations[safe: index] ?? 0
        let scanDrift: CGFloat = isScanning && scanPhase
            ? (index.isMultiple(of: 2) ? 1.0 : -1.0) : 0

        return PhotoThumbnailView(
            assetIdentifier: assetId,
            size: thumbnailSize
        )
        .frame(width: availableWidth, height: photoHeight)
        .clipShape(RoundedRectangle(cornerRadius: photoRadius))
        .overlay(
            RoundedRectangle(cornerRadius: photoRadius)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(
            color: Color.black.opacity(index == 0 ? 0.18 : 0.10),
            radius: index == 0 ? 8 : 4,
            x: 0, y: index == 0 ? 4 : 2
        )
        .scaleEffect(scale)
        .offset(x: scanDrift, y: yOff)
        .rotationEffect(.degrees(rotation))
        .opacity(appeared ? 1.0 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.8)
                .delay(Double(index) * 0.06),
            value: appeared
        )
        .zIndex(Double(total - index))
    }
}

// MARK: - Safe Array Subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
