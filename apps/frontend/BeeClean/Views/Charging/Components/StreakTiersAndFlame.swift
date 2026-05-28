import SwiftUI

// MARK: - Streak Tiers

enum StreakTier {
    case starter, building, momentum, fire, legendary

    static func from(_ streak: Int) -> StreakTier {
        if streak >= 30 { return .legendary }
        if streak >= 14 { return .fire }
        if streak >= 7  { return .momentum }
        if streak >= 3  { return .building }
        return .starter
    }

    var icon: String {
        switch self {
        case .starter:   return "flame"
        case .building:  return "flame.fill"
        case .momentum:  return "bolt.fill"
        case .fire:      return "bolt.horizontal.fill"
        case .legendary: return "crown.fill"
        }
    }

    var filledDots: Int {
        switch self {
        case .starter:   return 1
        case .building:  return 2
        case .momentum:  return 3
        case .fire:      return 4
        case .legendary: return 5
        }
    }
}

// MARK: - Streak Flame Glyph
//
// Three-layer flame: outer halo glow, mid-orange body, hot white-yellow
// core. Each layer is the same `FlameShape` path drawn at progressively
// smaller scale, so the silhouette reads as a single coherent flame
// while the layered fills give the depth of an actual burning flame
// rather than a flat icon.
//
// Layer composition:
//   1. Halo  — soft amber glow blurred behind the body, gives the
//      "this thing is emitting light" cue.
//   2. Body  — the main flame fill. Radial gradient from a yellow-hot
//      lower lobe up to an orange tip.
//   3. Core  — small inner flame, white-hot center fading to
//      transparent. Drawn with .plusLighter so it adds light without
//      over-saturating the body color.
//   4. Spark — a tiny bright dot above the apex, suggesting a flying
//      ember. Subtle, but it's the detail that makes the icon feel
//      alive instead of static.
//
// At 14 pt the result reads as a glowing micro-flame — distinctly more
// "futuristic / unreal" than the SF Symbol cartoon flame.
struct StreakFlameGlyph: View {
    var size: CGFloat = 14
    /// Outer flame body gradient (yellow-orange → amber).
    var bodyGradient: LinearGradient
    /// Halo glow color (typically amber).
    var haloColor: Color
    /// Whether to draw the inner white-hot core. Off in low-contrast
    /// contexts (e.g. day mode where the white core blows out the body).
    var showCore: Bool = true

    var body: some View {
        ZStack {
            // 1. Halo — soft glow behind the flame. Slightly larger than
            //    the body so it reads as light bleeding past the
            //    silhouette edge.
            FlameShape()
                .fill(haloColor)
                .frame(width: size * 1.35, height: size * 1.45)
                .blur(radius: size * 0.28)
                .opacity(0.75)

            // 2. Body — the main flame.
            FlameShape()
                .fill(bodyGradient)
                .frame(width: size, height: size * 1.10)

            // 3. Core — white-hot center, lifted toward the lower lobe
            //    where a real flame's combustion zone is hottest.
            if showCore {
                FlameShape()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(hex: "FFF1B8").opacity(0.45),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.5, y: 0.78),
                            startRadius: 0,
                            endRadius: size * 0.55
                        )
                    )
                    .frame(width: size * 0.62, height: size * 0.76)
                    .offset(y: size * 0.18)
                    .blendMode(.plusLighter)
            }

            // 4. Spark — tiny ember floating above the apex. A single
            //    blurred dot offset slightly off-center gives the
            //    micro-detail that makes the icon feel alive.
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: size * 0.10, height: size * 0.10)
                .blur(radius: 0.6)
                .offset(x: -size * 0.08, y: -size * 0.78)
                .blendMode(.plusLighter)
        }
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Bottom center.
        p.move(to: CGPoint(x: w * 0.5, y: h))
        // Sweep left up to the apex with a slight inward pinch on the
        // way (gives the flame its characteristic "wisp").
        p.addCurve(
            to: CGPoint(x: w * 0.05, y: h * 0.55),
            control1: CGPoint(x: w * 0.10, y: h * 0.95),
            control2: CGPoint(x: w * -0.05, y: h * 0.78)
        )
        // Up to the apex (top point of the flame).
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.18, y: h * 0.30),
            control2: CGPoint(x: w * 0.30, y: h * 0.10)
        )
        // Right side — slightly narrower so the flame leans subtly.
        p.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.55),
            control1: CGPoint(x: w * 0.72, y: h * 0.10),
            control2: CGPoint(x: w * 0.85, y: h * 0.32)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * 1.05, y: h * 0.78),
            control2: CGPoint(x: w * 0.90, y: h * 0.95)
        )
        p.closeSubpath()
        return p
    }
}

