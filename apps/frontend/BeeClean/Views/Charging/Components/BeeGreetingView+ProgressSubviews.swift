import SwiftUI

// MARK: - Bee Progress Animation View
//
// Drives the bee mascot's per-stage idle loop. Watches `targetStage` (derived
// from progress) and restarts the playback Task whenever the user crosses a
// stage threshold.
struct BeeProgressAnimationView: View {
    let progress: Double
    let isAnimating: Bool

    @State private var frames: [String] = []
    @State private var frameIndex = 0

    // Main-runloop ticker. Advancing `frameIndex` modulo `frames.count` on every
    // tick loops the stage's idle animation forever by construction — no Task,
    // no per-frame cancellation/re-sync, no stale `self` capture.
    private let ticker = Timer.publish(every: 1.0 / BeeStageAnimationConfig.fps,
                                       on: .main, in: .common).autoconnect()

    private var targetStage: Int {
        BeeStageAnimationConfig.stage(for: min(max(progress, 0), 1))
    }

    private var currentAssetName: String {
        if frames.indices.contains(frameIndex) { return frames[frameIndex] }
        return BeeStageAnimationConfig.stageAssetName(
            stage: targetStage,
            loopIndex: 0,
            frame: BeeStageAnimationConfig.firstFrame(for: targetStage)
        )
    }

    var body: some View {
        beeImage(named: currentAssetName)
            .frame(maxWidth: .infinity)
            .onAppear { rebuild() }
            .onChange(of: targetStage) { _, _ in rebuild() }
            .onReceive(ticker) { _ in
                guard isAnimating, !frames.isEmpty else { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
    }

    @ViewBuilder
    private func beeImage(named assetName: String) -> some View {
        if let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
        } else {
            Image(BeeStageAnimationConfig.fallbackAssetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
        }
    }

    private func rebuild() {
        frames = BeeStageAnimationConfig.frameNames(for: targetStage)
        frameIndex = 0
    }
}

