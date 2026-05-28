import SwiftUI

// MARK: - Legacy Secret Media Item (kept for compatibility)
/// Note: New code uses VaultMediaItem from SecretVaultManager.swift
struct SecretMediaItem: Identifiable {
    let id = UUID()
    let image: UIImage?
    let isVideo: Bool
}

// MARK: - Secret Media Cell (legacy — not used by new code)
struct SecretMediaCell: View {
    let item: SecretMediaItem
    
    var body: some View {
        ZStack {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.surfaceLight)
                    .aspectRatio(1, contentMode: .fit)
            }
            
            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
    }
}

#Preview {
    SecretMediaCell(item: SecretMediaItem(image: nil, isVideo: true))
        .frame(width: 100, height: 100)
        .preferredColorScheme(.dark)
}
