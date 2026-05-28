import Foundation

// MARK: - Leaderboard Entry
//
// Single rung on the global leaderboard ladder. Coins is the ranking
// metric (single source of truth, no toggle). Storage freed rides
// alongside as the honest flex — visible but not what reorders rows.
struct LeaderboardEntry: Identifiable, Hashable {
    let id: String
    let rank: Int
    let displayName: String
    let coins: Int
    let storageFreedGB: Double
    let streak: Int
    /// Accessory ids the entry is wearing — drives the bling preview
    /// on row avatars and the dedicated detail page.
    let equippedAccessoryIds: [String]
    let isSelf: Bool
}
