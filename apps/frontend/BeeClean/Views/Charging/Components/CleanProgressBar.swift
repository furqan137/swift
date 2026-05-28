import SwiftUI

// MARK: - Clean Progress Bar
/// Sleek segmented progress bar showing bee stage progression.
/// 5 segments matching the 5 bee stages (20% each).
struct CleanProgressBar: View {
    let progress: Double

    private let segmentCount = 5
    private let segmentSpacing: CGFloat = 3
    private let barHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = segmentSpacing * CGFloat(segmentCount - 1)
            let segmentWidth = (geo.size.width - totalSpacing) / CGFloat(segmentCount)

            HStack(spacing: segmentSpacing) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let segmentStart = Double(index) / Double(segmentCount)
                    let segmentEnd = Double(index + 1) / Double(segmentCount)
                    let fillAmount = segmentFill(progress: progress, start: segmentStart, end: segmentEnd)

                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: segmentWidth, height: barHeight)

                        // Fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(segmentWidth * fillAmount, fillAmount > 0 ? barHeight : 0), height: barHeight)
                            .shadow(color: Color.white.opacity(fillAmount > 0 ? 0.4 : 0), radius: 4, y: 0)
                    }
                }
            }
        }
        .frame(height: barHeight)
        .animation(.easeOut(duration: 0.6), value: progress)
    }

    private func segmentFill(progress: Double, start: Double, end: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        if clamped >= end { return 1.0 }
        if clamped <= start { return 0.0 }
        return (clamped - start) / (end - start)
    }
}

#Preview {
    ZStack {
        Color(hex: "4A90D9")
            .ignoresSafeArea()
        VStack(spacing: 20) {
            CleanProgressBar(progress: 0.0)
            CleanProgressBar(progress: 0.35)
            CleanProgressBar(progress: 0.6)
            CleanProgressBar(progress: 1.0)
        }
        .padding(40)
    }
}
