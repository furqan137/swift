import SwiftUI

// MARK: - Cleanup History ("View All")
//
// Pushed full-screen activity history for completed cleanup tasks, grouped by
// day with per-day totals. Game-like / workout-history feel, in the BeeClean
// design language. Reads from CleanupTaskManager (backend-backed).

struct CleanupHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [DayGroup] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if loaded && groups.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            ForEach(groups) { group in
                                daySection(group)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            groups = await CleanupTaskManager.shared.historyGroupedByDay()
            loaded = true
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text("Cleanup History")
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(.primary)

            HStack {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                .buttonStyle(ScaleButtonStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Day section

    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.label)
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(Color.foreground)
                Spacer()
                summaryChip(group)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.taskNumber) { index, item in
                    historyRow(item)
                    if index != group.items.count - 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 46)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
            )
        }
    }

    private func summaryChip(_ group: DayGroup) -> some View {
        HStack(spacing: 8) {
            Text(TodaysCleanupCard.mbText(group.totalMB))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(Color.mutedForeground)
            HStack(spacing: 2) {
                Image(systemName: "centsign.circle.fill")
                Text("+\(group.totalCoins)")
            }
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "C4850A"))
            Text("· \(group.count) task\(group.count == 1 ? "" : "s")")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.mutedForeground.opacity(0.7))
        }
    }

    // MARK: - Row

    private func historyRow(_ item: CompletedCleanupTask) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor(for: TodaysCleanupCard.category(from: item.category)).opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(iconColor(for: TodaysCleanupCard.category(from: item.category)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.foreground)
                Text(timeText(item))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.mutedForeground.opacity(0.7))
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TodaysCleanupCard.mbText(item.mbReviewed))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.foreground)
                HStack(spacing: 2) {
                    Image(systemName: "centsign.circle.fill")
                    Text("+\(item.coinsEarned)")
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "C4850A"))
            }
        }
        .padding(.vertical, 10)
    }

    private func timeText(_ item: CompletedCleanupTask) -> String {
        guard let date = item.completedDate else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(Color(hex: "C4850A").opacity(0.6))
            Text("No cleanups yet")
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(Color.foreground)
            Text("Finish a cleanup task and it'll show up here.")
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundColor(Color.mutedForeground)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconColor(for category: CleanupTaskCategory) -> Color {
        switch category {
        case .duplicatePhotos: return .categorySky
        case .similarPhotos: return .categoryViolet
        case .similarScreenshots: return .categoryTeal
        case .screenshots: return .categoryAmber
        case .blurryPhotos: return .categoryRose
        case .similarVideos: return .categoryCrimson
        case .screenRecordings: return .categoryIndigo
        case .shortRecordings: return .categoryMint
        case .longVideos: return .categoryCocoa
        case .otherPhotos: return .categorySlate
        case .promoEmails: return .categorySlate
        }
    }
}
