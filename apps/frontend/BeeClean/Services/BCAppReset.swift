import Foundation

// MARK: - App Reset Helper
//
// Centralised "rerun onboarding" reset. Previously the Settings action
// just flipped `hasCompletedOnboarding = false` and called it a day —
// but that left the indexing engine, the cached embedding completion
// flag, the Gmail connection flag, and the goal/pains inputs all
// pointing at the previous user-state. The downstream effect that real
// users hit during support flows:
//
//   • IndexingService persisted `state == .complete` while
//     `embedding_full_index_complete == false` (mismatch from prior
//     runs / migrations) → on re-onboarding, `startIfNeeded` saw the
//     stale `.complete` state, flipped to `.notStarted`, then bounced
//     through a Combine debounce window. Dashboard counts froze for
//     seconds.
//
//   • The user re-authenticates with Gmail but `gmail_connected` is
//     still `true` from the previous session, so the auth flow short-
//     circuits back into the cached connection state.
//
// What this helper does:
//
//   • Clears the onboarding-input keys (`onboardingGoal`,
//     `onboardingPains`) so the questionnaire genuinely re-runs.
//   • Clears the indexing persistence (`indexing_state_v1`,
//     `embedding_full_index_complete`, `embedding_indexed_count`,
//     `embedding_indexed_count_v2`, `embedding_last_index_date`,
//     `embedding_last_index_date_v2`) so the next run does a clean
//     re-index of the embedding store.
//   • Clears `gmail_connected` so the post-onboarding email flow
//     prompts the user to re-auth instead of pretending they're
//     already connected.
//   • Clears the first-query flag (`ask_bee_first_query_sent`).
//   • Flips `hasCompletedOnboarding = false` (the trigger that drives
//     ContentView back to the OnboardingView).
//
// What this helper INTENTIONALLY DOES NOT touch:
//
//   • `bee_*` (stage / cleanup totals / streaks) — earned progress.
//   • `hive_*` (lifetime stats / streaks) — earned progress.
//   • `userName`, `userPhoneNumber`, `secretPIN`, `hasCreatedPIN` —
//     account / vault state. Use Sign Out for those.
//   • `IntelligentPreviewCard.lastSeenCount.*` baselines — wiping
//     these would re-flash "New" on every dashboard card.
//   • SwiftData / file caches — too expensive to rebuild and not the
//     audit's pain point.
enum BCAppReset {

    /// Keys that the "Rerun Onboarding" Settings action should clear.
    /// Every key here is a session-state pointer — none of them
    /// represents user-earned progress.
    private static let keysToReset: [String] = [
        // Onboarding inputs — clear so the questionnaire runs fresh.
        "onboardingGoal",
        "onboardingPains",
        // Indexing engine state — clear so the post-onboarding scan
        // does a real re-index instead of stale-completing.
        "indexing_state_v1",
        "embedding_full_index_complete",
        "embedding_indexed_count",
        "embedding_indexed_count_v2",
        "embedding_last_index_date",
        "embedding_last_index_date_v2",
        // Gmail connection — clear so the email flow re-prompts.
        "gmail_connected",
        // First-query flag for Ask Bee.
        "ask_bee_first_query_sent",
        // Persisted onboarding slide index — restart the carousel from
        // slide 0 on re-run. Without this, a user who got partway
        // through onboarding, completed it, then tapped "Rerun
        // Onboarding" would land on whatever slide they last sat on
        // before finishing.
        "onboarding.currentPage"
    ]

    /// Resets every key in `keysToReset`. Safe to call from any actor —
    /// the underlying `UserDefaults` API is thread-safe for these
    /// primitive keys. The legacy `hasCompletedOnboarding` flip is
    /// dropped: the previous onboarding flow has been removed pending a
    /// redesign, so there's no flag to gate.
    static func resetForOnboarding() {
        let defaults = UserDefaults.standard
        for key in keysToReset {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        // Reset the in-memory IndexingService too so the next
        // `startIfNeeded()` call doesn't read the @Published `.complete`
        // that's still cached in the singleton from the previous
        // session. PhotoIndexingService has its own `resetCheckpoint()`
        // that clears the embedding-count UserDefaults key + the
        // in-memory `fullIndexComplete` flag.
        Task { @MainActor in
            PhotoIndexingService.shared.resetCheckpoint()
        }
    }
}
