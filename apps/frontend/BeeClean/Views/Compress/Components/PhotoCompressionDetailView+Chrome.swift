import SwiftUI
import Photos

extension PhotoCompressionDetailView {

    // MARK: - Custom Header
    //
    // Inline header (back button + title) rendered in the content layer
    // instead of the system toolbar so we don't get iOS's translucent
    // material chip behind the chevron. Mirrors SettingsView exactly.
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

            Text("Photo Compress")
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
    // Bitepal-mirrored cool gradient — same stops as CompressView /
    // ContactsView / Settings so the list and the detail share one
    // continuous canvas. The previous WarmGoldBackdrop drifted the
    // detail view into a warmer cream that didn't match the entry
    // screen the user came from.
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

