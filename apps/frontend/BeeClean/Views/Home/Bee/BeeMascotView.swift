import SwiftUI

struct BeeMascotView: View {
    @ObservedObject var vm: BeeViewModel

    @State private var previousStage: BeeStage?
    @State private var previousOpacity = 0.0
    @State private var bounceScale: CGFloat = 1
    @State private var baseY: CGFloat = 0
    @State private var breatheScale: CGFloat = 1
    @State private var rotateAngle: Double = 0
    @State private var xOffset: CGFloat = 0
    @State private var glowOpacity: Double = 0.08
    @State private var blinkOpacity: Double = 0
    @State private var behaviorTask: Task<Void, Never>?

    @State private var lastStateToken = 0
    @State private var lastBehaviorToken = 0
    @State private var lastEvolutionToken = 0
    @State private var lastDevolutionToken = 0
    @State private var lastRewardToken = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "F4D44D").opacity(glowOpacity), Color(hex: "F4D44D").opacity(glowOpacity * 0.28), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 260, height: 260)

            if let previousStage {
                Image(previousStage.fallbackImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(previousOpacity)
            }

            currentBeeImage

            BeeParticleOverlay(vm: vm)

            if vm.state == .thinking {
                ThinkingOrbitView(token: vm.orbitToken)
            }

            BlinkOverlay(opacity: blinkOpacity)
        }
        .offset(x: xOffset, y: baseY)
        .rotationEffect(.degrees(rotateAngle))
        .scaleEffect(bounceScale * breatheScale)
        .onAppear {
            startBaseIdle()
            startBehaviorLoop()
        }
        .onDisappear {
            behaviorTask?.cancel()
        }
        .onChange(of: vm.stage) { old, new in
            previousStage = old
            previousOpacity = 1
            withAnimation(.easeOut(duration: 0.45)) {
                previousOpacity = 0
            }
            runEvolveMotion(for: new)
        }
        .onChange(of: vm.stateToken) { _, token in
            guard token != lastStateToken else { return }
            lastStateToken = token
            reactToState(vm.state)
        }
        .onChange(of: vm.behaviorToken) { _, token in
            guard token != lastBehaviorToken else { return }
            lastBehaviorToken = token
            runBehavior(vm.activeBehavior)
        }
        .onChange(of: vm.evolutionToken) { _, token in
            guard token != lastEvolutionToken else { return }
            lastEvolutionToken = token
            runEvolveMotion(for: vm.stage)
        }
        .onChange(of: vm.devolutionToken) { _, token in
            guard token != lastDevolutionToken else { return }
            lastDevolutionToken = token
            runDevolveMotion(for: vm.stage)
        }
        .onChange(of: vm.rewardToken) { _, token in
            guard token != lastRewardToken else { return }
            lastRewardToken = token
            runCelebrationPulse()
        }
    }

    private var currentBeeImage: some View {
        Image(vm.stage.fallbackImageName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private func startBaseIdle() {
        withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
            baseY = -5
        }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            breatheScale = 1.014
        }
    }

    private func startBehaviorLoop() {
        behaviorTask?.cancel()
        behaviorTask = Task {
            while !Task.isCancelled {
                let ns = UInt64(Double.random(in: 6...12) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    vm.triggerRandomBehavior()
                }
            }
        }
    }

    private func reactToState(_ state: BeeMascotState) {
        switch state {
        case .idle:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                bounceScale = 1
                xOffset = 0
                rotateAngle = 0
                glowOpacity = max(glowOpacity, 0.08)
            }
        case .reacting:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.44)) {
                bounceScale = 1.08
                xOffset = 5
                rotateAngle = 2.5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    bounceScale = 1
                    xOffset = 0
                    rotateAngle = 0
                }
            }
        case .celebrating:
            runCelebrationPulse()
        case .thinking:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                rotateAngle = 1.2
                glowOpacity = 0.18
            }
        case .encouraging:
            withAnimation(.spring(response: 0.34, dampingFraction: 0.48)) {
                baseY = -10
                bounceScale = 1.04
            }
        case .evolving:
            runEvolveMotion(for: vm.stage)
        case .devolving:
            runDevolveMotion(for: vm.stage)
        }
    }

    private func runBehavior(_ behavior: BeeIdleBehavior) {
        guard vm.state == .idle else { return }
        switch behavior {
        case .hoverSway:
            withAnimation(.easeInOut(duration: 0.7)) { rotateAngle = -1.6; xOffset = -4 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                withAnimation(.easeInOut(duration: 0.7)) { rotateAngle = 1.6; xOffset = 4 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                withAnimation(.easeOut(duration: 0.35)) { rotateAngle = 0; xOffset = 0 }
            }
        case .blink:
            blinkOpacity = 1
            withAnimation(.easeOut(duration: 0.12)) { blinkOpacity = 0 }
        case .wingFlutter:
            withAnimation(.linear(duration: 0.08).repeatCount(4, autoreverses: true)) { rotateAngle = 2.6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeOut(duration: 0.2)) { rotateAngle = 0 }
            }
        case .curiousTilt:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { rotateAngle = -5; xOffset = -6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { rotateAngle = 0; xOffset = 0 }
            }
        case .smallBounce:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.42)) { bounceScale = 1.08; baseY = -12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { bounceScale = 1; baseY = -5 }
            }
        case .glanceToMeter:
            withAnimation(.easeInOut(duration: 0.3)) { rotateAngle = 4; xOffset = 8; baseY = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                withAnimation(.easeOut(duration: 0.25)) { rotateAngle = 0; xOffset = 0; baseY = -5 }
            }
        case .playfulSpin:
            withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) { rotateAngle = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rotateAngle = 0 }
        case .honeyCatch:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.56)) { baseY = -16; xOffset = 10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { baseY = -5; xOffset = 0 }
            }
        case .hoverLoop:
            withAnimation(.easeInOut(duration: 0.45)) { xOffset = -10; baseY = -10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeInOut(duration: 0.45)) { xOffset = 10; baseY = -7 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.3)) { xOffset = 0; baseY = -5 }
            }
        }
    }

    private func runCelebrationPulse() {
        BeeHaptics.forReward(vm.rewardPulse)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.4)) {
            bounceScale = 1.12
            glowOpacity = max(0.22, vm.glowIntensity)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.22)) {
                bounceScale = 0.95
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                bounceScale = 1
                glowOpacity = max(0.08, vm.glowIntensity * 0.55)
            }
        }
    }

    private func runEvolveMotion(for stage: BeeStage) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.48)) {
            bounceScale = 0.94
            glowOpacity = max(0.26, vm.glowIntensity)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                bounceScale = 1.08
                rotateAngle = 1.5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            withAnimation(.easeOut(duration: 0.25)) {
                bounceScale = 1
                rotateAngle = 0
            }
        }
    }

    /// Inverse of `runEvolveMotion` — the bee sags and dims when it drops a
    /// stage. Used for both "scan found new clutter" regressions and the
    /// decay-timer regression that fires when a user goes days without
    /// cleaning. Intentionally low-energy — no sparkle, no rebound — so the
    /// user reads it as "I'm slipping" not "something broke."
    private func runDevolveMotion(for stage: BeeStage) {
        BeeHaptics.lightTap()
        // 1. Droop — gentle downward sag + slight forward tilt + dim glow.
        withAnimation(.easeOut(duration: 0.35)) {
            baseY = 6
            bounceScale = 0.94
            rotateAngle = -3
            glowOpacity = 0.03
        }
        // 2. Tiny head-shake at the bottom of the droop to sell the
        //    disappointment — slower + narrower than the celebrate wobble.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.easeInOut(duration: 0.22)) {
                rotateAngle = 2
                xOffset = -3
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.64) {
            withAnimation(.easeInOut(duration: 0.22)) {
                rotateAngle = -2
                xOffset = 3
            }
        }
        // 3. Settle back to the base idle position, but keep the glow dim
        //    so subsequent idle reads as "the bee's light is lower."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                baseY = -5
                bounceScale = 1
                rotateAngle = 0
                xOffset = 0
                glowOpacity = max(0.05, vm.glowIntensity * 0.6)
            }
        }
    }
}

private struct BlinkOverlay: View {
    let opacity: Double
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

private struct ThinkingOrbitView: View {
    let token: Int
    @State private var rotate = false

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(Color(hex: "F7DA57").opacity(0.85))
                    .frame(width: 8, height: 8)
                    .offset(y: -86)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .rotationEffect(.degrees(rotate ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotate = true
            }
        }
        .onChange(of: token) { _, _ in
            rotate = false
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotate = true
            }
        }
    }
}
