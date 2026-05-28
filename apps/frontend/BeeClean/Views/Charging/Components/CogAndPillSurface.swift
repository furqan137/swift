import SwiftUI

// MARK: - Futuristic Cog Glyph
//
// Custom 8-tooth cog with razor-sharp triangular teeth — replaces the
// SF Symbol `gearshape` which reads as a soft generic icon. The path is
// drawn at the unit circle and scaled by the host so it stays crisp
// at any size without font hinting drift.
//
// Geometry: 8 teeth means 16 vertices around the rim (tip + valley
// alternating), with a circular bore in the middle. Sharp teeth make
// the icon feel mechanical / sci-fi rather than "settings widget."
struct FuturisticCogGlyph: View {
    var size: CGFloat = 17
    var stroke: AnyShapeStyle
    var lineWidth: CGFloat = 1.4

    var body: some View {
        CogShape(toothCount: 8, toothDepth: 0.18, boreRadius: 0.26)
            .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .miter, miterLimit: 4))
            .frame(width: size, height: size)
    }
}

struct CogShape: Shape {
    var toothCount: Int = 8
    /// Tooth height as a fraction of the outer radius (0..1).
    var toothDepth: CGFloat = 0.18
    /// Inner bore radius as a fraction of the outer radius.
    var boreRadius: CGFloat = 0.26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * (1 - toothDepth)
        let bore = outerR * boreRadius

        let pointsPerTooth = 4   // tip-out, valley-in, valley-in, tip-out
        let totalPoints = toothCount * pointsPerTooth
        let angleStep = (CGFloat.pi * 2) / CGFloat(totalPoints)
        // Start at -90° so the first tooth points up.
        let startAngle: CGFloat = -.pi / 2

        for i in 0..<totalPoints {
            // Pattern: tooth tip (outer) → tooth tip (outer) → valley
            // (inner) → valley (inner) → repeat. This makes each tooth
            // a flat-topped trapezoid rather than a triangle, which
            // reads as more mechanical / engineered.
            let phase = i % 4
            let radius: CGFloat = (phase == 0 || phase == 1) ? outerR : innerR
            let angle = startAngle + CGFloat(i) * angleStep
            let pt = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()

        // Inner bore — concentric circle, even-odd fill rule when
        // filled would knock it out. We're stroking, so it just draws
        // as a circle outline inside the cog.
        p.addEllipse(in: CGRect(
            x: center.x - bore,
            y: center.y - bore,
            width: bore * 2,
            height: bore * 2
        ))

        return p
    }
}

// MARK: - Futuristic Pill Surface
//
// Shared chrome-glass pill used by both the StreakBadge and the
// settings cog button — gives the two top-bar elements a unified
// "lifted glass" feel that reads as crafted hardware rather than
// flat painted UI.
//
// Stack (bottom up):
//   1. Body gradient — a top-bright, bottom-darker linear ramp gives
//      the pill the impression of a curved 3D surface lit from above.
//   2. Inner shadow at the bottom edge — drawn by stroking the
//      capsule with a subtle dark line and blurring it inward. Adds
//      "depth" so the pill reads as recessed slightly into the canvas
//      around it instead of pasted on flat.
//   3. Top rim highlight — a very thin bright stroke along the top
//      half of the capsule edge. This is the single most effective
//      "premium product" cue.
//   4. Outer hairline — keeps the silhouette crisp regardless of
//      what's behind it.
//   5. Stacked drop shadows — tight definition + wide ambient lift.
//
// Theme-aware: in night mode the body gradient flips to a deep warm
// ink, the rim highlight uses a gold tint, and the shadows get
// stronger to keep the pill readable on a dark background.
struct FuturisticPillSurface: View {
    var isNight: Bool

    var body: some View {
        ZStack {
            // 1. Body gradient.
            Capsule()
                .fill(
                    isNight
                        ? AnyShapeStyle(LinearGradient(
                            colors: [
                                Color(hex: "23201B"),
                                Color(hex: "0E0C0A")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        : AnyShapeStyle(LinearGradient(
                            colors: [
                                Color.white,
                                Color(hex: "EDEAE3")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )

            // 2. Inner shadow at bottom edge — gives the pill the
            //    impression of a 3D wall curving inward.
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(isNight ? 0.55 : 0.10)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .blur(radius: 0.8)

            // 3. Top rim highlight — bright thin stroke along the
            //    upper half. The "lit from above" cue.
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            isNight
                                ? Color(hex: "FFE5A5").opacity(0.55)
                                : Color.white.opacity(0.95),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.8
                )
                .blendMode(.plusLighter)

            // 4. Outer hairline silhouette.
            Capsule()
                .stroke(
                    isNight
                        ? Color(hex: "F0D58A").opacity(0.22)
                        : Color.black.opacity(0.10),
                    lineWidth: 0.5
                )
        }
    }
}

