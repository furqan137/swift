import SwiftUI

// MARK: - Sender Card

struct SenderCard: View, Equatable {
    let sender: EmailSender
    let isUnsubscribed: Bool
    let isKept: Bool
    let isLoading: Bool
    let onKeep: () -> Void
    let onUnsubscribe: () -> Void

    static func == (lhs: SenderCard, rhs: SenderCard) -> Bool {
        lhs.sender.email == rhs.sender.email &&
        lhs.isUnsubscribed == rhs.isUnsubscribed &&
        lhs.isKept == rhs.isKept &&
        lhs.isLoading == rhs.isLoading
    }

    private var domain: String {
        // Extract domain from "user@subdomain.example.com" → "example.com"
        let parts = sender.email.split(separator: "@")
        guard parts.count == 2 else { return sender.email }
        let host = String(parts[1]).lowercased()
        let components = host.split(separator: ".")
        if components.count >= 2 {
            return components.suffix(2).joined(separator: ".")
        }
        return host
    }

    private var faviconURL: URL? {
        // Google's S2 favicon service — returns the company logo
        URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(domain)")
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Company logo / avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)

                    AsyncImage(url: faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        case .empty, .failure:
                            // Fallback: first letter over tinted background
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(avatarColor(for: sender.name).opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Text(String(sender.name.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(avatarColor(for: sender.name))
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(sender.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)
                    Text(sender.email)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(sender.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "78716C"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "F4F4F5")))
            }

            actionRow
        }
        .padding(16)
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

    @ViewBuilder
    private var actionRow: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                Text("Unsubscribing...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "A1A1AA"))
                Spacer()
            }
            .frame(height: 44)
        } else if isUnsubscribed {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "22C55E"))
                Text("Unsubscribed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "22C55E"))
                Spacer()
            }
            .frame(height: 44)
        } else if isKept {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "1C1917"))
                Text("Keeping")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                Spacer()
            }
            .frame(height: 44)
        } else {
            HStack(spacing: 12) {
                Button(action: onKeep) {
                    Text(BCLoc.keep.tr)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "F4F4F5"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                }

                Button(action: onUnsubscribe) {
                    Text("Unsubscribe")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "1C1917"))
                        )
                }
            }
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [
            Color(hex: "2563EB"), Color(hex: "7C3AED"), Color(hex: "D97706"),
            Color(hex: "059669"), Color(hex: "DC2626"), Color(hex: "0891B2")
        ]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Unsubscribe Confirmation Sheet

struct UnsubscribeConfirmSheet: View {
    let sender: EmailSender
    @Binding var trashExisting: Bool
    @Binding var skipFuture: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(hex: "B0B0B4"))
                .frame(width: 40, height: 5)
                .padding(.top, 14)
                .padding(.bottom, 28)

            // Title
            Text("Unsubscribe from this list?")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "1C1917"))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            // Subtitle
            VStack(spacing: 2) {
                Text("You will \(Text("no longer ").bold().foregroundColor(Color(hex: "57534E")))receive emails from")
                    .foregroundColor(Color(hex: "9B9490"))
                    .font(.system(size: 15))

                Text(sender.email)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "9B9490"))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)

            // Options — clean white background
            VStack(spacing: 12) {
                optionRow("Move all emails from this sender to Trash", isOn: $trashExisting)
                optionRow("Do not ask for confirmation again", isOn: $skipFuture)
            }
            .padding(.horizontal, 20)

            Spacer()

            // Buttons — dark Cancel + dark Unsubscribe (no blue)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                }

                Button(action: onConfirm) {
                    Text("Unsubscribe")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .preferredColorScheme(.light)
    }

    private func optionRow(_ text: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 14) {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.leading)

                Spacer()

                // Radio circle — black when selected, gray when off
                Circle()
                    .stroke(
                        isOn.wrappedValue ? Color(hex: "1C1917") : Color(hex: "C0C0C4"),
                        lineWidth: isOn.wrappedValue ? 7 : 2
                    )
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "F2F2F7").opacity(0.85))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Confirm Option Toggle (legacy compat)

struct ConfirmOption: View {
    let text: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: 14) {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.leading)

                Spacer()

                Circle()
                    .stroke(isOn ? Color(hex: "1C1917") : Color(hex: "C0C0C4"), lineWidth: isOn ? 7 : 2)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "F2F2F7").opacity(0.85))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
