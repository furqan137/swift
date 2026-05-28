import SwiftUI

// MARK: - Checkpoint Progress (yellow theme, start node + one per task)

struct GuidedCleanupCheckpointProgressView: View {
    let tasks: [CleanupTask]
    let isNodeComplete: (Int) -> Bool
    let isNodeActive: (Int) -> Bool

    private let honeyYellow = Color(hex: "FFC636")
    private let inactiveGrey = Color(hex: "D1D1D6")
    private let horizontalPadding: CGFloat = 24

    /// Node 0 is the session start; nodes 1…N map to cleanup tasks.
    private var nodeCount: Int { max(tasks.count, 0) + 1 }

    var body: some View {
        GeometryReader { geo in
            let innerWidth = max(geo.size.width - horizontalPadding * 2, 1)
            let nodeDiameter = min(
                28,
                max(14, (innerWidth * 0.6) / CGFloat(max(nodeCount, 1)))
            )

            HStack(spacing: 0) {
                ForEach(0..<nodeCount, id: \.self) { idx in
                    if idx > 0 {
                        progressLine(completed: isNodeComplete(idx))
                    }
                    progressNode(
                        index: idx,
                        task: idx > 0 ? tasks[idx - 1] : nil,
                        diameter: nodeDiameter,
                        isComplete: isNodeComplete(idx),
                        isActive: isNodeActive(idx)
                    )
                    .frame(width: nodeDiameter, height: nodeDiameter)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(width: geo.size.width, alignment: .center)
            // #region agent log
            .onAppear {
                AppDebugLog.write(
                    location: "GuidedCleanupCheckpointProgressView.onAppear",
                    message: "progress tracker rendered",
                    hypothesisId: "B-E",
                    data: [
                        "tasksCount": tasks.count,
                        "nodeCount": nodeCount,
                        "geoWidth": geo.size.width,
                        "innerWidth": innerWidth,
                        "nodeDiameter": nodeDiameter
                    ]
                )
            }
            // #endregion
        }
        .frame(height: 36)
        .clipped()
    }

    private func progressLine(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? honeyYellow : inactiveGrey)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
    }

    private func progressNode(
        index: Int,
        task: CleanupTask?,
        diameter: CGFloat,
        isComplete: Bool,
        isActive: Bool
    ) -> some View {
        ZStack {
            Circle()
                .fill(isComplete ? honeyYellow : inactiveGrey)

            if isActive && !isComplete {
                Circle()
                    .stroke(honeyYellow, lineWidth: max(2, diameter * 0.1))
            }

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.34, weight: .bold))
                    .foregroundColor(.black)
            } else {
                Image(systemName: index == 0 ? "play.fill" : (task?.icon ?? "flag.fill"))
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundColor(isActive ? honeyYellow : .white)
            }
        }
        .scaleEffect(isActive ? 1.0 : 0.88)
        .layoutPriority(2)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isComplete)
    }
}
