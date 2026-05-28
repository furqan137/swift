import Foundation

// MARK: - Gate Section & Pattern

enum GateSection: String, CaseIterable, Sendable {
    case photos, videos, contacts, email, compress
}

enum GatePattern: Sendable {
    /// Pattern A: free allowance + rewarded ad batch + pro bypass
    case rewardedAd
    /// Pattern B: free allowance + pro only (no ads ever)
    case hardCap
    /// Pattern C: free allowance then 1-ad-per-action
    case meteredPerAd
}

// MARK: - Feature Gate Config

struct FeatureGateConfig: @unchecked Sendable {
    let section: GateSection
    let pattern: GatePattern
    let freePerDay: Int
    let adRewardAmount: Int          // 0 for hardCap
    let actionVerb: String           // "Delete", "Merge", "Clean", "Compress"
    let itemNounSingular: String     // "photo", "contact", "email", "file"
    let itemNounPlural: String       // "photos", "contacts", "emails", "files"
    let helperText: String?          // Pattern B only
    let quotaKeyPath: KeyPath<UserQuota, Int>

    func itemNoun(_ count: Int) -> String {
        count == 1 ? itemNounSingular : itemNounPlural
    }

    func adButtonLabel(_ count: Int) -> String {
        switch pattern {
        case .rewardedAd:
            return "Watch Ad — \(actionVerb) \(min(count, adRewardAmount))"
        case .meteredPerAd:
            return "Watch Ad → \(actionVerb) 1 File"
        case .hardCap:
            return "" // never shown
        }
    }

    static func config(for section: GateSection) -> FeatureGateConfig {
        switch section {
        case .photos:
            return FeatureGateConfig(
                section: .photos,
                pattern: .rewardedAd,
                freePerDay: 5,
                adRewardAmount: 25,
                actionVerb: "Delete",
                itemNounSingular: "photo",
                itemNounPlural: "photos",
                helperText: nil,
                quotaKeyPath: \.freePhotoDeletesRemaining
            )
        case .videos:
            return FeatureGateConfig(
                section: .videos,
                pattern: .rewardedAd,
                freePerDay: 1,
                adRewardAmount: 15,
                actionVerb: "Delete",
                itemNounSingular: "video",
                itemNounPlural: "videos",
                helperText: nil,
                quotaKeyPath: \.freeVideoDeletesRemaining
            )
        case .contacts:
            return FeatureGateConfig(
                section: .contacts,
                pattern: .hardCap,
                freePerDay: 2,
                adRewardAmount: 0,
                actionVerb: "Merge",
                itemNounSingular: "contact",
                itemNounPlural: "contacts",
                helperText: "Free users can merge up to 2 contacts per day. Upgrade to Pro for unlimited.",
                quotaKeyPath: \.freeContactMergesRemaining
            )
        case .email:
            return FeatureGateConfig(
                section: .email,
                pattern: .rewardedAd,
                freePerDay: 5,
                adRewardAmount: 15,
                actionVerb: "Clean",
                itemNounSingular: "email",
                itemNounPlural: "emails",
                helperText: nil,
                quotaKeyPath: \.freeEmailDeletesRemaining
            )
        case .compress:
            return FeatureGateConfig(
                section: .compress,
                pattern: .meteredPerAd,
                freePerDay: 3,
                adRewardAmount: 1,
                actionVerb: "Compress",
                itemNounSingular: "file",
                itemNounPlural: "files",
                helperText: nil,
                quotaKeyPath: \.freeCompressActionsRemaining
            )
        }
    }
}
