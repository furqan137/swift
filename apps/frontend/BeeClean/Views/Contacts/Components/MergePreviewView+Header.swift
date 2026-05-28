import SwiftUI
import Contacts

extension MergePreviewView {

    // MARK: - Header

    var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(hex: "EEEDF3")))
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicates")
                    .font(.custom("Poppins-Bold", size: 30))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("\(totalMergedContacts) Contact\(totalMergedContacts == 1 ? "" : "s")")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .contentTransition(.numericText(countsDown: false))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            // Tightened from 16 → 6. Combined with the scroll's `.padding(.top, 8)`
            // below, the merged card now sits right under the "1 Contact"
            // subtitle instead of floating in 38pt of dead space.
            .padding(.bottom, 6)
        }
    }

}
