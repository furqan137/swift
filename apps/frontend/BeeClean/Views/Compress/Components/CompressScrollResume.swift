import SwiftUI

// MARK: - Bee Reaction
//
// The Compress result screen shows a small bee mascot delivering a quick
// reaction line about the compression result. Reactions are chosen from
// the bee's mood (heart eyes / curious / sweating / impressed / chill)
// based on the savings %, and the copy is sampled randomly from a pool
// per mood so a power user doesn't see the same one-liner every time.
//
// All asset names map to existing bee imagesets — no new art required.

enum BeeReaction: CaseIterable {
    case heartEyes      // 70%+ savings — bee is in love with the result
    case impressed      // 30–70% savings — solid trim
    case curious        // 10–30% savings — modest trim, bee tilts head
    case sweating       // 0% savings or grew — bee is working/embarrassed
    case chill          // exact-zero savings, image already lean — bee shrugs

    /// Pick the appropriate mood for a compression result.
    static func pick(savingsPercent: Int, didGrow: Bool) -> BeeReaction {
        if didGrow { return .sweating }
        switch savingsPercent {
        case 70...:    return .heartEyes
        case 30..<70:  return .impressed
        case 10..<30:  return .curious
        case 1..<10:   return .chill
        default:       return .chill
        }
    }

    /// Asset name from `Assets.xcassets`. We reuse what the project ships
    /// (bee_mascot, bee_waving, bee_running, bee_stage4_honey_earned,
    /// bee_stage5_streak_build) so this works on any iPhone with no
    /// downloads, no permissions, no new images required.
    var assetName: String {
        switch self {
        case .heartEyes: return "bee_stage4_honey_earned"
        case .impressed: return "bee_mascot"
        case .curious:   return "bee_waving"
        case .sweating:  return "bee_running"
        case .chill:     return "bee_stage5_streak_build"
        }
    }

    /// Copy pool — `random()` picks a line so back-to-back compressions
    /// don't read like the bee is stuck on one phrase.
    var lines: [String] {
        switch self {
        case .heartEyes:
            return [
                "Whoa! Practically vapor.",
                "Sweet! Honey on a diet.",
                "I love it. Light as a wing-flap.",
                "Nailed it — pure honey.",
                "Look at us go, hive-five!"
            ]
        case .impressed:
            return [
                "Real bite outta this one.",
                "That's a clean trim.",
                "Lighter, and still sharp.",
                "Tidy work. The hive approves.",
                "Solid sweep — keep going."
            ]
        case .curious:
            return [
                "Every byte counts in the hive.",
                "Small win. Adds up over time.",
                "Found a few crumbs to trim.",
                "Nothing dramatic — but it's something.",
                "A trim is a trim. Onward."
            ]
        case .sweating:
            return [
                "Whew — already at peak buzz!",
                "This one's tighter than my belt.",
                "Nothing left to squeeze, captain.",
                "Hmm — image is already lean.",
                "Yikes. That one fought back."
            ]
        case .chill:
            return [
                "Looks like it was already lean.",
                "Barely a crumb to shed.",
                "Photo's holding its weight.",
                "Pretty much how it was. Cool.",
                "Already tidy — no harm done."
            ]
        }
    }

    /// Sample a fresh line from the pool. Caller passes a stable seed
    /// (e.g. a per-result UUID hash) so the bubble doesn't re-roll on
    /// every SwiftUI re-render.
    func line(seed: Int) -> String {
        guard !lines.isEmpty else { return "" }
        let idx = abs(seed) % lines.count
        return lines[idx]
    }
}

// MARK: - Compress Scroll Resume
//
// On-device "continue where you left off" for the Compress grid (Photos
// and Videos). The user's last visible card index is persisted via
// `UserDefaults`, scoped per category, so it survives tab switches, app
// background/launch, and device restarts. No backend, no iCloud — works
// on any iPhone with no permissions beyond what Compress already needs.
//
// UX:
//   1. As the user scrolls, `recordSeen(_:for:)` updates the latest top
//      index for the active category.
//   2. When `CompressView` appears (or category changes), if the persisted
//      index is past `minResumeIndex`, the resume sheet is shown ONCE
//      per session for that category.
//   3. "Let's Go" scrolls the grid back to the saved card. "No, Thanks"
//      clears the saved position.

@MainActor
final class CompressResumeManager: ObservableObject {
    static let shared = CompressResumeManager()

    /// Don't bother prompting unless the user actually scrolled past this
    /// many cards — otherwise the sheet shows for a 2-card scroll, which
    /// reads as noise. 8 cards ≈ 4 rows in the 2-col grid.
    static let minResumeIndex = 8

    @Published var promptedCategory: CompressCategory?

    /// Per-session memo: which categories already had their resume prompt
    /// dismissed (or accepted) so we don't keep showing it on every tab
    /// re-entry within the same launch.
    private var promptedThisSession: Set<CompressCategory> = []

    private let defaults = UserDefaults.standard
    private func key(for cat: CompressCategory) -> String {
        "compress.resume.\(cat.rawValue)"
    }

    private init() {}

    func recordSeen(_ index: Int, for category: CompressCategory) {
        guard index >= 0 else { return }
        defaults.set(index, forKey: key(for: category))
    }

    func savedIndex(for category: CompressCategory) -> Int {
        max(0, defaults.integer(forKey: key(for: category)))
    }

    func clear(_ category: CompressCategory) {
        defaults.removeObject(forKey: key(for: category))
    }

    /// Call when the user lands on a category. If they have a saved
    /// position past the threshold and we haven't already prompted this
    /// session, surface the resume sheet.
    func considerPrompt(for category: CompressCategory, totalItems: Int) {
        guard !promptedThisSession.contains(category) else { return }
        let saved = savedIndex(for: category)
        guard saved >= Self.minResumeIndex, saved < totalItems else { return }
        promptedThisSession.insert(category)
        promptedCategory = category
    }

    func dismissPrompt() {
        promptedCategory = nil
    }
}

// MARK: - Resume Sheet
//
// Bitepal-styled sheet — solid ink primary CTA, ghost "No, Thanks" — that
// drops over the grid when there's a saved scroll position to return to.
struct CompressResumeSheet: View {
    let category: CompressCategory
    let onResume: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Continue where you left off?")
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("We'll scroll \(category == .videos ? "Videos" : "Photos") back to where you stopped, so you can keep cleaning effortlessly.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "78716C"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Button {
                HapticManager.shared.impact(.medium)
                onResume()
            } label: {
                Text("Let's Go")
                    .font(.custom("Poppins-Bold", size: 17))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(Color(hex: "0A0A0A")))
                    .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
            }
            .buttonStyle(ScaleButtonStyle())

            Button {
                HapticManager.shared.impact(.light)
                onDismiss()
            } label: {
                Text("No, Thanks")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(Color(hex: "78716C"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(GlassPanel(cornerRadius: 28, elevation: .lifted))
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
    }
}
