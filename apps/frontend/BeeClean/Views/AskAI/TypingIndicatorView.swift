import SwiftUI

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var dotOffset: CGFloat = 0

    private var maxBubbleWidth: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393) * 0.7
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: "A1A1AA"))
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffset(for: index))
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                            value: dotOffset
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Color.white)
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: maxBubbleWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { dotOffset = 1 }
    }

    private func dotOffset(for index: Int) -> CGFloat {
        dotOffset == 0 ? 0 : -4
    }
}
