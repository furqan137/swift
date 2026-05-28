import SwiftUI

// MARK: - Segmented Meter View (15 Segments, No Text)
struct SegmentedMeterView: View {
    let filledCount: Int
    let waveIndices: [Int]
    let waveToken: Int

    // MARK: - Wave State
    @State private var waveScales: [Int: CGFloat] = [:]
    @State private var lastWaveToken: Int = 0

    // MARK: - Layout Constants
    private let segmentCount = 15
    private let segmentSpacing: CGFloat = 2.5
    private let segmentCornerRadius: CGFloat = 3

    // Colors
    private let trackColor = Color.black.opacity(0.35)
    private let fillGold = Color(hex: "D4A01C")
    private let fillGoldLight = Color(hex: "E8BF30")

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = segmentSpacing * CGFloat(segmentCount - 1)
            let segW = (geo.size.width - totalSpacing) / CGFloat(segmentCount)
            let segH = geo.size.height

            // Track background
            RoundedRectangle(cornerRadius: segmentCornerRadius + 2)
                .fill(trackColor)
                .frame(width: geo.size.width, height: segH)

            // Segments
            HStack(spacing: segmentSpacing) {
                ForEach(1...segmentCount, id: \.self) { index in
                    let filled = index <= filledCount
                    let waveScale = waveScales[index] ?? 1.0

                    RoundedRectangle(cornerRadius: segmentCornerRadius)
                        .fill(filled ? segmentGradient : clearGradient)
                        .frame(width: segW, height: segH * 0.7)
                        .scaleEffect(y: waveScale)
                        .animation(.easeOut(duration: 0.18), value: filledCount)
                }
            }
            .frame(width: geo.size.width, height: segH, alignment: .center)
        }
        .onChange(of: waveToken) { _, newToken in
            if newToken != lastWaveToken {
                lastWaveToken = newToken
                runWave()
            }
        }
    }

    private var segmentGradient: LinearGradient {
        LinearGradient(
            colors: [fillGoldLight, fillGold],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var clearGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Wave Animation
    private func runWave() {
        for (i, segIndex) in waveIndices.enumerated() {
            let delay = Double(i) * 0.06

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                    waveScales[segIndex] = 1.12
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.25) {
                withAnimation(.easeOut(duration: 0.15)) {
                    waveScales[segIndex] = 1.0
                }
            }
        }
    }
}
