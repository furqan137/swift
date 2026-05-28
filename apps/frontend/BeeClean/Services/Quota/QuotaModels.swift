import Foundation

// MARK: - QuotaModels
//
// Codable structs for the server-side deletion quota system.
// Matches the JSON shape returned by Supabase Edge Functions.

struct UserQuota: Codable, Sendable {
    let userId: String
    let freePhotoDeletesRemaining: Int
    let freeVideoDeletesRemaining: Int
    let freeContactMergesRemaining: Int
    let freeEmailDeletesRemaining: Int
    let freeCompressActionsRemaining: Int
    let adsWatchedToday: Int
    let totalDeletesToday: Int
    let quotaResetAt: Date
    let isPro: Bool
    let proExpiresAt: Date?

    // Backward-compatible decoding: new fields default if missing from
    // an older backend response that hasn't been updated yet.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        freePhotoDeletesRemaining = try c.decode(Int.self, forKey: .freePhotoDeletesRemaining)
        freeVideoDeletesRemaining = try c.decodeIfPresent(Int.self, forKey: .freeVideoDeletesRemaining) ?? 1
        freeContactMergesRemaining = try c.decodeIfPresent(Int.self, forKey: .freeContactMergesRemaining) ?? 2
        freeEmailDeletesRemaining = try c.decodeIfPresent(Int.self, forKey: .freeEmailDeletesRemaining) ?? 5
        freeCompressActionsRemaining = try c.decodeIfPresent(Int.self, forKey: .freeCompressActionsRemaining) ?? 3
        adsWatchedToday = try c.decode(Int.self, forKey: .adsWatchedToday)
        totalDeletesToday = try c.decode(Int.self, forKey: .totalDeletesToday)
        quotaResetAt = try c.decode(Date.self, forKey: .quotaResetAt)
        isPro = try c.decode(Bool.self, forKey: .isPro)
        proExpiresAt = try c.decodeIfPresent(Date.self, forKey: .proExpiresAt)
    }

    // Memberwise init for fallback / testing
    init(
        userId: String,
        freePhotoDeletesRemaining: Int,
        freeVideoDeletesRemaining: Int = 1,
        freeContactMergesRemaining: Int = 2,
        freeEmailDeletesRemaining: Int = 5,
        freeCompressActionsRemaining: Int = 3,
        adsWatchedToday: Int,
        totalDeletesToday: Int,
        quotaResetAt: Date,
        isPro: Bool,
        proExpiresAt: Date?
    ) {
        self.userId = userId
        self.freePhotoDeletesRemaining = freePhotoDeletesRemaining
        self.freeVideoDeletesRemaining = freeVideoDeletesRemaining
        self.freeContactMergesRemaining = freeContactMergesRemaining
        self.freeEmailDeletesRemaining = freeEmailDeletesRemaining
        self.freeCompressActionsRemaining = freeCompressActionsRemaining
        self.adsWatchedToday = adsWatchedToday
        self.totalDeletesToday = totalDeletesToday
        self.quotaResetAt = quotaResetAt
        self.isPro = isPro
        self.proExpiresAt = proExpiresAt
    }

    /// Offline/error fallback with generous defaults so the user isn't blocked.
    static func fallback() -> UserQuota {
        UserQuota(
            userId: "",
            freePhotoDeletesRemaining: 5,
            freeVideoDeletesRemaining: 1,
            freeContactMergesRemaining: 2,
            freeEmailDeletesRemaining: 5,
            freeCompressActionsRemaining: 3,
            adsWatchedToday: 0,
            totalDeletesToday: 0,
            quotaResetAt: Date().addingTimeInterval(86400),
            isPro: false,
            proExpiresAt: nil
        )
    }
}

struct ConsumeDeletesResponse: Codable, Sendable {
    let success: Bool
    let quota: UserQuota
}

struct GrantAdRewardResponse: Codable, Sendable {
    let success: Bool
    let deletesGranted: Int
    let quota: UserQuota
}

struct SectionAdRewardResponse: Codable, Sendable {
    let success: Bool
    let rewardAmount: Int
    let quota: UserQuota
}

struct QuotaError: Codable, Sendable {
    let error: String
    let code: String?
}
