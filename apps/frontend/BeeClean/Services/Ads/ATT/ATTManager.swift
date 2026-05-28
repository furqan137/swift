import Foundation
import AppTrackingTransparency

// MARK: - ATTManager
//
// Manages App Tracking Transparency authorization. Shows a custom
// pre-prompt once per install, then triggers the system ATT dialog.
// Persists the "shown" flag in UserDefaults so the pre-prompt never
// re-appears after the first launch.

@MainActor
final class ATTManager: ObservableObject {
    static let shared = ATTManager()

    private static let prePromptShownKey = "att_prompt_shown"

    @Published private(set) var status: ATTrackingManager.AuthorizationStatus

    /// True if the pre-prompt has never been shown to this user.
    var shouldShowPrePrompt: Bool {
        !UserDefaults.standard.bool(forKey: Self.prePromptShownKey)
    }

    private init() {
        self.status = ATTrackingManager.trackingAuthorizationStatus
    }

    /// Triggers the system ATT dialog. Should be called from the
    /// pre-prompt's "Continue" button. Marks the pre-prompt as shown
    /// regardless of the user's choice.
    @discardableResult
    func requestAuthorization() async -> ATTrackingManager.AuthorizationStatus {
        UserDefaults.standard.set(true, forKey: Self.prePromptShownKey)

        let result = await ATTrackingManager.requestTrackingAuthorization()
        status = result
        return result
    }
}
