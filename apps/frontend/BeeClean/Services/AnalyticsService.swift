import Foundation

// MARK: - Analytics Service (Console-Only)

/// Lightweight console-only analytics facade. All analytics events go
/// through this singleton — swapping to a real SDK later is a one-file change.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    func log(_ event: String, properties: [String: Any] = [:]) {
        let timestamp = formatter.string(from: Date())
        if properties.isEmpty {
            print("[Analytics] \(timestamp) \(event)")
        } else {
            let props = properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("[Analytics] \(timestamp) \(event) {\(props)}")
        }
    }

    /// Alias for `log` — allows `Analytics.track("event")` shorthand.
    func track(_ event: String, properties: [String: Any] = [:]) {
        log(event, properties: properties)
    }
}

/// Shorthand typealias so callers can write `Analytics.track(...)`.
typealias Analytics = AnalyticsService

// MARK: - Analytics convenience for static calls
extension AnalyticsService {
    /// Static shorthand: `Analytics.track("event")` without `.shared`.
    nonisolated static func track(_ event: String, properties: [String: Any] = [:]) {
        Task { @MainActor in
            shared.track(event, properties: properties)
        }
    }
}

// MARK: - Ad & Gate Event Names
extension AnalyticsService {
    // Deletion gate events
    static let gateShown = "gate_shown"
    static let gateChoseFree = "gate_chose_free"
    static let gateChoseAd = "gate_chose_ad"
    static let gateChosePro = "gate_chose_pro"
    static let gateDismissed = "gate_dismissed"

    // Ad events
    static let adLoadSuccess = "ad_load_success"
    static let adLoadFailed = "ad_load_failed"
    static let adCompleted = "ad_completed"
    static let adAbandoned = "ad_abandoned"

    // Paywall events
    static let paywallShown = "paywall_shown"
    static let paywallDismissed = "paywall_dismissed"
}
