import SwiftUI

// MARK: - Action Flow Coordinator
//
// Orchestrates loading -> summary -> dismiss after a major cleanup action.
// Lives as @StateObject in each section view so each section manages its
// own flow lifecycle independently.

@MainActor
class ActionFlowCoordinator: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var progress: ActionProgress = .init(current: 0, total: 0, label: "")
    @Published private(set) var result: ActionResult?

    enum Phase {
        case idle, loading, summary
    }

    struct ActionProgress {
        var current: Int
        var total: Int
        var label: String
    }

    /// Executes a cleanup action with a loading state and transitions to
    /// the summary page on success. Enforces a 1.5s minimum display time
    /// so fast actions still feel deliberate.
    func execute(
        section: GateSection,
        actionType: ActionResult.ActionType,
        itemCount: Int,
        action: @escaping () async throws -> ActionResult
    ) async {
        phase = .loading
        progress = ActionProgress(
            current: 0,
            total: itemCount,
            label: Self.loadingLabel(section: section, actionType: actionType)
        )

        let start = Date()
        Analytics.track("action_loading_shown", properties: ["section": section.rawValue])

        do {
            let result = try await action()

            // Enforce 1.5s minimum display so fast actions still feel deliberate
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 1.5 {
                try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
            }

            self.result = result
            phase = .summary
            HapticManager.shared.notify(.success)

            Analytics.track("action_completed", properties: [
                "section": section.rawValue,
                "items_processed": result.itemsProcessed,
                "bytes_freed": result.bytesFreed ?? 0,
                "bytes_saved": result.bytesSaved ?? 0,
                "duration_ms": Int(Date().timeIntervalSince(start) * 1000)
            ])
        } catch {
            phase = .idle
        }
    }

    func dismiss() {
        phase = .idle
        result = nil
    }

    static func loadingLabel(section: GateSection, actionType: ActionResult.ActionType) -> String {
        switch (section, actionType) {
        case (.photos, .delete):   return "Deleting photos..."
        case (.videos, .delete):   return "Deleting videos..."
        case (.email, .clean):     return "Cleaning emails..."
        case (.contacts, .merge):  return "Merging contacts..."
        case (.compress, _):       return "Compressing..."
        default:                   return "Processing..."
        }
    }

    /// Suggested next section for the "Clean Something Else" CTA.
    static func nextSection(after current: GateSection) -> GateSection {
        switch current {
        case .photos:   return .videos
        case .videos:   return .compress
        case .email:    return .compress
        case .contacts: return .email
        case .compress: return .photos
        }
    }
}
