import SwiftUI

// MARK: - Storage Cleared line chart — Cal AI 2-line style
//
// Solid amber line = bytes cleared per bucket (the actual win).
// Dashed muted line = trailing average pace (the personal trend).
// Lines share a smoothed-curve renderer so the chart breathes;
// the best bucket lights up as a burnt-orange node so wins pop.
// Tap/drag for amount + relative date on the closest bucket.

struct ActivityLineChart: View {
    let values: [Double]
    let previousPeriod: [Double]
    let maxValue: Double
    let bestIndex: Int?
    @Binding var selectedIndex: Int?
    let xAxisLabels: [String]
    let tooltip: (value: String, when: String)
    /// User-selected color family for the line, area fill, shadow, and
    /// best marker. Defaults to `.honey` so legacy call sites stay
    /// visually identical.
    var palette: ChartPalette = .honey

    @State private var drawProgress: CGFloat = 0
    @State private var areaOpacity: Double = 0
    /// Tracks whether the current drag gesture has actually moved the
    /// selection to a new bar. Only commit-haptic on release if true.
    @State private var didScrub: Bool = false
    /// Edge-bump debounce. True while the finger is past the plot's
    /// leading or trailing edge and the selection has clamped at the
    /// boundary. Re-set to false the moment the finger comes back
    /// in-bounds so the next overshoot fires a fresh wall-bump.
    @State private var pastEdge: Bool = false
    /// Drives the pulsing halo on the rightmost "Now" anchor.
    @State private var nowPulse: Bool = false

    private let leftPad: CGFloat = 6
    private let rightPad: CGFloat = 6
    private let topPad: CGFloat = 40
    private let bottomPad: CGFloat = 24

    private var amber: Color     { palette.areaFillTop }
    private var amberDeep: Color { palette.lineEnd }
    private var bestColor: Color { palette.bestMarkerColor }

    var body: some View {
        GeometryReader { geo in
            let plotW = max(geo.size.width - leftPad - rightPad, 1)
            let plotH = max(geo.size.height - topPad - bottomPad, 1)
            let cnt = values.count
            let hasSelection = selectedIndex != nil
            let resolvedIndex = max(0, min(cnt - 1, selectedIndex ?? 0))

            ZStack {
                if cnt >= 2, maxValue > 0 {
                    // Static line + area rasterized via `.drawingGroup()`
                    // so drag-scrub updates (selectedIndex changes) don't
                    // re-rasterize the curve every frame.
                    ZStack {
                        primaryArea(plotW: plotW, plotH: plotH, cnt: cnt)
                            .opacity(areaOpacity)
                        primaryLine(plotW: plotW, plotH: plotH, cnt: cnt,
                                    progress: drawProgress)
                    }
                    .drawingGroup()

                    if !hasSelection, let bestIndex {
                        bestDayBadge(plotW: plotW, plotH: plotH,
                                     cnt: cnt, index: bestIndex)
                            .opacity(drawProgress > 0.92 ? 1 : 0)
                            .animation(.easeOut(duration: 0.32)
                                .delay(0.05), value: drawProgress)
                    }
                    if !hasSelection {
                        nowAnchor(plotW: plotW, plotH: plotH, cnt: cnt)
                            .opacity(drawProgress > 0.92 ? 1 : 0)
                    }
                    if hasSelection {
                        nodes(plotW: plotW, plotH: plotH, cnt: cnt,
                              selected: resolvedIndex)
                            .opacity(drawProgress > 0.85 ? 1 : 0)
                        selectionLayer(index: resolvedIndex, cnt: cnt,
                                       plotW: plotW, plotH: plotH)
                            .opacity(drawProgress > 0.85 ? 1 : 0)
                    }
                }

                xAxisLabelsLayer(plotW: plotW, geoH: geo.size.height)
            }
            .onAppear {
                triggerDrawIn()
                HapticManager.shared.prepareScrub()
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    nowPulse = true
                }
            }
            .onChange(of: cnt) { _, _ in triggerDrawIn() }
            .onChange(of: maxValue) { _, _ in triggerDrawIn() }
            .contentShape(Rectangle())
            .gesture(scrubGesture(plotW: plotW, cnt: cnt))
        }
    }

    /// Drag gesture extracted so the body chain stays inside Swift's
    /// view-builder type-check budget after the move to a standalone file.
    private func scrubGesture(plotW: CGFloat, cnt: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard cnt > 1 else { return }
                let step = plotW / CGFloat(cnt - 1)
                let rawX = g.location.x - leftPad
                let isOver = rawX < 0 || rawX > plotW
                let xInPlot = max(0, min(plotW, rawX))
                let idx = Int(round(xInPlot / step))
                let clamped = max(0, min(cnt - 1, idx))

                if clamped != selectedIndex {
                    let v = values.indices.contains(clamped) ? values[clamped] : 0
                    let norm = maxValue > 0 ? min(v / maxValue, 1.0) : 0
                    selectedIndex = clamped
                    HapticManager.shared.chartScrubTick(normalizedValue: norm)
                    didScrub = true
                    if !isOver { pastEdge = false }
                } else if isOver && !pastEdge {
                    HapticManager.shared.chartScrubEdgeBump()
                    pastEdge = true
                    didScrub = true
                } else if !isOver {
                    pastEdge = false
                }
            }
            .onEnded { _ in
                if didScrub {
                    HapticManager.shared.chartScrubCommit()
                    didScrub = false
                }
                pastEdge = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        selectedIndex = nil
                    }
                }
            }
    }

    private func triggerDrawIn() {
        drawProgress = 0
        areaOpacity = 0
        withAnimation(.easeOut(duration: 0.85)) {
            drawProgress = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
            areaOpacity = 1.0
        }
    }

    // MARK: Plotting helpers

    private func point(i: Int, value: Double,
                       plotW: CGFloat, plotH: CGFloat, cnt: Int) -> CGPoint {
        let stepX = cnt > 1 ? plotW / CGFloat(cnt - 1) : 0
        let x = leftPad + CGFloat(i) * stepX
        let frac = maxValue > 0 ? min(value / maxValue, 1) : 0
        let y = topPad + plotH - CGFloat(frac) * plotH
        return CGPoint(x: x, y: y)
    }

    /// Catmull-Rom-ish smoothing via midpoint quad curves — gives the
    /// soft Cal AI curve without overshoot.
    private func smoothPath(points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        if points.count == 1 { return p }
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = CGPoint(x: (prev.x + curr.x) / 2,
                              y: (prev.y + curr.y) / 2)
            p.addQuadCurve(to: mid, control: prev)
            p.addQuadCurve(to: curr, control: curr)
        }
        return p
    }

    // MARK: Primary series

    private func primaryPoints(plotW: CGFloat, plotH: CGFloat, cnt: Int) -> [CGPoint] {
        (0..<cnt).map { i in
            point(i: i, value: values[i], plotW: plotW, plotH: plotH, cnt: cnt)
        }
    }

    private func primaryArea(plotW: CGFloat, plotH: CGFloat, cnt: Int) -> some View {
        let pts = primaryPoints(plotW: plotW, plotH: plotH, cnt: cnt)
        var path = smoothPath(points: pts)
        let baselineY = topPad + plotH
        if let last = pts.last, let first = pts.first {
            path.addLine(to: CGPoint(x: last.x, y: baselineY))
            path.addLine(to: CGPoint(x: first.x, y: baselineY))
            path.closeSubpath()
        }
        return path.fill(
            LinearGradient(
                colors: [amber.opacity(0.40), amber.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func primaryLine(plotW: CGFloat, plotH: CGFloat, cnt: Int,
                             progress: CGFloat) -> some View {
        let pts = primaryPoints(plotW: plotW, plotH: plotH, cnt: cnt)
        return smoothPath(points: pts)
            .trim(from: 0, to: max(progress, 0.001))
            .stroke(
                LinearGradient(
                    colors: [amberDeep, amber],
                    startPoint: .leading, endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3,
                                   lineCap: .round, lineJoin: .round)
            )
            .shadow(color: amber.opacity(0.45), radius: 6, y: 3)
    }

    // MARK: Nodes — Cal AI minimalism

    private func nodes(plotW: CGFloat, plotH: CGFloat,
                       cnt: Int, selected: Int) -> some View {
        ZStack {
            if selected >= 0 && selected < cnt {
                let pt = point(i: selected, value: values[selected],
                               plotW: plotW, plotH: plotH, cnt: cnt)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .position(pt)
                    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
                Circle()
                    .fill(amber)
                    .frame(width: 8, height: 8)
                    .position(pt)
                    .shadow(color: amber.opacity(0.55), radius: 4)
            }
        }
    }

    // MARK: "Now" anchor — Robinhood-style "you are here" dot

    private func nowAnchor(plotW: CGFloat, plotH: CGFloat, cnt: Int) -> some View {
        let lastIndex = cnt - 1
        let v = values.indices.contains(lastIndex) ? values[lastIndex] : 0
        let pt = point(i: lastIndex, value: v,
                       plotW: plotW, plotH: plotH, cnt: cnt)
        return ZStack {
            Circle()
                .fill(amberDeep.opacity(0.32))
                .frame(width: 16, height: 16)
                .scaleEffect(nowPulse ? 1.55 : 0.9)
                .opacity(nowPulse ? 0 : 0.85)
                .position(pt)
            Circle()
                .fill(amberDeep)
                .frame(width: 7, height: 7)
                .shadow(color: amberDeep.opacity(0.65), radius: 4)
                .position(pt)
        }
    }

    // MARK: Best-day badge

    private func bestDayBadge(plotW: CGFloat, plotH: CGFloat,
                              cnt: Int, index: Int) -> some View {
        let v = values.indices.contains(index) ? values[index] : 0
        let pt = point(i: index, value: v,
                       plotW: plotW, plotH: plotH, cnt: cnt)
        return Text("BEST")
            .font(.custom("Poppins-Bold", size: 9))
            .tracking(0.9)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(bestColor.opacity(0.95))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: bestColor.opacity(0.4), radius: 5, y: 2)
            .position(x: pt.x, y: max(pt.y - 16, topPad - 4))
    }

    // MARK: Selection + tooltip

    private func selectionLayer(index: Int, cnt: Int,
                                plotW: CGFloat, plotH: CGFloat) -> some View {
        let v = values.indices.contains(index) ? values[index] : 0
        let pt = point(i: index, value: v,
                       plotW: plotW, plotH: plotH, cnt: cnt)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: pt.x, y: topPad))
                p.addLine(to: CGPoint(x: pt.x, y: topPad + plotH))
            }
            .stroke(Color(hex: "1C1917").opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            tooltipBubble
                .position(
                    x: max(leftPad + 60, min(leftPad + plotW - 60, pt.x)),
                    y: 22
                )
        }
    }

    private var tooltipBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tooltip.value)
                .font(.custom("Poppins-Bold", size: 13))
                .foregroundColor(.white)
            Text(tooltip.when)
                .font(.custom("Poppins-Medium", size: 9.5))
                .tracking(0.3)
                .foregroundColor(Color.white.opacity(0.65))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "1C1917"))
        )
        .fixedSize()
    }

    private func xAxisLabelsLayer(plotW: CGFloat, geoH: CGFloat) -> some View {
        ZStack {
            ForEach(Array(xAxisLabels.enumerated()), id: \.offset) { i, label in
                let stepX = plotW / CGFloat(max(xAxisLabels.count - 1, 1))
                let labelX = xAxisLabels.count == 1
                    ? leftPad + plotW / 2
                    : leftPad + CGFloat(i) * stepX
                Text(label)
                    .font(.custom("Poppins-Medium", size: 10))
                    .foregroundColor(Color(hex: "A8A29E"))
                    .position(x: labelX, y: geoH - 8)
            }
        }
    }
}
