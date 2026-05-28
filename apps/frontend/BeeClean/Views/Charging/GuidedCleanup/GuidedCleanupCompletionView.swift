import SwiftUI

// MARK: - Guided Cleanup Completion View
//
// Final session screen. Deletion progress updates the headline + bee
// animation in place (no separate overlay).

struct GuidedCleanupCompletionView: View {
    @ObservedObject var vm: GuidedCleanupViewModel
    let onBackToDashboard: () -> Void
    var onPhotoCardTap: (() -> Void)? = nil
    var onVideoCardTap: (() -> Void)? = nil
    var isPrimaryDisabled: Bool = false

    private let honeyYellow = Color(hex: "FFC636")
    private let successGreen = Color(hex: "3A6B3A")
    private let inactiveGrey = Color(hex: "D1D1D6")

    private var mascotAnimation: BeeFrameAnimation {
        switch vm.completionDeletionPhase {
        case .idle:
            return .completionResultCelebration(
                variant: vm.activeCompletionResultGifVariant ?? .smiling
            )
        case .running:
            // Starts only after PhotoKit delete confirmation.
            return .checkpointGifCelebration(variant: .gif2)
        case .success:
            // Keep transition animation through the short pre-dismiss window.
            return .checkpointGifCelebration(variant: .gif2)
        }
    }

    private var contentDimmed: Bool {
        vm.completionDeletionPhase != .idle
    }

    var body: some View {
        // Layout matches Figma node 564:3999:
        //   • Title: SF Pro Rounded Bold 32/38, 24pt horizontal padding
        //   • Bee: 280pt tall (Figma container is 435pt with transparent margin)
        //   • Bottom widgets stack: 16pt horizontal padding, 8pt gap between
        //     Total Space Saved and stat-pair row, 24pt gap before button
        VStack(spacing: 0) {
            headlineArea
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(minHeight: 100, alignment: .leading)

            GuidedCleanupFrameAnimationView(animation: mascotAnimation)
                .animation(.easeInOut(duration: 0.5), value: vm.completionDeletionPhase)

            CompletionSpaceSavedCard(
                formattedBytes: vm.formattedBytesMarked,
                progressPercent: vm.sessionProgressPercent,
                trackColor: inactiveGrey,
                fillColor: successGreen
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .opacity(contentDimmed ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.5), value: contentDimmed)

            HStack(spacing: 8) {
                CompletionCategoryStatCard(
                    icon: "wand.and.stars",
                    iconColor: Color(hex: "0088FF"),
                    count: vm.markedPhotoCount,
                    mediaLabel: "Photos",
                    subtitle: vm.completionPhotoSubtitle,
                    onTap: vm.completionDeletionPhase == .idle ? onPhotoCardTap : nil
                )
                CompletionCategoryStatCard(
                    icon: "film.fill",
                    iconColor: Color(hex: "CB30E0"),
                    count: vm.markedVideoCount,
                    mediaLabel: "Videos",
                    subtitle: vm.completionVideoSubtitle,
                    onTap: vm.completionDeletionPhase == .idle ? onVideoCardTap : nil
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .opacity(contentDimmed ? 0.55 : 1)
            .allowsHitTesting(vm.completionDeletionPhase == .idle)
            .animation(.easeInOut(duration: 0.5), value: contentDimmed)

            Spacer(minLength: 16)

            if vm.completionDeletionPhase == .idle {
                backToDashboardButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: vm.completionDeletionPhase)
        .onAppear {
            vm.ensureCompletionResultGifVariant()
            // #region agent log
            AppDebugLog.write(
                location: "GuidedCleanupCompletionView.onAppear",
                message: "completion visible",
                hypothesisId: "H1",
                data: [
                    "progressPercent": vm.sessionProgressPercent,
                    "bytesMarked": vm.totalBytesMarked
                ]
            )
            // #endregion
        }
    }

    @ViewBuilder
    private var headlineArea: some View {
        switch vm.completionDeletionPhase {
        case .idle:
            Text("All clear! Your favorite memories finally have some room to breathe.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .lineSpacing(6) // approximates Figma's 38px leading on 32pt text
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)

        case .running:
            Text(vm.completionDeletionMessage)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(vm.completionDeletionMessage)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundColor(successGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
        }
    }

    private var backToDashboardButton: some View {
        Button {
            HapticManager.shared.impact(.medium)
            onBackToDashboard()
        } label: {
            Group {
                if isPrimaryDisabled {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(vm.totalMarked > 0
                        ? "Delete & Proceed to Dashboard"
                        : "Proceed to Dashboard")
                }
            }
            // Figma I564:4131;349:14039 — bg #ffc648 capsule, padding ×15,
            // 14pt Inter Medium, shadow 0/4/16 black 0.05.
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(honeyYellow.opacity(isPrimaryDisabled ? 0.7 : 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.05), radius: 16, y: 4)
        }
        .disabled(isPrimaryDisabled)
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Total Space Saved Card

private struct CompletionSpaceSavedCard: View {
    let formattedBytes: String
    let progressPercent: Int
    let trackColor: Color
    let fillColor: Color

    var body: some View {
        // Figma I564:4131;349:14011 — bg white, rounded 20, padding 20×12.
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total Space Saved")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black.opacity(0.5))
                    .tracking(-0.16)

                Text(formattedBytes)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .tracking(-0.32)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            SessionGoalRing(
                progressPercent: progressPercent,
                trackColor: trackColor,
                fillColor: fillColor
            )
            .frame(width: 72, height: 72)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - Category Stat Card

private struct CompletionCategoryStatCard: View {
    let icon: String
    let iconColor: Color
    let count: Int
    let mediaLabel: String
    let subtitle: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        // Figma I564:4131;349:14022 — bg white, rounded 20, padding 16×12,
        // gap 12. Icon disc 36×36 (8pt padding around 20pt glyph).
        Button {
            HapticManager.shared.impact(.light)
            onTap?()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 0) {
                    Text("\(count) \(mediaLabel)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .tracking(-0.18)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                        .tracking(-0.13)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(onTap == nil)
    }
}

// MARK: - Session Goal Ring

private struct SessionGoalRing: View {
    let progressPercent: Int
    let trackColor: Color
    let fillColor: Color

    @State private var animatedProgress: Double = 0

    private let ringSize: CGFloat = 76
    private let lineWidth: CGFloat = 7

    private var progressFraction: Double {
        Double(min(max(progressPercent, 0), 100)) / 100
    }

    private var percentLabel: String {
        "\(progressPercent)%"
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)

            ZStack {
                Circle()
                    .stroke(trackColor.opacity(0.55), lineWidth: lineWidth)
                    .frame(width: ringSize, height: ringSize)

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        fillColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: animatedProgress)

                Text(percentLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(width: ringSize - lineWidth * 4, height: ringSize - lineWidth * 4)
            }
        }
        .frame(width: ringSize, height: ringSize + 18)
        .onAppear {
            animatedProgress = progressFraction
        }
        .onChange(of: progressPercent) { _, newValue in
            animatedProgress = Double(min(max(newValue, 0), 100)) / 100
        }
    }
}
