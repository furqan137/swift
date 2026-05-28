import SwiftUI

struct HoneycombMeterView: View {
    @ObservedObject var vm: BeeViewModel
    @State private var animatedCells = 0
    @State private var dripScale: CGFloat = 0.7
    @State private var lastRewardToken = 0

    var body: some View {
        GeometryReader { geo in
            let cellSize = min((geo.size.width - 24) / 5.0, geo.size.height * 1.65)
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    HoneyCellView(
                        isFilled: index < vm.filledCells,
                        isActive: index == min(vm.filledCells, 4),
                        partialProgress: partialProgress(for: index),
                        highlight: vm.rewardPulse == .cellFilled(index + 1) || (vm.rewardPulse == .hiveComplete && index == 4)
                    )
                    .frame(width: cellSize, height: cellSize * 0.95)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if vm.dripActive && vm.filledCells == 0 {
                    HoneyDripIndicator()
                        .offset(y: -10)
                        .scaleEffect(dripScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                dripScale = 1.02
                            }
                        }
                }
            }
        }
        .onAppear { animatedCells = vm.filledCells }
        .onChange(of: vm.rewardToken) { _, token in
            guard token != lastRewardToken else { return }
            lastRewardToken = token
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                animatedCells = vm.filledCells
            }
        }
    }

    private func partialProgress(for index: Int) -> Double {
        if index < vm.filledCells { return 1 }
        if index == vm.filledCells { return vm.currentCellProgress }
        return 0
    }
}

private struct HoneyCellView: View {
    let isFilled: Bool
    let isActive: Bool
    let partialProgress: Double
    let highlight: Bool

    var body: some View {
        ZStack {
            HexagonShape()
                .fill(Color.black.opacity(0.28))
            HexagonShape()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            GeometryReader { geo in
                let fillHeight = geo.size.height * CGFloat(max(0.06, partialProgress))
                VStack {
                    Spacer(minLength: 0)
                    HexagonShape()
                        .fill(LinearGradient(colors: [Color(hex: "F8DA56"), Color(hex: "D59A12")], startPoint: .top, endPoint: .bottom))
                        .frame(height: fillHeight)
                        .mask(alignment: .bottom) {
                            HexagonShape().frame(width: geo.size.width, height: geo.size.height)
                        }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if highlight {
                HexagonShape()
                    .stroke(Color(hex: "F9E27C").opacity(0.9), lineWidth: 2.2)
                    .shadow(color: Color(hex: "F9E27C").opacity(0.8), radius: 10)
            } else if isActive {
                HexagonShape()
                    .stroke(Color(hex: "D59A12").opacity(0.45), lineWidth: 1.4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(highlight ? 1.05 : 1.0)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: highlight)
    }
}

private struct HoneyDripIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HoneyDropShape()
                    .fill(LinearGradient(colors: [Color(hex: "F8DA56"), Color(hex: "D59A12")], startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 14)
            }
        }
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let dx = w * 0.25
        var path = Path()
        path.move(to: CGPoint(x: dx, y: 0))
        path.addLine(to: CGPoint(x: w - dx, y: 0))
        path.addLine(to: CGPoint(x: w, y: h / 2))
        path.addLine(to: CGPoint(x: w - dx, y: h))
        path.addLine(to: CGPoint(x: dx, y: h))
        path.addLine(to: CGPoint(x: 0, y: h / 2))
        path.closeSubpath()
        return path
    }
}
