import SwiftUI

// MARK: - Accessory Category
enum AccessoryCategory: String, CaseIterable, Identifiable, Codable {
    case hats
    case sunglasses
    case ties
    case bracelets
    case belts
    case wings
    case watch
    case diamonds
    case antennae
    case shoes
    case backgrounds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hats:        return "Hats"
        case .sunglasses:  return "Sunglasses"
        case .ties:        return "Ties"
        case .bracelets:   return "Bracelets"
        case .belts:       return "Belts"
        case .wings:       return "Wings"
        case .watch:       return "Watch"
        case .diamonds:    return "Diamonds"
        case .antennae:    return "Antennae"
        case .shoes:       return "Shoes"
        case .backgrounds: return "Backgrounds"
        }
    }

    /// SF Symbol shown as the category tab icon (and as fallback art
    /// for items whose imageset is not yet in the asset catalog).
    var sfSymbol: String {
        switch self {
        case .hats:        return "graduationcap.fill"
        case .sunglasses:  return "sunglasses.fill"
        case .ties:        return "comb.fill"
        case .bracelets:   return "circle.hexagongrid.fill"
        case .belts:       return "rectangle.compress.vertical"
        case .wings:       return "wind"
        case .watch:       return "applewatch"
        case .diamonds:    return "diamond.fill"
        case .antennae:    return "antenna.radiowaves.left.and.right"
        case .shoes:       return "shoeprints.fill"
        case .backgrounds: return "photo.fill"
        }
    }

    var tint: Color {
        switch self {
        case .hats:        return .categoryHoney
        case .sunglasses:  return .categorySky
        case .ties:        return .categoryCrimson
        case .bracelets:   return .categoryViolet
        case .belts:       return .categoryCocoa
        case .wings:       return .categoryMint
        case .watch:       return .categoryTeal
        case .diamonds:    return .categoryIndigo
        case .antennae:    return .categoryAmber
        case .shoes:       return .categoryRose
        case .backgrounds: return .categorySlate
        }
    }
}

// MARK: - BeeAccessory
struct BeeAccessory: Identifiable, Codable, Hashable {
    let id: String
    let category: AccessoryCategory
    let displayName: String
    /// Image asset name in `Assets.xcassets/BitePalAccessories/`. Falls
    /// back to the category's SF Symbol when the imageset is missing,
    /// so the catalog renders even before real artwork lands.
    let assetName: String
    let price: Int
    let isPremium: Bool

    init(
        id: String,
        category: AccessoryCategory,
        displayName: String,
        assetName: String? = nil,
        price: Int,
        isPremium: Bool = false
    ) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.assetName = assetName ?? id
        self.price = price
        self.isPremium = isPremium
    }
}
