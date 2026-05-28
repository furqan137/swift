import UIKit

/// Thin wrapper over `HapticManager` so the bee surface keeps its
/// readable call sites. Routes through the shared manager which holds
/// pre-warmed generators and a recoverable `CHHapticEngine` — calling
/// `UIImpactFeedbackGenerator(style:).impactOccurred()` directly (the
/// previous implementation) creates and immediately discards a fresh
/// generator on every call without `prepare()`, which makes the first
/// tap after any pause feel late or skip entirely.
///
/// `@MainActor` mirrors `HapticManager`'s isolation — the underlying
/// generators and CoreHaptics engine all live on main, so call sites
/// (every one of which is already a SwiftUI view / gesture handler)
/// stay on the same actor end-to-end.
@MainActor
enum BeeHaptics {
    static func lightTap() {
        HapticManager.shared.impact(.light)
    }

    static func softTap() {
        HapticManager.shared.impact(.soft)
    }

    static func mediumImpact() {
        HapticManager.shared.impact(.medium)
    }

    static func success() {
        HapticManager.shared.notify(.success)
    }

    static func forReward(_ pulse: RewardPulseType) {
        switch pulse {
        case .none:
            break
        case .cellFilled:
            mediumImpact()
        case .hiveComplete:
            mediumImpact()
            // `Task { @MainActor }` instead of DispatchQueue.asyncAfter
            // so the follow-up haptic stays on the same actor as the
            // initial impact — keeps the call site under strict
            // concurrency without the unsafe-isolation crossing.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                success()
            }
        }
    }
}
