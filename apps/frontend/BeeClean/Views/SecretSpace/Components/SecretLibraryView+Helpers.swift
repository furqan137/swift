import SwiftUI

// `@MainActor` on the extension so the helpers below — which all touch
// `vault` (a @StateObject backed by SecretVaultManager, itself
// @MainActor-isolated) — match the actor of the property they read.
// Swift 6 doesn't auto-infer @MainActor on a SwiftUI View's *extension*
// methods the way it does for the main struct, so the explicit
// annotation is needed.
@MainActor
extension SecretLibraryView {

    // MARK: - Helpers
    func toggleSelection(_ item: VaultMediaItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showImportToast = false
        }
    }

    func prepareShareItems() {
        var items: [Any] = []
        for itemId in selectedItems {
            guard let vaultItem = vault.items.first(where: { $0.id == itemId }) else { continue }
            let url = vault.fileURL(for: vaultItem)
            if vaultItem.isVideo {
                items.append(url)
            } else if let image = vault.loadFullImage(for: vaultItem) {
                items.append(image)
            }
        }
        if !items.isEmpty {
            shareItems = items
            showShareSheet = true
        }
    }
}

#Preview {
    SecretLibraryView(showChangePIN: .constant(false), onLock: {})
        .background(Color(hex: "F2F2F7"))
}
