import SwiftUI

// MARK: - Accessory Image
//
// Renders an accessory's artwork. Tries the named imageset in
// `Assets.xcassets/BitePalAccessories/` first; if it's missing (which
// is the default state until artwork lands), falls back to the
// accessory's category SF Symbol so the catalog still renders cleanly.
struct AccessoryImage: View {
    let accessory: BeeAccessory
    var size: CGFloat = 64

    var body: some View {
        let ui = UIImage(named: accessory.assetName)
        Group {
            if let ui {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: accessory.category.sfSymbol)
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(accessory.category.tint)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
    }
}
