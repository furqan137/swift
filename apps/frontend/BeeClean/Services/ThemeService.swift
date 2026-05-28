import Foundation
import SwiftUI
import Combine

// MARK: - Theme Service
//
// Live time-of-day theme. Window-level `mode` stays pinned to `.light`
// (dark mode was retired app-wide for the rest of the UI), but
// `scheduleMode` flips between `.light` and `.dark` based on the
// device's local clock so HomeView's background swap (bee_bg_structured
// ↔ bee_bg_night) and any other schedule-driven surface can honor the
// time of day:
//
//   08:00–18:00 local → day (`.light`)
//   18:00–08:00 local → night (`.dark`)
//
// Refreshed on a 5-min timer plus on `scenePhase == .active` via the
// public `refresh()` call wired in BeeCleanApp.
@MainActor
final class ThemeService: ObservableObject {
    static let shared = ThemeService()

    static let userOverrideKey = "preferences.themeOverride"

    enum UserOverride: String {
        case light, night, auto
        var colorScheme: ColorScheme? { .light }
    }

    /// Window-level scheme — always light. Don't reorder; HomeView's
    /// background swap was previously reading this and never flipping.
    /// `scheduleMode` is what callers should bind to for time-of-day art.
    @Published private(set) var mode: ColorScheme = .light
    @Published private(set) var scheduleMode: ColorScheme = .light
    @Published private(set) var slot: Int = 1
    @Published private(set) var nextSwitchAt: Date?
    @Published private(set) var lastServerSync: Date?

    private var timer: Timer?

    private init() {
        recompute(animated: false)
    }

    func start() {
        recompute(animated: false)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute(animated: true) }
        }
    }

    func refresh() async {
        recompute(animated: true)
    }

    private func recompute(animated: Bool) {
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour < 8 || hour >= 18
        let next: ColorScheme = isNight ? .dark : .light
        let nextSlot = isNight ? 2 : 1
        let switchAt = nextBoundary(isNight: isNight)

        guard next != scheduleMode || nextSlot != slot || switchAt != nextSwitchAt else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                scheduleMode = next
                slot = nextSlot
                nextSwitchAt = switchAt
            }
        } else {
            scheduleMode = next
            slot = nextSlot
            nextSwitchAt = switchAt
        }
    }

    private func nextBoundary(isNight: Bool) -> Date {
        let cal = Calendar.current
        let now = Date()
        let targetHour = isNight ? 8 : 18
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = targetHour
        comps.minute = 0
        comps.second = 0
        var candidate = cal.date(from: comps) ?? now
        if candidate <= now {
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}
