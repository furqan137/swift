import Foundation
import GoogleMobileAds

// MARK: - DeletionGateViewModel
//
// Orchestrates the deletion gate flow: checks quota, presents
// ad or free-delete options, and communicates approved delete
// counts back to the presenting view.
//
// Owns references to RewardedAdManager and QuotaService. Tracks
// in-session ad count for the ProNag interrupt (every 3rd ad).

@MainActor @Observable
final class DeletionGateViewModel {

    // MARK: - Dependencies

    let adManager: RewardedAdManager
    let quotaService: QuotaService

    // MARK: - State

    var quota: UserQuota?
    var isLoading: Bool = false
    var error: String?

    /// Number of ads watched in the current app session (resets on app close).
    /// Used to trigger ProNagView every 3rd ad. Static so it persists across
    /// gate presentations within the same app session.
    static var sessionAdCount: Int = 0

    /// Whether the Pro nag sheet should be shown.
    var showProNag: Bool = false

    // MARK: - Computed

    var freeDeletesRemaining: Int {
        quota?.freePhotoDeletesRemaining ?? 0
    }

    var canUseFreeDeletes: Bool {
        freeDeletesRemaining > 0
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
        adManager: RewardedAdManager? = nil,
        quotaService: QuotaService? = nil
    ) {
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
            // Fallback: allow 5 free deletes if server is unreachable
            // so the user isn't completely blocked.
            if quota == nil {
                quota = UserQuota(
                    userId: "",
                    freePhotoDeletesRemaining: 5,
                    adsWatchedToday: 0,
                    totalDeletesToday: 0,
                    quotaResetAt: Date().addingTimeInterval(86400),
                    isPro: false,
                    proExpiresAt: nil
                )
            }
        }

        // Preload an ad while the user reads the gate
        if !adManager.isReady {
            Task { await adManager.preload() }
        }
    }

    // MARK: - Choose Free

    /// Consumes free deletes. Returns the number of deletes approved
    /// (capped at remaining free allowance and selected count).
    func chooseFree(selectedCount: Int) async -> Int {
        let toDelete = min(selectedCount, freeDeletesRemaining)
        guard toDelete > 0 else { return 0 }

        Analytics.track("gate_chose_free", properties: ["count": toDelete])

        do {
            let response = try await quotaService.consumeFreeDeletes(count: toDelete)
            quota = response.quota
            return toDelete
        } catch {
            self.error = error.localizedDescription
            // Optimistic: allow the delete locally even if server fails
            return toDelete
        }
    }

    // MARK: - Choose Ad

    /// Presents a rewarded ad. On reward, grants +25 deletes server-side
    /// and returns 25 (the approved delete count). Returns 0 on failure.
    func chooseAd(selectedCount: Int) async -> Int {
        Analytics.track("gate_chose_ad")

        let earned = await adManager.presentAd()
        guard earned else { return 0 }

        Self.sessionAdCount += 1

        // Grant server-side reward
        do {
            let response = try await quotaService.grantAdReward()
            quota = response.quota
        } catch {
            self.error = error.localizedDescription
        }

        // Check if we should show the Pro nag (every 3rd ad)
        if Self.sessionAdCount > 0 && Self.sessionAdCount % 3 == 0 {
            showProNag = true
        }

        return min(selectedCount, 25)
    }
}
