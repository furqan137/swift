import Foundation
import SwiftUI

// MARK: - Leaderboard View Model
//
// Drives the global leaderboard. Top 100 are seeded from a deterministic
// mock generator so the UI has real data to render until a backend
// endpoint exists. The self entry is inserted at the correct rank
// based on the current user's coin balance (read from HiveStatsManager).
@MainActor
final class LeaderboardViewModel: ObservableObject {
    static let shared = LeaderboardViewModel()

    @Published private(set) var entries: [LeaderboardEntry] = []
    @Published private(set) var selfEntry: LeaderboardEntry?
    @Published private(set) var isLoading: Bool = false

    private init() {
        refreshLocal()
    }

    /// Async stub for future API integration. Currently re-seeds locally
    /// and adds a faint delay so callers can show a loading state.
    func refresh() async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 250_000_000)
        refreshLocal()
        isLoading = false
    }

    // MARK: - Seeding

    private func refreshLocal() {
        let stats = HiveStatsManager.shared
        let selfCoins = stats.coinsBalance
        let selfGB = Double(stats.lifetimeBytesSaved) / 1_000_000_000.0
        let selfStreak = stats.currentStreak
        let selfEquipped = Array(BitePalViewModel.shared.equippedByCategory.values)

        let mocked = Self.mockTop()
        // Insert self at the correct rank by coins descending.
        var combined = mocked
        let selfAccessories: [String] = selfEquipped.isEmpty
            ? ["hat_baseball_blue"]
            : selfEquipped
        let placeholder = LeaderboardEntry(
            id: "self",
            rank: 0,
            displayName: "You",
            coins: selfCoins,
            storageFreedGB: selfGB,
            streak: selfStreak,
            equippedAccessoryIds: selfAccessories,
            isSelf: true
        )
        combined.append(placeholder)
        combined.sort { $0.coins > $1.coins }
        // Re-number ranks.
        var ranked: [LeaderboardEntry] = []
        ranked.reserveCapacity(combined.count)
        for (i, e) in combined.enumerated() {
            ranked.append(
                LeaderboardEntry(
                    id: e.id,
                    rank: i + 1,
                    displayName: e.displayName,
                    coins: e.coins,
                    storageFreedGB: e.storageFreedGB,
                    streak: e.streak,
                    equippedAccessoryIds: e.equippedAccessoryIds,
                    isSelf: e.isSelf
                )
            )
        }
        entries = ranked
        selfEntry = ranked.first { $0.isSelf }
    }

    // MARK: - Mock Data

    private static let mockNames: [String] = [
        "QueenBeeAlpha", "HoneyHive7", "BuzzMaster", "GoldenWing", "Stinger99",
        "BeeWell", "Honeycombo", "HiveQueen", "WaxWizard", "NectarKing",
        "PollenPete", "RoyalJelly", "DroneDave", "FlightOps", "ZephyrZ",
        "MeadowMia", "AmberAce", "SunSeekerX", "DandelionDuke", "ClovrChris",
        "BuzzCutBea", "HiveHopper", "BeeRescue", "SwarmCipher", "GoldDust",
        "WaxLyrical", "Foragelink", "HoneyWraps", "QueenComb", "BeeKnight",
        "ApiaryAna", "JellyJam", "CrystalWax", "NectarNinja", "BumbleBri",
        "RoseHoneyx", "ShadowHive", "BeesNeck", "GoldComb", "VioletVespa",
        "DustyDrone", "SugarSwarm", "PollenPilot", "BeeBard", "GildedFlight",
        "MorningBuzz", "LunarHive", "EclipseBee", "WildflowerW", "FrostNectar",
        "OakHoney", "FernFlight", "WillowWax", "BasilBee", "MarigoldM",
        "SagebrushS", "ThistleT", "IvyHive", "CedarComb", "BirchBee",
        "MapleMist", "PinePollen", "AshenAce", "RowanRoyal", "ElderEm",
        "HazelHive", "JuneberryJ", "RedwoodR", "SequoiaS", "BalsamB",
        "CypressC", "TamarackT", "JuniperJ", "AspenA", "AldreyA",
        "LarchL", "TupeloT", "MyrtleM", "OrchidO", "PetalP",
        "BloomB", "FernyF", "GlowG", "HoneyH", "InkwellI",
        "JadeJ", "KineticK", "LumenL", "MarrowM", "NovaN",
        "OracleO", "PrismP", "QuartzQ", "RiverR", "SolaceS",
        "TempestT", "UmbralU", "VividV", "WhisperW", "XenithX"
    ]

    private static func mockTop() -> [LeaderboardEntry] {
        let accessoryPool: [[String]] = [
            ["hat_crown", "diamond_grill", "wings_gold"],
            ["hat_top", "glasses_aviator", "tie_silk", "watch_diamond"],
            ["wings_crystal", "diamond_necklace", "shoes_jordans"],
            ["hat_baseball_blue", "glasses_wayfarer", "shoes_sneakers"],
            ["antennae_neon", "wings_neon", "watch_smart"],
            ["hat_beanie", "tie_classic", "belt_leather"],
            ["bracelet_diamond", "watch_classic"],
            ["glasses_round", "tie_bowtie"],
            ["antennae_curly", "shoes_loafers"],
            ["antennae_classic"]
        ]

        return (0..<100).map { i in
            let baseCoins = 9800 - (i * 90) + Int.random(in: -25...25, using: &Self.seededRng)
            let coins = max(50, baseCoins)
            let gb = Double(coins) / 110.0 + Double.random(in: -0.5...1.5, using: &Self.seededRng)
            let streak = max(1, 60 - i / 2 + Int.random(in: -3...3, using: &Self.seededRng))
            let name = mockNames[i % mockNames.count]
            let acc = accessoryPool[i % accessoryPool.count]
            return LeaderboardEntry(
                id: "mock_\(i)",
                rank: i + 1,
                displayName: name,
                coins: coins,
                storageFreedGB: max(0.2, gb),
                streak: streak,
                equippedAccessoryIds: acc,
                isSelf: false
            )
        }
    }

    // Seeded RNG so the mock list is stable across launches (no
    // jarring reshuffles every time the user opens the screen).
    nonisolated(unsafe) private static var seededRng = SeededRandom(seed: 0xBEE_C1EA_47)
}

// MARK: - Seeded RNG

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_FACE : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
