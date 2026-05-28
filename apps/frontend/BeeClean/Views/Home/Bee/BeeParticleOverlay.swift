import SwiftUI

private struct BeeParticle: Identifiable {
    let id = UUID()
    let type: ParticleType
    let start: CGPoint
    let end: CGPoint
    let size: CGFloat
    let rotation: Double
    var opacity: Double = 1
    var scale: CGFloat = 1

    enum ParticleType {
        case sparkle
        case honeyDrop
        case puff
    }
}

struct BeeParticleOverlay: View {
    @ObservedObject var vm: BeeViewModel

    @State private var particles: [BeeParticle] = []
    @State private var lastDeleteToken = 0
    @State private var lastSparkleToken = 0
    @State private var lastRewardToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    particleView(for: particle)
                        .position(particle.start)
                        .offset(x: particle.end.x - particle.start.x, y: particle.end.y - particle.start.y)
                        .opacity(particle.opacity)
                        .scaleEffect(particle.scale)
                        .rotationEffect(.degrees(particle.rotation))
                }
            }
            .onChange(of: vm.deleteReactionToken) { _, token in
                guard token != lastDeleteToken else { return }
                lastDeleteToken = token
                emitDeleteParticles(in: geo.size)
            }
            .onChange(of: vm.sparkleToken) { _, token in
                guard token != lastSparkleToken else { return }
                lastSparkleToken = token
                emitSparkleBurst(in: geo.size)
            }
            .onChange(of: vm.rewardToken) { _, token in
                guard token != lastRewardToken else { return }
                lastRewardToken = token
                emitRewardParticles(in: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func particleView(for particle: BeeParticle) -> some View {
        switch particle.type {
        case .sparkle:
            SparkleShape()
                .fill(Color(hex: "F5D55A"))
                .frame(width: particle.size, height: particle.size)
        case .honeyDrop:
            HoneyDropShape()
                .fill(LinearGradient(colors: [Color(hex: "F7D94C"), Color(hex: "D69313")], startPoint: .top, endPoint: .bottom))
                .frame(width: particle.size * 0.8, height: particle.size * 1.2)
        case .puff:
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: particle.size, height: particle.size)
        }
    }

    private func emitDeleteParticles(in size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
        let meter = CGPoint(x: size.width * 0.5, y: size.height * 0.88)

        var all: [BeeParticle] = []
        all += (0..<4).map { _ in
            BeeParticle(type: .puff,
                        start: center,
                        end: CGPoint(x: center.x + CGFloat.random(in: -34...34), y: center.y + CGFloat.random(in: -20...20)),
                        size: CGFloat.random(in: 14...22),
                        rotation: 0,
                        opacity: 0.75,
                        scale: 0.3)
        }
        all += (0..<5).map { _ in
            BeeParticle(type: .sparkle,
                        start: center,
                        end: CGPoint(x: center.x + CGFloat.random(in: -46...46), y: center.y + CGFloat.random(in: -42...42)),
                        size: CGFloat.random(in: 6...12),
                        rotation: Double.random(in: 0...360),
                        opacity: 1,
                        scale: 0.2)
        }
        all.append(BeeParticle(type: .honeyDrop,
                               start: CGPoint(x: center.x, y: center.y + 8),
                               end: meter,
                               size: 18,
                               rotation: Double.random(in: -12...12),
                               opacity: 1,
                               scale: 0.4))
        animate(particles: all, duration: 0.8)
    }

    private func emitSparkleBurst(in size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
        let burst = (0..<10).map { index in
            let angle = Double(index) / 10.0 * (.pi * 2)
            let radius = CGFloat.random(in: 36...72)
            return BeeParticle(type: .sparkle,
                               start: center,
                               end: CGPoint(x: center.x + cos(angle) * radius,
                                            y: center.y + sin(angle) * radius),
                               size: CGFloat.random(in: 7...14),
                               rotation: Double.random(in: 0...360),
                               opacity: 1,
                               scale: 0.25)
        }
        animate(particles: burst, duration: 0.7)
    }

    private func emitRewardParticles(in size: CGSize) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
        let meter = CGPoint(x: size.width * 0.5, y: size.height * 0.88)
        var bundle: [BeeParticle] = []
        bundle += (0..<8).map { _ in
            BeeParticle(type: .sparkle,
                        start: center,
                        end: CGPoint(x: center.x + CGFloat.random(in: -90...90), y: center.y + CGFloat.random(in: -80...60)),
                        size: CGFloat.random(in: 8...16),
                        rotation: Double.random(in: 0...360),
                        opacity: 1,
                        scale: 0.25)
        }
        bundle += (0..<3).map { index in
            BeeParticle(type: .honeyDrop,
                        start: CGPoint(x: center.x + CGFloat(index * 10 - 10), y: center.y + 5),
                        end: CGPoint(x: meter.x + CGFloat.random(in: -40...40), y: meter.y),
                        size: CGFloat.random(in: 16...20),
                        rotation: Double.random(in: -18...18),
                        opacity: 1,
                        scale: 0.35)
        }
        animate(particles: bundle, duration: 0.95)
    }

    private func animate(particles newParticles: [BeeParticle], duration: Double) {
        particles.append(contentsOf: newParticles)
        let ids = newParticles.map(\ .id)
        withAnimation(.easeOut(duration: duration)) {
            particles = particles.map { particle in
                guard ids.contains(particle.id) else { return particle }
                var copy = particle
                copy.opacity = 0
                copy.scale = particle.type == .puff ? 1.4 : 1.0
                return copy
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.12) {
            particles.removeAll { ids.contains($0.id) }
        }
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.32
        var path = Path()
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * .pi * 2 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct HoneyDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX + 2, y: rect.minY + rect.height * 0.2))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.maxX - 2, y: rect.minY + rect.height * 0.2))
        return path
    }
}
