import SwiftUI

extension CompressionDetailView {

    // MARK: - Custom Header — mirrors PhotoCompressionDetailView
    var customHeader: some View {
        HStack {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                if activeIsCompressing {
                    engine.cancel()
                } else if let result = engine.result {
                    try? FileManager.default.removeItem(at: result.outputURL)
                }
                BottomNavBarVisibility.shared.releaseHide()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: "EEEDF3")))
                    .contentShape(Rectangle())
            }

            Text("Video Compress")
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(Color(hex: "1C1917"))
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 20)
        // Bumped from 8 → 24 so the title doesn't crowd the dynamic
        // island / status-bar safe area on iPhone 14 Pro+.
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    // MARK: - Backdrop
    //
    // Bitepal-mirrored cool gradient — matches CompressView so the list
    // and detail share one continuous canvas. Replaces the prior warm
    // cream backdrop that drifted away from the entry screen's palette.
    var glassBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

}
