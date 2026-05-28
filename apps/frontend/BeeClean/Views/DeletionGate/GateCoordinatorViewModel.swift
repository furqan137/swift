import Foundation
import GoogleMobileAds

// MARK: - GateCoordinatorViewModel
//
// Section-aware gate logic. Reads quota via config.quotaKeyPath and
// routes consume/grant calls through section-aware endpoints.
// Replaces the hardcoded photos-only logic in DeletionGateViewModel
// while keeping the same ad manager + pro nag pattern.

@MainActor @Observable
final class GateCoordinatorViewModel {

    // MARK: - Dependencies

    let config: FeatureGateConfig
    let adManager: RewardedAdManager
    let quotaService: QuotaService

    // MARK: - State

    var quota: UserQuota?
    var isLoading: Bool = false
    var error: String?

    /// Number of ads watched in the current app session (resets on app close).
    /// Static so it persists across gate presentations within the same session.
    static var sessionAdCount: Int = 0

    /// Whether the Pro nag sheet should be shown (every 3rd ad).
    var showProNag: Bool = false

    // MARK: - Computed

    var freeActionsRemaining: Int {
        guard let quota else { return 0 }
        return quota[keyPath: config.quotaKeyPath]
    }

    var canUseFreeActions: Bool {
        freeActionsRemaining > 0
    }

    var isAdReady: Bool {
        adManager.isReady
    }

    var isAdCapReached: Bool {
        (quota?.adsWatchedToday ?? 0) >= 15
    }

    var canWatchAd: Bool {
        isAdReady && !isAdCapReached
    }

    // MARK: - Init

    init(
        config: FeatureGateConfig,
        adManager: RewardedAdManager? = nil,
        quotaService: QuotaService? = nil
    ) {
        self.config = config
        self.adManager = adManager ?? RewardedAdManager()
        self.quotaService = quotaService ?? QuotaService.shared
    }

    // MARK: - Load Quota

    func loadQuota() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            quota = try await quotaService.checkQuota()
        } catch {
            self.error = error.localizedDescription
            if quota == nil {
                quota = UserQuota.fallback()
            }
        }

        // Preload ad for patterns that support it
        if config.pattern != .hardCap && !adManager.isReady {
            Task { await adManager.preload() }
        }
    }

    // MARK: - Choose Free

    /// Consumes free actions. Returns the number of actions approved
    /// (capped at remaining free allowance and selected count).
    func chooseFree(selectedCount: Int) async -> Int {
        let toConsume = min(selectedCount, freeActionsRemaining)
        guard toConsume > 0 else { return 0 }

        Analytics.track("gate_chose_free", properties: [
            "count": toConsume,
            "section": config.section.rawValue
        ])

        do {
            let response = try await quotaService.consumeSectionQuota(
                section: config.section.rawValue,
                count: toConsume
            )
            quota = response.quota
            return toConsume
        } catch {
            self.error = error.localizedDescription
            // Optimistic: allow the action locally even if server fails
            return toConsume
        }
    }

    // MARK: - Choose Ad

    /// Presents a rewarded ad. On reward, grants section-specific reward amount
    /// server-side and returns the approved action count. Returns 0 on failure.
    func chooseAd(selectedCount: Int) async -> Int {
        guard config.pattern != .hardCap else { return 0 }

        Analytics.track("gate_chose_ad", properties: [
            "section": config.section.rawValue
        ])

        let earned = await adManager.presentAd()
        guard earned else { return 0 }

        Self.sessionAdCount += 1

        if config.section == .compress {
            Analytics.track("compress_metered_ad_triggered", properties: [
                "section": config.section.rawValue
            ])
        }

        // Grant server-side reward
        do {
            let response = try await quotaService.grantSectionAdReward(
                section: config.section.rawValue
            )
            quota = response.quota
        } catch {
            self.error = error.localizedDescription
        }

        // Pro nag every 3rd ad
        if Self.sessionAdCount > 0 && Self.sessionAdCount % 3 == 0 {
            showProNag = true
        }

        return min(selectedCount, config.adRewardAmount)
    }
}
