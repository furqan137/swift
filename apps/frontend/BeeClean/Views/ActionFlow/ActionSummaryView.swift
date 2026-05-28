import SwiftUI

// MARK: - Action Summary View
//
// Full-screen summary shown after a cleanup action completes. Displays
// action-specific stats with a celebration checkmark, hero number, stats
// card, and CTAs. This is the "screenshot moment" — the user's reward for
// completing a cleanup action.

struct ActionSummaryView: View {
    let result: ActionResult
    let onContinue: () -> Void
    let onNextSection: (() -> Void)?

    // Animation states
    @State private var checkScale: CGFloat = 0.3
    @State private var checkOpacity: Double = 0
    @State private var heroNumberDisplay: Int = 0
    @State private var statsOpacity: Double = 0
    @State private var ctaOffset: CGFloat = 40
    @State private var ctaOpacity: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WarmGoldBackdrop()

            VStack(spacing: 0) {
                Spacer()

                // Checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.success)
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
                    .padding(.bottom, 20)

                // Hero text
                Text(result.heroText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)

                // Subtitle
                Text(result.subtitleText)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "71717A"))
                    .padding(.bottom, 28)

                // Stats card — variant per section
                statsCard
                    .padding(.horizontal, 20)
                    .opacity(statsOpacity)

                // Footer note
                if let footerNote = footerNote {
                    Text(footerNote)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .opacity(statsOpacity)
                }

                Spacer()

                // CTAs
                VStack(spacing: 12) {
                    // Primary: Continue
                    Button {
                        HapticManager.shared.impact(.light)
                        Analytics.track("action_summary_continue_tapped", properties: [
                            "section": result.section.rawValue
                        ])
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "3D2914"), Color(hex: "1C1917")],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color(hex: "FFC636").opacity(0.7), Color.clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(color: Color(hex: "1C1917").opacity(0.22), radius: 14, x: 0, y: 6)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    // Secondary: Clean Something Else
                    if let onNextSection {
                        let suggested = ActionFlowCoordinator.nextSection(after: result.section)
                        Button {
                            Analytics.track("action_summary_next_section_tapped", properties: [
                                "section": result.section.rawValue,
                                "suggested_section": suggested.rawValue
                            ])
                            onNextSection()
                        } label: {
                            Text("Clean Something Else")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: "A1A1AA"))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .offset(y: ctaOffset)
                .opacity(ctaOpacity)
            }
        }
        .onAppear {
            Analytics.track("action_summary_shown", properties: ["section": result.section.rawValue])
            playAnimation()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Stats Card

    @ViewBuilder
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch (result.section, result.actionType) {
            case (.photos, .delete), (.videos, .delete):
                deletionStatsContent
            case (.compress, .compress):
                compressionStatsContent
            case (.email, .clean):
                emailStatsContent
            case (.contacts, .merge):
                contactStatsContent
            default:
                genericStatsContent
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GlassPanel(cornerRadius: DesignTokens.Radius.lg)
        )
    }

    // MARK: - Deletion Stats (Photos / Videos)

    private var deletionStatsContent: some View {
        Group {
            if let freed = result.bytesFreed {
                statRow(icon: "sparkles", iconColor: Color(hex: "F59E0B"),
                        label: "Storage Freed", value: formatBytes(freed))
            }
            statRow(icon: "trash", iconColor: Color(hex: "EF4444"),
                    label: "Items Removed", value: "\(result.itemsProcessed)")
        }
    }

    // MARK: - Compression Stats

    private var compressionStatsContent: some View {
        Group {
            if let original = result.originalBytes {
                statRow(icon: "doc.fill", iconColor: Color(hex: "8A8A8E"),
                        label: "Original Size", value: formatBytes(original))
            }
            if let compressed = result.compressedBytes {
                statRow(icon: "doc.zipper", iconColor: Color(hex: "1C1917"),
                        label: "New Size", value: formatBytes(compressed))
            }
            if let percent = result.savingsPercent {
                statRow(icon: "arrow.down.circle.fill", iconColor: Color(hex: "22C55E"),
                        label: "Reduction", value: "\(percent)%")
            }
        }
    }

    // MARK: - Email Stats

    private var emailStatsContent: some View {
        Group {
            if let breakdown = result.breakdown {
                ForEach(Array(breakdown.sorted(by: { $0.value > $1.value })), id: \.key) { category, count in
                    statRow(icon: "envelope.fill", iconColor: Color(hex: "F59E0B"),
                            label: category, value: "\(count)")
                }
            } else {
                statRow(icon: "envelope.fill", iconColor: Color(hex: "F59E0B"),
                        label: "Emails Cleaned", value: "\(result.itemsProcessed)")
            }

            if let senders = result.topSenders, !senders.isEmpty {
                Divider().background(Color(hex: "1C1917").opacity(0.06))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Senders")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    ForEach(senders, id: \.self) { sender in
                        Text(sender)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "1C1917"))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Contact Stats

    private var contactStatsContent: some View {
        Group {
            statRow(icon: "person.2.fill", iconColor: Color(hex: "6366F1"),
                    label: "Groups Merged", value: "\(result.itemsProcessed)")
            if let breakdown = result.breakdown, let deleted = breakdown["deleted"] {
                statRow(icon: "person.badge.minus", iconColor: Color(hex: "EF4444"),
                        label: "Duplicates Removed", value: "\(deleted)")
            }
        }
    }

    // MARK: - Generic Stats

    private var genericStatsContent: some View {
        statRow(icon: "checkmark.circle", iconColor: .success,
                label: "Items Processed", value: "\(result.itemsProcessed)")
    }

    // MARK: - Stat Row

    private func statRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 28, alignment: .center)

            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "71717A"))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "1C1917"))
        }
    }

    // MARK: - Footer Note

    private var footerNote: String? {
        switch (result.section, result.actionType) {
        case (.photos, .delete), (.videos, .delete):
            return "Moved to Recently Deleted (recoverable for 30 days)"
        case (.compress, .compress):
            return "Originals replaced. Quality preserved."
        default:
            return nil
        }
    }

    // MARK: - Animation

    private func playAnimation() {
        if reduceMotion {
            checkScale = 1.0
            checkOpacity = 1.0
            statsOpacity = 1.0
            ctaOffset = 0
            ctaOpacity = 1.0
            return
        }

        // Step 1: Checkmark bounces in (0.2s delay)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
            checkScale = 1.0
            checkOpacity = 1.0
        }

        // Step 2: Stats card fades in (0.4s delay)
        withAnimation(.easeOut(duration: 0.3).delay(0.4)) {
            statsOpacity = 1.0
        }

        // Step 3: CTAs slide up (0.6s delay)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6)) {
            ctaOffset = 0
            ctaOpacity = 1.0
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var desc = result.heroText + ". " + result.subtitleText + "."
        if let freed = result.bytesFreed {
            desc += " \(formatBytes(freed)) freed."
        }
        if let saved = result.bytesSaved {
            desc += " \(formatBytes(saved)) saved."
        }
        return desc
    }
}
