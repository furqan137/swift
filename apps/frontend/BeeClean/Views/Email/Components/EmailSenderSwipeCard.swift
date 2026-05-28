import SwiftUI

struct EmailSwipeCard: View {
    let message: EmailMessage
    let cardSize: CGSize
    let onSwipe: (SwipeDirection) -> Void

    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    private let swipeThreshold: CGFloat = 120

    var body: some View {
        cardContent
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(swipeOverlay)
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .offset(x: offset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        offset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        let distance = value.translation.width

                        if abs(distance) > swipeThreshold {
                            let direction: SwipeDirection = distance < 0 ? .left : .right
                            HapticManager.shared.tapSensation()
                            withAnimation(.easeOut(duration: 0.25)) {
                                offset.width = distance < 0 ? -500 : 500
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                offset = .zero
                                onSwipe(direction)
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = .zero
                            }
                        }
                    }
            )
    }

    // MARK: - Card Content
    private var cardContent: some View {
        VStack(spacing: 16) {
            Spacer()

            // Sender avatar
            Text(senderInitial)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
                .background(avatarColor)
                .clipShape(Circle())

            // Sender name
            Text(message.senderName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.foreground)
                .lineLimit(1)
                .padding(.horizontal, 24)

            // Sender email
            Text(message.senderEmail)
                .font(.system(size: 13))
                .foregroundColor(.foregroundSecondary)
                .lineLimit(1)
                .padding(.horizontal, 24)

            // Subject
            Text(message.subject)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            // Snippet
            Text(EmailFormatters.cleanSnippet(message.snippet))
                .font(.system(size: 14))
                .foregroundColor(.foregroundSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)

            // Date badge
            if let dateStr = message.date {
                Text(EmailFormatters.shortDate(dateStr))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.surfaceLight)
                    .cornerRadius(16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.card)
    }

    // MARK: - Swipe Overlay — DELETE / KEEP labels
    //
    // Mirrors `MediaSwipeView.swipeOverlay` exactly so every swipe deck
    // in the app — Other Photos, Blurry, Screen Recordings, Short / Long
    // Videos, Email QuickClean — shows the same Tinder-style overlay.
    // Colored wash + bordered rotated label, fading in with the drag.
    @ViewBuilder
    private var swipeOverlay: some View {
        ZStack {
            if offset.width < 0 {
                let intensity = Double(min(abs(offset.width) / swipeThreshold, 1))
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(intensity * 0.42))

                Text("DELETE")
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .opacity(intensity)
                    .rotationEffect(.degrees(-14))
            }

            if offset.width > 0 {
                let intensity = Double(min(offset.width / swipeThreshold, 1))
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(intensity * 0.42))

                Text("KEEP")
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .opacity(intensity)
                    .rotationEffect(.degrees(14))
            }
        }
        .allowsHitTesting(false)
    }

    /// Soft tinted gradient anchored to one edge — hints at the commit
    /// direction without painting over the card content. Scales from
    /// invisible at 0 progress to a gentle 28% wash at 1.0.
    private func edgeVignette(tint: Color, edge: HorizontalEdge, progress: Double) -> some View {
        let start: UnitPoint = edge == .leading ? .leading : .trailing
        let end: UnitPoint = edge == .leading ? .trailing : .leading
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.28 * progress),
                        tint.opacity(0.0)
                    ],
                    startPoint: start,
                    endPoint: end
                )
            )
    }

    /// Floating glass chip — `.ultraThinMaterial` + white-gradient wash +
    /// soft halo in the direction's accent color. Slides in from the edge
    /// and settles to its resting position as progress approaches 1.
    private func glassSwipeChip(
        label: String,
        icon: String,
        foreground: Color,
        halo: Color,
        progress: Double,
        alignment: Alignment
    ) -> some View {
        let shape = Capsule(style: .continuous)
        let slideIn: CGFloat = alignment == .leading ? -40 : 40
        let slideOffset = CGFloat(1 - progress) * slideIn

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(label)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(0.2)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.9),
                        halo.opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.9
            )
        )
        .shadow(color: halo.opacity(0.35 * progress), radius: 14, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .opacity(progress)
        .scaleEffect(0.9 + 0.1 * progress)
        .offset(x: slideOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    // MARK: - Helpers
    private var senderInitial: String {
        let name = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(name.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            .categoryHoney, .categoryTeal, .categoryAmber,
            .categoryRose, .categoryViolet, .categorySky
        ]
        let hash = abs(message.senderEmail.hashValue)
        return colors[hash % colors.count]
    }
}
