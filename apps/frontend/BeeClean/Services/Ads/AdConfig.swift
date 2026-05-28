import Foundation
import GoogleMobileAds

// MARK: - AdConfig
//
// Static constants for AdMob identifiers and test device ID loading.
// App ID and ad unit IDs are public values (safe to hardcode).
// Test device IDs come from Secrets.xcconfig → Info.plist at build time.

enum AdConfig {
    /// AdMob App ID — matches GADApplicationIdentifier in Info.plist.
    static let appID = "ca-app-pub-6404154472246117~9460094218"

    /// Rewarded ad unit ID for the deletion gate.
    static let rewardedAdUnitID = "ca-app-pub-6404154472246117/5720498953"

    /// Loads test device IDs from Info.plist's `AdMobTestDeviceIDs` key.
    /// The value is injected via Secrets.xcconfig → `$(ADMOB_TEST_DEVICE_IDS)`.
    /// Returns an empty array if the key is missing or the xcconfig variable
    /// wasn't resolved (literal `$(ADMOB_TEST_DEVICE_IDS)` string).
    static func loadTestDeviceIDs() -> [String] {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AdMobTestDeviceIDs") as? String else {
            return []
        }

        // If the xcconfig variable wasn't set, Xcode leaves the literal
        // `$(ADMOB_TEST_DEVICE_IDS)` string in the plist. Treat it as empty.
        if raw.hasPrefix("$(") || raw.isEmpty || raw == "YOUR_DEVICE_HASH_HERE" {
            return []
        }

        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
