import SwiftUI

// MARK: - Vault Media Cell (Grid Item)
struct VaultMediaCell: View {
    let item: VaultMediaItem
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    var onSelect: (() -> Void)? = nil

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            // Thumbnail — tap opens viewer
            Button(action: onTap) {
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(hex: "F0EFED"))
                            .overlay(
                                ProgressView()
                                    .tint(Color(hex: "A1A1AA"))
                                    .scaleEffect(0.6)
                            )
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Video badge
            if item.isVideo {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(5)
                        Spacer()
                    }
                }
            }

            // Circle checkbox — always visible, top-right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onSelect?()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color(hex: "1C1917") : Color.white.opacity(0.85))
                                .frame(width: 24, height: 24)

                            Circle()
                                .stroke(isSelected ? Color(hex: "1C1917") : Color(hex: "D4D4D8"), lineWidth: 1.5)
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    .padding(6)
                }
                Spacer()
            }

            // Selection border
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "1C1917"), lineWidth: 2)
            }
        }
        .task {
            thumbnail = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            await SecretVaultManager.shared.loadThumbnail(for: item, size: CGSize(width: 300, height: 300))
        }.value
    }
}
