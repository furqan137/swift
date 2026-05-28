import SwiftUI

// MARK: - Compact Email Row (glass polished card, category-tinted)
/// Performance-optimized: uses shared formatters, minimal view hierarchy, equatable check.
/// `accent` is the category color — drives the avatar tint, unread rail, hairline,
/// background wash, and unread dot so every list reads as one cohesive surface.
struct CompactEmailRow: View, Equatable {
    let message: EmailMessage
    let isSelected: Bool
    let accent: Color
    let onToggle: () -> Void
    let onTap: () -> Void

    static func == (lhs: CompactEmailRow, rhs: CompactEmailRow) -> Bool {
        lhs.message.id == rhs.message.id && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(spacing: 14) {
            // Selection chip — soft lavender resting state, accent
            // fill when on. Same chrome family as the back-button +
            // dismiss-X chips so the whole app shares one tap-target
            // language.
            Button(action: {
                HapticManager.shared.selection()
                onToggle()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? accent : Color(hex: "EEEDF3"))
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 0.6)
                            .frame(width: 22, height: 22)
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            avatarBadge

            // Text stack — generous vertical breathing room, premium
            // weight ramp from Poppins-Bold 16 down through espresso
            // semibold 14 down to warm-gray 12.5.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(message.senderName)
                        .font(.custom("Poppins-Bold", size: 16))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)
                        .kerning(-0.1)

                    Spacer(minLength: 4)

                    if let date = message.date {
                        Text(EmailFormatters.shortDate(date))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "A8A29E"))
                            .monospacedDigit()
                    }
                }

                Text(message.subject)
                    .font(.system(size: 14, weight: message.isRead ? .semibold : .bold))
                    .foregroundColor(message.isRead ? Color(hex: "44403C") : Color(hex: "1C1917"))
                    .lineLimit(1)

                Text(EmailFormatters.cleanSnippet(message.snippet))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(Color(hex: "A8A29E"))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(cardSurface)
        .overlay(unreadEdgeMarker, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            HapticManager.shared.buttonTap()
            onTap()
        }
    }

    // MARK: - Card Surface (Premium Bitepal)
    //
    // Pure white body with a HAIR of cool vertical depth — barely-
    // there ramp (white → #F8F9FB, neutral cool gray) so the card
    // has a real surface gradient under the eye but reads as plain
    // white at a glance. The previous gold/cream stops drifted the
    // card warm against Bitepal's cool-gray canvas — felt off in a
    // dense list. Hairline border, top rim-light, stacked shadows
    // for the "lit-from-above" cue stay; only the body color
    // temperature changes from warm to neutral.
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(hex: "F8F9FB"), Color(hex: "EEF0F4")]
                            : [Color.white, Color(hex: "F8F9FB")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Top rim-light — single most effective premium cue.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.8
            )
            .blendMode(.plusLighter)

            // Outer hairline silhouette. Picks up the category accent
            // when selected so the marked state reads at a glance.
            shape.stroke(
                isSelected ? accent.opacity(0.40) : Color.black.opacity(0.06),
                lineWidth: isSelected ? 1.0 : 0.5
            )
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
        .shadow(color: Color.black.opacity(0.07), radius: 14, y: 6)
    }

    // MARK: - Unread Edge Marker
    //
    // Leading 3pt rail in the category accent — but ONLY when the
    // message is unread. Read messages get no rail, which lets the
    // user's eye scan straight down to what actually needs
    // attention. Top-to-bottom accent gradient + a soft sideways
    // halo gives the bar a sense of emitting category color.
    @ViewBuilder
    private var unreadEdgeMarker: some View {
        if !message.isRead {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3.5)
                .padding(.vertical, 12)
                .padding(.leading, 1)
                .shadow(color: accent.opacity(0.35), radius: 3, x: 1, y: 0)
        }
    }

    // MARK: - Avatar
    /// Premium 44pt monogram tile. Three-layer build:
    ///   1. Top → bottom gradient body (jewel-tone)
    ///   2. Inner top highlight ring (white 0.5 → 0, plusLighter) —
    ///      reads as a polished bevel catching light from above
    ///   3. Soft glow shadow in the tile's own color so the avatar
    ///      visibly sits on the card surface like a real chip
    private var avatarBadge: some View {
        let (top, bottom) = Self.avatarGradient(for: message.senderName)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Text(String(message.senderName.prefix(1)).uppercased())
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [top, bottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Inner top highlight — bright thin stroke along
                    // the upper half of the tile. The single most
                    // effective "premium hardware" cue.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)

                    // Bottom inner shadow — dark thin stroke along
                    // the lower half. Pairs with the top rim-light to
                    // imply real edge thickness.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )

                    // Hairline outer silhouette in the tile's own
                    // dark stop — keeps the colored chip crisp
                    // against the white card surface.
                    shape.stroke(bottom.opacity(0.40), lineWidth: 0.5)
                }
            )
            // Colored glow + tight definition shadow. The glow
            // radius/opacity is tuned per dark-stop so dark jewel
            // tones get a stronger throw than bright ones — keeps
            // the visual weight balanced across senders.
            .shadow(color: bottom.opacity(0.40), radius: 6, y: 3)
            .shadow(color: bottom.opacity(0.18), radius: 1.5, y: 1)
    }

    // MARK: - Per-sender avatar palette
    /// Curated deep-jewel two-stop gradients. Deliberately dialed back from
    /// pure saturation so a dense list reads refined, not candy-colored.
    private static let avatarPalette: [(Color, Color)] = [
        (Color(hex: "4A66E8"), Color(hex: "2230A6")), // sapphire
        (Color(hex: "13A89B"), Color(hex: "066772")), // teal
        (Color(hex: "9458EC"), Color(hex: "5E1FC7")), // violet
        (Color(hex: "E9465F"), Color(hex: "9E1E38")), // rose
        (Color(hex: "E8A640"), Color(hex: "A3620C")), // amber
        (Color(hex: "2CAE78"), Color(hex: "0A7043")), // emerald
        (Color(hex: "6768E0"), Color(hex: "3438A6")), // indigo
        (Color(hex: "EE7856"), Color(hex: "B83E1C")), // coral
        (Color(hex: "28A5C9"), Color(hex: "06718D")), // cyan
        (Color(hex: "D04DD0"), Color(hex: "8A1090")), // fuchsia
        (Color(hex: "F08A2E"), Color(hex: "B85812")), // orange
        (Color(hex: "5BC176"), Color(hex: "1E7A38"))  // mint
    ]

    private static func avatarGradient(for name: String) -> (Color, Color) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bucket = abs(key.hashValue) % avatarPalette.count
        return avatarPalette[bucket]
    }


    // MARK: - Leading category rail
    /// Always-on tick bar in the category's accent colour. Light-to-
    /// darker vertical gradient (instead of the previous flat fill)
    /// gives the rail a hint of dimension that matches the card's
    /// lit-from-above body — same physical material, different
    /// surface treatment. Unread state lives in the sender-line dot
    /// and bolder weights, not the rail.
    private var categoryRail: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.95), accent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3)
            .padding(.vertical, 10)
            .padding(.leading, 1)
            .shadow(color: accent.opacity(0.22), radius: 2, x: 0.5, y: 0)
    }

}

// MARK: - Mini Dot indicator
struct MiniDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Tag Badge
struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}
