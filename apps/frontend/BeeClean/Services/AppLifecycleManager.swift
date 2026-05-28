import Foundation
import UIKit

@MainActor
class AppLifecycleManager: ObservableObject {
    static let shared = AppLifecycleManager()

    private let lastActiveKey = "askbee_last_active_timestamp"
    private let freshChatThreshold: TimeInterval = 30 * 60 // 30 minutes

    /// True if this process launch should start AskBee with a fresh chat.
    /// Evaluated once at init from the persisted timestamp.
    let shouldStartFreshOnLaunch: Bool

    private init() {
        let lastActive = UserDefaults.standard.double(forKey: lastActiveKey)
        let now = Date().timeIntervalSince1970

        if lastActive == 0 {
            // First ever launch
            shouldStartFreshOnLaunch = true
        } else {
            // Clamp to 0 so a backward device-clock change (manual,
            // NTP correction) doesn't make `now - lastActive` negative
            // and silently fail every comparison below — the user
            // would get a stale chat when they should get a fresh one.
            let elapsed = max(0, now - lastActive)
            shouldStartFreshOnLaunch = elapsed > freshChatThreshold
        }

        setupObservers()
    }

    /// Returns true if the app has been in the background long enough
    /// to warrant a fresh AskBee chat (warm-resume case).
    func hasBeenInactiveForTooLong() -> Bool {
        let lastActive = UserDefaults.standard.double(forKey: lastActiveKey)
        guard lastActive > 0 else { return true }
        let elapsed = max(0, Date().timeIntervalSince1970 - lastActive)
        return elapsed > freshChatThreshold
    }

    // MARK: - Private

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordActivity()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordActivity()
            }
        }

        // Storage forecast snapshot on foreground. The manager itself
        // throttles to one append per ~6h of wall-clock, so wiring it
        // here is safe regardless of how often the user resumes the app.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                StorageForecastManager.shared.recordSnapshot()
            }
        }
    }

    private func recordActivity() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: lastActiveKey
        )
    }
}
