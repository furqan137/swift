import SwiftUI

// MARK: - Guided Cleanup Frame Animation
//
// Plays a contiguous range of `dynamic-bee/Reactive Animations_*` PNG
// frames. Mirrors the Task-loop pattern from BeeProgressAnimationView.

struct GuidedCleanupFrameAnimationView: View {
    let animation: BeeFrameAnimation
    /// Visual height of the rendered bee. Default 280 — mirrors the Figma
    /// celebration frame where the bee container is 435pt on a 393pt-wide
    /// design (the PNG includes transparent margin around the bee so the
    /// visible bee is roughly 280pt tall on device).
    /// Source: Figma node 564:3999 (`ylome-am7h9 1` — size 435×435).
    var height: CGFloat = 280

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedAssetName: String
    @State private var playbackTask: Task<Void, Never>?

    init(animation: BeeFrameAnimation, height: CGFloat = 280) {
        self.animation = animation
        self.height = height
        _displayedAssetName = State(
            initialValue: animation.assetName(for: animation.startFrame)
        )
    }

    var body: some View {
        Group {
            if let image = UIImage(named: displayedAssetName) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else if let fallback = UIImage(named: "bee_mascot") {
                Image(uiImage: fallback)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(LinearGradient.honeyGradient)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear { syncPlayback(force: true) }
        .onChange(of: animation) { _, _ in syncPlayback(force: true) }
        .onDisappear { playbackTask?.cancel() }
    }

    private func syncPlayback(force: Bool = false) {
        playbackTask?.cancel()

        if reduceMotion {
            displayedAssetName = animation.assetName(for: animation.startFrame)
            return
        }

        playbackTask = Task {
            let start = animation.startFrame
            let end = animation.endFrame
            guard start <= end else { return }

            await MainActor.run {
                displayedAssetName = animation.assetName(for: start)
            }

            while !Task.isCancelled {
                for frame in start...end {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        displayedAssetName = animation.assetName(for: frame)
                    }
                    try? await Task.sleep(
                        nanoseconds: UInt64(1_000_000_000 / animation.fps)
                    )
                }
            }
        }
    }
}
