import SwiftUI

// MARK: - Contact Row View
struct ContactRowView: View {
    let contact: AppContact
    let isSelected: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                HapticManager.shared.selection()
                onToggle()
            }) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(hex: "1C1917") : Color(hex: "DDD8D3"), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "1C1917"))
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .buttonStyle(.plain)

            // Avatar + Info
            Button(action: {
                HapticManager.shared.buttonTap()
                onTap()
            }) {
                HStack(spacing: 12) {
                    // Avatar
                    if contact.hasThumbnail, let data = contact.thumbnailData {
                        ContactAvatarImage(data: data, size: 42)
                    } else {
                        ZStack {
                            Circle()
                                .fill(avatarGradient)
                                .frame(width: 42, height: 42)
                            Text(contact.initials)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.fullName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "1A1A1A"))
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let phone = contact.phoneNumbers.first {
                                HStack(spacing: 3) {
                                    Image(systemName: "phone.fill").font(.system(size: 9))
                                    Text(phone).font(.system(size: 12))
                                }
                                .foregroundColor(Color(hex: "9B9490"))
                                .lineLimit(1)
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: "phone.fill").font(.system(size: 9))
                                    Text("No phone").font(.system(size: 12))
                                }
                                .foregroundColor(Color(hex: "C5C0BB"))
                            }

                            if let email = contact.emails.first {
                                HStack(spacing: 3) {
                                    Image(systemName: "envelope.fill").font(.system(size: 9))
                                    Text(email).font(.system(size: 12))
                                }
                                .foregroundColor(Color(hex: "9B9490"))
                                .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "9B9490").opacity(0.4))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    private var avatarGradient: LinearGradient {
        let hash = abs(contact.fullName.hashValue)
        let colors: [(Color, Color)] = [
            (Color(hex: "4A90D9"), Color(hex: "2563B0")),
            (Color(hex: "8B5CF6"), Color(hex: "6D28D9")),
            (Color(hex: "D97BB5"), Color(hex: "B0477A")),
            (Color(hex: "2EC4A2"), Color(hex: "1A9B7E")),
            (Color(hex: "E5930E"), Color(hex: "C47A0A")),
            (Color(hex: "E8453C"), Color(hex: "C23028"))
        ]
        let pair = colors[hash % colors.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
