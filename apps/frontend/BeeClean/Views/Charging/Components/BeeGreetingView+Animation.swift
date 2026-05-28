import Foundation

// MARK: - Bee Stage Animation Config
//
// Pure data + lookup logic for the bee mascot's per-stage idle loop frames.
// No SwiftUI dependency — `BeeProgressAnimationView` consumes this to drive
// playback in a Task loop.
enum BeeStageAnimationConfig {
    static let fallbackAssetName = "bee_mascot"
    static let fps: Double = 24

    struct LoopRange {
        let prefix: String
        let startFrame: Int
        let endFrame: Int
    }

    static let stageLoops: [Int: [LoopRange]] = [
        1: [
            LoopRange(prefix: "1/Dynamic1/Dynamic1_", startFrame: 85, endFrame: 203),
            LoopRange(prefix: "1/Dynamic2/Dynamic2_", startFrame: 216, endFrame: 343)
        ],
        2: [
            LoopRange(prefix: "2/Dynamic1/Dynamic1_", startFrame: 120, endFrame: 201),
            LoopRange(prefix: "2/Dynamic2/Dynamic2_", startFrame: 120, endFrame: 201)
        ],
        3: [
            LoopRange(prefix: "3/Dynamic1/Dynamic1_", startFrame: 106, endFrame: 164),
            LoopRange(prefix: "3/Dynamic2/Dynamic2_", startFrame: 181, endFrame: 236)
        ],
        4: [
            LoopRange(prefix: "4/Dynamic1/Dynamic1_", startFrame: 84, endFrame: 132),
            LoopRange(prefix: "4/Dynamic2/Dynamic2_", startFrame: 146, endFrame: 178)
        ],
        5: [
            LoopRange(prefix: "5/Dynamic1/Dynamic1_", startFrame: 114, endFrame: 178)
        ]
    ]

    static func stage(for progress: Double) -> Int {
        let p = min(max(progress, 0), 1)
        switch p {
        case ..<0.55: return 1
        case ..<0.72: return 2
        case ..<0.86: return 3
        case ..<0.95: return 4
        default: return 5
        }
    }

    static func firstFrame(for stage: Int) -> Int {
        let clampedStage = min(max(stage, 1), 5)
        return stageLoops[clampedStage]?.first?.startFrame ?? 1
    }

    static func stageAssetName(stage: Int, loopIndex: Int, frame: Int) -> String {
        let clampedStage = min(max(stage, 1), 5)
        let loops = stageLoops[clampedStage] ?? stageLoops[1] ?? []
        let safeLoopIndex = min(max(loopIndex, 0), loops.count - 1)
        let loop = loops[safeLoopIndex]
        return String(format: "%@%05d", loop.prefix, frame)
    }

    /// Flattened, ordered frame-name list for a stage — every loop's frames
    /// concatenated. A frame ticker cycles this modulo its count to loop the
    /// stage's idle animation indefinitely.
    static func frameNames(for stage: Int) -> [String] {
        let clamped = min(max(stage, 1), 5)
        let loops = stageLoops[clamped] ?? stageLoops[1] ?? []
        return loops.enumerated().flatMap { idx, loop in
            (loop.startFrame...loop.endFrame).map {
                stageAssetName(stage: clamped, loopIndex: idx, frame: $0)
            }
        }
    }
}

