import SwiftUI

// MARK: - Effect Resolver
/// Maps a ChargingAnimation id to its live effect view
struct ChargingEffectView: View {
    let animationId: String
    let isCompact: Bool

    var body: some View {
        switch animationId {
        case "neon-pulse": NeonPulseEffect(isCompact: isCompact)
        case "aurora": AuroraEffect(isCompact: isCompact)
        case "solar-flare": SolarFlareEffect(isCompact: isCompact)
        case "crystal": CrystalEffect(isCompact: isCompact)
        case "ocean": OceanWaveEffect(isCompact: isCompact)
        case "midnight": MidnightEffect(isCompact: isCompact)
        default: NeonPulseEffect(isCompact: isCompact)
        }
    }
}

// MARK: - Neon Pulse
/// Electric bolt center + concentric ring pulses expanding outward with neon glow
struct NeonPulseEffect: View {
    let isCompact: Bool
    @State private var pulse = false

    private var ringCount: Int { isCompact ? 3 : 5 }
    private var baseSize: CGFloat { isCompact ? 20 : 60 }
    private var ringSpacing: CGFloat { isCompact ? 14 : 50 }

    var body: some View {
        ZStack {
            // Background glow
            if !isCompact {
                RadialGradient(
                    colors: [Color(red: 0, green: 0.4, blue: 1).opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: 200
                )
            }

            // Concentric rings
            ForEach(0..<ringCount, id: \.self) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0, green: 0.4, blue: 1), .cyan],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: isCompact ? 1.5 : 2.5
                    )
                    .frame(width: baseSize + CGFloat(i) * ringSpacing,
                           height: baseSize + CGFloat(i) * ringSpacing)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .opacity(pulse ? 0.0 : 0.7)
                    .animation(
                        .easeOut(duration: isCompact ? 1.8 : 2.2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.3),
                        value: pulse
                    )
            }

            // Center bolt
            Image(systemName: "bolt.fill")
                .font(.system(size: isCompact ? 16 : 44, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .cyan.opacity(0.8), radius: isCompact ? 4 : 16)
                .scaleEffect(pulse ? 1.1 : 0.95)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Aurora
/// Flowing gradient blobs drifting across screen, purple -> green -> teal
struct AuroraEffect: View {
    let isCompact: Bool
    @State private var move = false

    private var blobSize: CGFloat { isCompact ? 50 : 250 }
    private var blurAmount: CGFloat { isCompact ? 20 : 80 }

    var body: some View {
        ZStack {
            // Blob 1 – purple
            Ellipse()
                .fill(Color.purple.opacity(0.6))
                .frame(width: blobSize * 1.2, height: blobSize * 0.8)
                .blur(radius: blurAmount)
                .offset(x: move ? blobSize * 0.3 : -blobSize * 0.3,
                        y: move ? -blobSize * 0.2 : blobSize * 0.2)

            // Blob 2 – green
            Ellipse()
                .fill(Color(red: 0, green: 0.8, blue: 0.6).opacity(0.5))
                .frame(width: blobSize, height: blobSize * 1.1)
                .blur(radius: blurAmount)
                .offset(x: move ? -blobSize * 0.25 : blobSize * 0.25,
                        y: move ? blobSize * 0.25 : -blobSize * 0.15)

            // Blob 3 – teal
            Ellipse()
                .fill(Color.teal.opacity(0.45))
                .frame(width: blobSize * 0.9, height: blobSize)
                .blur(radius: blurAmount)
                .offset(x: move ? blobSize * 0.15 : -blobSize * 0.2,
                        y: move ? blobSize * 0.1 : -blobSize * 0.25)
        }
        .animation(.easeInOut(duration: isCompact ? 3 : 6).repeatForever(autoreverses: true), value: move)
        .onAppear { move = true }
    }
}

// MARK: - Solar Flare
/// Central sun with radiating particle rays, rotating outer ring, pulsing core
struct SolarFlareEffect: View {
    let isCompact: Bool
    @State private var rotate = false
    @State private var pulse = false

    private var coreSize: CGFloat { isCompact ? 22 : 80 }
    private var rayCount: Int { isCompact ? 8 : 12 }

    var body: some View {
        ZStack {
            // Warm ambient glow
            if !isCompact {
                RadialGradient(
                    colors: [Color.orange.opacity(0.25), Color.red.opacity(0.1), .clear],
                    center: .center, startRadius: 20, endRadius: 200
                )
            }

            // Rotating ray ring
            ForEach(0..<rayCount, id: \.self) { i in
                let angle = Double(i) * (360.0 / Double(rayCount))
                Capsule()
                    .fill(
                        LinearGradient(colors: [.orange, .red.opacity(0.3)],
                                       startPoint: .bottom, endPoint: .top)
                    )
                    .frame(width: isCompact ? 2 : 4,
                           height: isCompact ? 12 : 45)
                    .offset(y: -(isCompact ? 24 : 75))
                    .rotationEffect(.degrees(angle))
                    .opacity(pulse ? 0.9 : 0.4)
            }
            .rotationEffect(.degrees(rotate ? 360 : 0))
            .animation(.linear(duration: isCompact ? 6 : 10).repeatForever(autoreverses: false), value: rotate)

            // Core sun
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow, .orange, .red.opacity(0.6)],
                        center: .center, startRadius: 0, endRadius: coreSize * 0.6
                    )
                )
                .frame(width: coreSize, height: coreSize)
                .shadow(color: .orange.opacity(0.7), radius: isCompact ? 8 : 30)
                .scaleEffect(pulse ? 1.12 : 0.92)

            // Sun icon overlay
            Image(systemName: "sun.max.fill")
                .font(.system(size: isCompact ? 12 : 36, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .scaleEffect(pulse ? 1.05 : 0.95)
        }
        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
        .onAppear { rotate = true; pulse = true }
    }
}

// MARK: - Crystal
/// Geometric diamond shapes that rotate and pulse, kaleidoscope feel
struct CrystalEffect: View {
    let isCompact: Bool
    @State private var rotate = false
    @State private var pulse = false

    private var shapeCount: Int { isCompact ? 3 : 5 }
    private var baseSize: CGFloat { isCompact ? 30 : 120 }

    var body: some View {
        ZStack {
            // Crystal shards
            ForEach(0..<shapeCount, id: \.self) { i in
                let scale = 1.0 - Double(i) * (isCompact ? 0.15 : 0.12)
                let rotationOffset = Double(i) * (360.0 / Double(shapeCount))

                RoundedRectangle(cornerRadius: isCompact ? 4 : 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.2, blue: 1).opacity(0.4 + Double(i) * 0.1),
                                Color(red: 0.9, green: 0.3, blue: 0.8).opacity(0.3)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: baseSize * scale, height: baseSize * scale)
                    .rotationEffect(.degrees(rotate ? rotationOffset + 360 : rotationOffset))
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .animation(
                        .linear(duration: isCompact ? 5 : 8)
                            .repeatForever(autoreverses: false),
                        value: rotate
                    )
            }

            // Overlay stroke diamond
            Rectangle()
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.3, blue: 0.8), Color(red: 0.6, green: 0.2, blue: 1)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: isCompact ? 1 : 2
                )
                .frame(width: baseSize * 0.45, height: baseSize * 0.45)
                .rotationEffect(.degrees(45))
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: isCompact ? 4 : 6).repeatForever(autoreverses: false), value: rotate)

            // Center diamond icon
            Image(systemName: "diamond.fill")
                .font(.system(size: isCompact ? 12 : 32, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.9, green: 0.3, blue: 0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 0.6, green: 0.2, blue: 1).opacity(0.6), radius: isCompact ? 4 : 12)
        }
        .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: pulse)
        .onAppear { rotate = true; pulse = true }
    }
}

// MARK: - Ocean Wave
/// Layered sine-wave shapes oscillating vertically, 3 wave layers
struct OceanWaveEffect: View {
    let isCompact: Bool
    @State private var phase: CGFloat = 0

    private var waveHeight: CGFloat { isCompact ? 6 : 25 }
    private var waveWidth: CGFloat { isCompact ? 70 : 400 }

    var body: some View {
        ZStack {
            // Background gradient
            if !isCompact {
                LinearGradient(
                    colors: [Color(red: 0, green: 0.1, blue: 0.3), Color(red: 0, green: 0.3, blue: 0.8).opacity(0.3)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            // Three wave layers
            ForEach(0..<3, id: \.self) { i in
                WavePath(
                    phase: phase + CGFloat(i) * .pi * 0.6,
                    amplitude: waveHeight * (1.0 - CGFloat(i) * 0.2),
                    frequency: isCompact ? 2 : 1.5
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0, green: 0.3, blue: 0.8).opacity(0.5 - Double(i) * 0.1),
                            Color.cyan.opacity(0.3 - Double(i) * 0.05)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: waveWidth, height: isCompact ? 50 : 200)
                .offset(y: CGFloat(i) * (isCompact ? 6 : 25))
            }

            // Foam crests
            if !isCompact {
                WavePath(phase: phase + 0.5, amplitude: 12, frequency: 2)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: waveWidth, height: 200)
                    .offset(y: -10)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: isCompact ? 2 : 3).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// Wave shape path
private struct WavePath: Shape {
    var phase: CGFloat
    var amplitude: CGFloat
    var frequency: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let step = rect.width / 60

        path.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: rect.width, by: step) {
            let relativeX = x / rect.width
            let y = midY + sin(relativeX * .pi * 2 * frequency + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        // Close the path to fill below the wave
        path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Midnight
/// Starfield with twinkling stars, central moon glow, shooting star
struct MidnightEffect: View {
    let isCompact: Bool
    @State private var twinkle = false
    @State private var shootingStar = false

    private var starCount: Int { isCompact ? 12 : 40 }

    var body: some View {
        ZStack {
            // Deep purple background
            if !isCompact {
                RadialGradient(
                    colors: [Color(red: 0.15, green: 0.1, blue: 0.3), Color(red: 0.05, green: 0.05, blue: 0.15)],
                    center: .center, startRadius: 0, endRadius: 250
                )
            }

            // Stars
            ForEach(0..<starCount, id: \.self) { i in
                let seed = StarSeed(index: i, isCompact: isCompact)
                Circle()
                    .fill(Color.white)
                    .frame(width: seed.size, height: seed.size)
                    .opacity(twinkle ? seed.opacityA : seed.opacityB)
                    .position(x: seed.x, y: seed.y)
                    .animation(
                        .easeInOut(duration: seed.duration)
                            .repeatForever(autoreverses: true)
                            .delay(seed.delay),
                        value: twinkle
                    )
            }

            // Moon glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.6, green: 0.4, blue: 1).opacity(0.4),
                            Color(red: 0.3, green: 0.1, blue: 0.5).opacity(0.1),
                            .clear
                        ],
                        center: .center, startRadius: 0,
                        endRadius: isCompact ? 25 : 100
                    )
                )
                .frame(width: isCompact ? 50 : 200, height: isCompact ? 50 : 200)

            // Moon icon
            Image(systemName: "moon.stars.fill")
                .font(.system(size: isCompact ? 16 : 44, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.8, green: 0.7, blue: 1), Color(red: 0.6, green: 0.4, blue: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1).opacity(0.5), radius: isCompact ? 6 : 16)

            // Shooting star
            if !isCompact {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 60, height: 2)
                    .rotationEffect(.degrees(-35))
                    .offset(x: shootingStar ? 120 : -180, y: shootingStar ? 80 : -100)
                    .opacity(shootingStar ? 0 : 1)
                    .animation(
                        .easeIn(duration: 0.8)
                            .repeatForever(autoreverses: false)
                            .delay(3),
                        value: shootingStar
                    )
            }
        }
        .onAppear { twinkle = true; shootingStar = true }
    }
}

// Deterministic star positions from index (no random needed)
private struct StarSeed {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacityA: Double
    let opacityB: Double
    let duration: Double
    let delay: Double

    init(index: Int, isCompact: Bool) {
        let bounds: CGFloat = isCompact ? 70 : 350
        // Simple hash-like distribution
        let a = CGFloat((index * 137 + 53) % 100) / 100.0
        let b = CGFloat((index * 89 + 17) % 100) / 100.0
        x = a * bounds
        y = b * bounds
        size = isCompact ? CGFloat(1 + (index % 2)) : CGFloat(1.5 + Double(index % 3) * 1.0)
        opacityA = 0.3 + Double(index % 4) * 0.15
        opacityB = 0.7 + Double(index % 3) * 0.1
        duration = 1.5 + Double(index % 4) * 0.5
        delay = Double(index % 5) * 0.3
    }
}
