import SwiftUI

// MARK: - Settings Divider
//
// Hairline that starts after the icon-tile column so the icons stack
// cleanly down the left edge and the divider visually separates only
// the title regions. Width matches the new Bitepal row metrics
// (16pt horizontal padding + 38pt icon tile + 14pt spacing = 68pt).
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 0.5)
            .padding(.leading, 68)
    }
}

// MARK: - Clean Row
struct CleanRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "78716C"))
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "1C1917"))

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "D4D4D8"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - About Us View
struct AboutUsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                BeeMascot(.hero, .happy)
                    .padding(.top, 40)

                Text("BeeClean")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("Your all-in-one device cleanup companion. Clean contacts, emails, photos, and storage — all in one place.")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "78716C"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
        .preferredColorScheme(.light)
        .navigationTitle("About Us")
        .navigationBarTitleDisplayMode(.inline)
    }
}
