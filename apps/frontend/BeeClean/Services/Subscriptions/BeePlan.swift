import Foundation

// MARK: - BeePlan
//
// Canonical identifier for the subscription products StoreManager knows
// about. `productID` MUST match what's configured in App Store Connect
// and BeeClean.storekit — StoreKit looks products up by string ID.
//
// Previously this lived in `Views/Onboarding/Native/ChoosePlanView.swift`
// (shared between that view, PromoPaywallView, and StoreManager). The
// onboarding views were removed pending a redesign, but the StoreKit
// plumbing in StoreManager still references this type — so it now lives
// next to its primary consumer.
enum BeePlan: String, CaseIterable, Identifiable {
    case annual
    case weekly

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .annual: return "com.beeclean.pro.annual"
        case .weekly: return "com.beeclean.pro.weekly"
        }
    }

    var title: String {
        switch self {
        case .annual: return "Annual"
        case .weekly: return "Weekly"
        }
    }

    var subtitle: String {
        switch self {
        case .annual: return "$79.99/yr"
        case .weekly: return "No commitment"
        }
    }

    var priceLabel: String {
        switch self {
        case .annual: return "$6.67"
        case .weekly: return "$7.99"
        }
    }

    var cadenceLabel: String {
        switch self {
        case .annual: return "Per month"
        case .weekly: return "Per week"
        }
    }
}
