import Foundation
import UIKit

enum BeeStage: Int, CaseIterable, Codable {
    case stage1, stage2, stage3, stage4, stage5

    /// Live emotional state derived from the Clean Bar — now the user's
    /// progress within the current level (0.0–1.0). The bee climbs as the bar
    /// fills and resets to stage1 at the start of each new level.
    static func forCleanBarPercent(_ percent: Double) -> BeeStage {
        switch percent {
        case ..<0.2001: return .stage1   // 0–20%
        case ..<0.4001: return .stage2   // 21–40%
        case ..<0.6001: return .stage3   // 41–60%
        case ..<0.8001: return .stage4   // 61–80%
        default:        return .stage5   // 81–100%
        }
    }

    /// Map the server's 1-based bee stage (1…5) to the 0-based enum.
    static func fromServer(_ stage: Int) -> BeeStage {
        BeeStage(rawValue: max(0, min(stage - 1, 4))) ?? .stage1
    }

    /// Hard threshold above which the meter / button enter "unclean" state
    /// (red flash + alarm copy). Mirrors the strictest absolute floor in
    /// BeeEngine.absoluteFloors so the UI and the stage engine agree.
    static let tooMuchCleanBytes: Int64 = 5 * 1024 * 1024 * 1024  // 5 GB

    var title: String {
        switch self {
        case .stage1: return "Needs You"
        case .stage2: return "Work Mode"
        case .stage3: return "Clean Reveal"
        case .stage4: return "Honey Earned"
        case .stage5: return "Streak Builder"
        }
    }

    /// Headline shown above the storage number on the HiveScoreCard.
    /// One per stage — single source of truth.
    var meterHeadline: String {
        switch self {
        case .stage1: return "Your Bee Is Unclean"
        case .stage2: return "Getting Started"
        case .stage3: return "Looking Better"
        case .stage4: return "Almost There"
        case .stage5: return "Hive Is Spotless"
        }
    }

    /// Status message shown below the storage number / under the ring.
    var meterStatusMessage: String {
        switch self {
        case .stage1: return "Too much clutter — clean to revive your bee"
        case .stage2: return "Good progress — keep cleaning"
        case .stage3: return "Halfway there — your bee is happier"
        case .stage4: return "Just a little more — almost spotless"
        case .stage5: return "Your phone is clean. Maintain the streak"
        }
    }

    /// Stage 1 is the "too much to clean / unclean" state. Drives red flash,
    /// alarm copy and the destructive accent on the stat bar.
    var isUnclean: Bool { self == .stage1 }

    var fallbackImageName: String {
        switch self {
        case .stage1: return "bee_stage1_needs_you"
        case .stage2: return "bee_stage2_work_mode"
        case .stage3: return "bee_stage3_clean_reveal"
        case .stage4: return "bee_stage4_honey_earned"
        case .stage5: return "bee_stage5_streak_build"
        }
    }

    var assetPrefix: String {
        switch self {
        case .stage1: return "stage1"
        case .stage2: return "stage2"
        case .stage3: return "stage3"
        case .stage4: return "stage4"
        case .stage5: return "stage5"
        }
    }

    func frameNames(for kind: BeeAnimationKind, maxFrames: Int) -> [String] {
        (1...maxFrames).compactMap { index in
            let name = "\(assetPrefix)_\(kind.rawValue)_\(String(format: "%02d", index))"
            return UIImage(named: name) != nil ? name : nil
        }
    }

    var idleFrames: [String] { frameNames(for: .idle, maxFrames: 12) }
    var celebrateFrames: [String] { frameNames(for: .celebrate, maxFrames: 20) }
    var evolveFrames: [String] { frameNames(for: .evolve, maxFrames: 20) }
    var thinkingFrames: [String] { frameNames(for: .thinking, maxFrames: 16) }

    static func stage(forTotalActions total: Int) -> BeeStage {
        switch total {
        case ..<15: return .stage1
        case ..<30: return .stage2
        case ..<50: return .stage3
        case ..<80: return .stage4
        default: return .stage5
        }
    }
}

enum BeeAnimationKind: String, Codable {
    case idle
    case celebrate
    case evolve
    case thinking
}

enum BeeMascotState: String, Codable {
    case idle
    case reacting
    case celebrating
    case thinking
    case encouraging
    case evolving
    /// Played when the bee regresses to a lower stage — either new clutter
    /// surfaced in a scan or the decay timer expired from inactivity. The
    /// opposite vibe of `.evolving`: dim glow, slight droop, no sparkle.
    case devolving
}

enum BeeIdleBehavior: String, Codable, CaseIterable {
    case hoverSway
    case blink
    case wingFlutter
    case curiousTilt
    case smallBounce
    case glanceToMeter
    case playfulSpin
    case honeyCatch
    case hoverLoop

    static func randomWeighted() -> BeeIdleBehavior {
        let roll = Double.random(in: 0...1)
        switch roll {
        case ..<0.40: return .hoverSway
        case ..<0.60: return .blink
        case ..<0.75: return .wingFlutter
        case ..<0.85: return .curiousTilt
        case ..<0.95: return .smallBounce
        case ..<0.99: return .glanceToMeter
        default:
            return [.playfulSpin, .honeyCatch, .hoverLoop].randomElement() ?? .hoverLoop
        }
    }
}

enum RewardPulseType: Equatable {
    case none
    case cellFilled(Int)
    case hiveComplete
}
