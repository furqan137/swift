import SwiftUI

// MARK: - Indexing Progress Bar
struct IndexingProgressBar: View {
    @ObservedObject var indexingService: IndexingService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(indexingService.statusLine)
                    .font(.caption)
                    .foregroundColor(Color(hex: "A1A1AA"))
                Spacer()
                if case .inProgress(_, let progress) = indexingService.state, progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }

            if case .inProgress(_, let progress) = indexingService.state, progress > 0 {
                ProgressView(value: progress)
                    .tint(Color(hex: "1C1917"))
            } else {
                ProgressView()
                    .tint(Color(hex: "1C1917"))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }
}
