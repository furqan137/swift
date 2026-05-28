import SwiftUI
import Combine

// MARK: - Theme Manager
/// Singleton that toggles `isNightMode` based on the current hour.
///
/// Day phases (every 6h):
///   00:00–06:00 → night
///   06:00–12:00 → day
///   12:00–18:00 → day
///   18:00–24:00 → night
///
/// Effective rule: night when `hour < 6 || hour >= 18`.
/// Refreshes every 5 minutes via a timer, and on demand via `refresh()`
/// (call from `.task` / `.onChange(of: scenePhase)`).
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var isNightMode: Bool = false

    private var timer: Timer?

    private init() {
        recompute(animated: false)
        // Re-check every 5 minutes — cheap, accurate enough for theme switching.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute(animated: true) }
        }
    }

    /// Force a re-evaluation of the theme. Call from `.task` and on app foreground.
    func refresh() {
        recompute(animated: true)
    }

    private func recompute(animated: Bool) {
        let hour = Calendar.current.component(.hour, from: Date())
        let newValue = hour < 6 || hour >= 18
        guard newValue != isNightMode else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.75)) {
                isNightMode = newValue
            }
        } else {
            isNightMode = newValue
        }
    }
}
