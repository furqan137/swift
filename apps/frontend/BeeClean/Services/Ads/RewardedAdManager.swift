import Foundation
import GoogleMobileAds
import UIKit

// MARK: - RewardedAdManager
//
// Preloads and presents Google AdMob rewarded video ads. Uses
// `CheckedContinuation` to bridge the delegate callback into Swift
// concurrency. Auto-preloads the next ad after each presentation.
//
// USAGE:
//   let mgr = RewardedAdManager()
//   await mgr.preload()
//   let earned = await mgr.presentAd()  // true if reward earned

@MainActor
final class RewardedAdManager: ObservableObject {

    @Published private(set) var isReady: Bool = false
    @Published private(set) var isPresenting: Bool = false

    private var rewardedAd: GADRewardedAd?
    private var isLoading: Bool = false

    // MARK: - Preload

    /// Loads a rewarded ad with exponential backoff (1s → 2s → 4s, max 3 attempts).
    func preload() async {
        guard !isLoading && !isReady else { return }
        isLoading = true
        defer { isLoading = false }

        let maxAttempts = 3
        var delay: UInt64 = 1_000_000_000 // 1 second

        for attempt in 1...maxAttempts {
            do {
                let ad = try await GADRewardedAd.load(
                    withAdUnitID: AdConfig.rewardedAdUnitID,
                    request: GADRequest()
                )
                self.rewardedAd = ad
                self.isReady = true
                Analytics.track("ad_load_success")
                return
            } catch {
                Analytics.track("ad_load_failed", properties: [
                    "attempt": attempt,
                    "error": error.localizedDescription
                ])

                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: delay)
                    delay *= 2
                }
            }
        }

        // All attempts failed
        self.isReady = false
    }

    // MARK: - Present

    /// Presents the loaded rewarded ad. Returns `true` if the user earned
    /// the reward (watched the ad), `false` if the ad was dismissed early
    /// or couldn't be presented.
    func presentAd() async -> Bool {
        guard let ad = rewardedAd, !isPresenting else { return false }
        guard let rootVC = rootViewController else { return false }

        isPresenting = true
        defer { isPresenting = false }

        let earned = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            ad.present(fromRootViewController: rootVC) {
                continuation.resume(returning: true)
            }
        }

        // Consume the ad and preload the next one
        self.rewardedAd = nil
        self.isReady = false

        if earned {
            Analytics.track("ad_completed")
        } else {
            Analytics.track("ad_abandoned")
        }

        // Preload next ad in the background
        Task { await preload() }

        return earned
    }

    // MARK: - Root VC

    /// Finds the top-most root view controller for ad presentation.
    private var rootViewController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        // Walk the presentation chain to find the top-most VC
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}
