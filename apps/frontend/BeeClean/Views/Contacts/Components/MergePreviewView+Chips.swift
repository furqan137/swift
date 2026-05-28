import SwiftUI

extension MergePreviewView {

    // MARK: - Confidence Dot

    func confidenceColor(_ c: DuplicateConfidence) -> Color {
        switch c {
        case .high:   return Color(hex: "22C55E")
        case .medium: return Color(hex: "F59E0B")
        case .low:    return Color(hex: "DC2626")
        }
    }

    // MARK: - Stat Pill

    func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color(hex: "78716C"))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(hex: "F4F4F5")))
    }

    // MARK: - Avatar

    @ViewBuilder
    func contactAvatar(_ contact: AppContact, size: CGFloat) -> some View {
        // ContactAvatarImage handles the JPEG/PNG decode on a userInitiated
        // background queue so scrolling the merge-preview chips list never
        // blocks main on UIImage(data:). Inline decode was firing per-row
        // per body invalidation and stuttering the scroll.
        if contact.hasThumbnail, let data = contact.thumbnailData {
            ContactAvatarImage(data: data, size: size)
        } else {
            ZStack {
                Circle()
                    .fill(avatarGradient(for: contact.fullName))
                    .frame(width: size, height: size)
                Text(contact.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    func avatarGradient(for name: String) -> LinearGradient {
        // Same muted Bitepal palette as ContactListView so the avatars
        // match identity across the duplicates list and merge preview.
        let hash = abs(name.hashValue)
        let colors: [(Color, Color)] = [
            (Color(hex: "C48B9F"), Color(hex: "A8707F")),
            (Color(hex: "D4A373"), Color(hex: "B8895C")),
            (Color(hex: "B5838D"), Color(hex: "9A6B74")),
            (Color(hex: "C9A96E"), Color(hex: "AE9058")),
            (Color(hex: "A8A0B5"), Color(hex: "8E869E")),
            (Color(hex: "B0A090"), Color(hex: "968878")),
        ]
        let pair = colors[hash % colors.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

}
