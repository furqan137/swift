import SwiftUI
import Contacts

// MARK: - My Card Section
struct MyCardSection: View {
    let phoneNumber: String
    let myContact: AppContact?
    let phoneLookup: PhoneLookupResult?
    let isLookupLoading: Bool
    let onEditPhone: () -> Void

    private var displayName: String {
        myContact?.fullName ?? "My Number"
    }

    var body: some View {
        Button(action: onEditPhone) {
            HStack(spacing: 14) {
                // Avatar
                avatarView

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(phoneLookup?.internationalFormat ?? phoneNumber)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Color(hex: "A1A1AA"))

                        if isLookupLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "A1A1AA")))
                                .scaleEffect(0.45)
                        } else if let result = phoneLookup, !result.numberType.isEmpty {
                            Text(result.numberType)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "1C1917"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "1C1917").opacity(0.1))
                                )
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "A1A1AA").opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Avatar
    @ViewBuilder
    private var avatarView: some View {
        // ContactAvatarImage decodes the thumbnail JPEG/PNG off the
        // main thread so the section header doesn't stall during a
        // body re-render. The previous inline UIImage(data:) blocked
        // main every time the parent invalidated.
        if let contact = myContact, contact.hasThumbnail,
           let imgData = contact.thumbnailData {
            ContactAvatarImage(data: imgData, size: 40)
        } else {
            ZStack {
                Circle()
                    .fill(Color(hex: "1C1917").opacity(0.1))
                    .frame(width: 40, height: 40)

                if let contact = myContact {
                    Text(contact.initials)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "1C1917"))
                }
            }
        }
    }
}
