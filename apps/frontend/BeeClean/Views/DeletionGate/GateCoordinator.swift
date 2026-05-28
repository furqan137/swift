import SwiftUI

// MARK: - GateCoordinator
//
// Section-aware freemium gate. Same visual design as DeletionGateView,
// parameterized by FeatureGateConfig. Renders one of three layouts:
//   Pattern A (.rewardedAd): free option + ad option + pro
//   Pattern B (.hardCap):    free option + helper text + pro (no ad)
//   Pattern C (.meteredPerAd): free/ad-per-action + pro

struct GateCoordinator: View {
    let config: FeatureGateConfig
    let selectedCount: Int
    let onActionApproved: (Int) async -> Int
    let onPaywall: (String) -> Void

    @State private var viewModel: GateCoordinatorViewModel
    @State private var remainingCount: Int = 0
    @State private var isProcessing: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(
        config: FeatureGateConfig,
        selectedCount: Int,
        onActionApproved: @escaping (Int) async -> Int,
        onPaywall: @escaping (String) -> Void
    ) {
        self.config = config
        self.selectedCount = selectedCount
        self.onActionApproved = onActionApproved
        self.onPaywall = onPaywall
        _viewModel = State(initialValue: GateCoordinatorViewModel(config: config))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "D4D4D8"))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            // Header
            VStack(spacing: 8) {
                Text("\(config.actionVerb) \(remainingCount) \(remainingCount == 1 ? "Item" : "Items")")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                if viewModel.isLoading || isProcessing {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .padding(.top, 20)

            Spacer().frame(height: 24)

            if !viewModel.isLoading && !isProcessing {
                VStack(spacing: 12) {
                    switch config.pattern {
                    case .rewardedAd:
                        patternAContent
                    case .hardCap:
                        patternBContent
                    case .meteredPerAd:
                        patternCContent
                    }

                    // Pro option — always shown
                    proOption
                }
                .padding(.horizontal, 20)
            }

            Spacer().frame(height: 16)

            // Cancel
            Button {
                Analytics.track("gate_dismissed", properties: ["section": config.section.rawValue])
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }
            .padding(.bottom, 32)
        }
        .task {
            remainingCount = selectedCount
            Analytics.track("gate_shown", properties: [
                "selected_count": selectedCount,
                "section": config.section.rawValue
            ])
            await viewModel.loadQuota()
        }
        .sheet(isPresented: $viewModel.showProNag) {
            ProNagView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Handle Approval

    private func handleApproval(_ approved: Int) async {
        guard approved > 0 else { return }
        isProcessing = true
        let remaining = await onActionApproved(approved)
        isProcessing = false

        if remaining <= 0 {
            dismiss()
        } else {
            remainingCount = remaining
            await viewModel.loadQuota()
        }
    }

    // MARK: - Pattern A: Rewarded Ad

    @ViewBuilder
    private var patternAContent: some View {
        if viewModel.canUseFreeActions {
            freeActionOption
        }
        adOption
    }

    // MARK: - Pattern B: Hard Cap

    @ViewBuilder
    private var patternBContent: some View {
        if viewModel.canUseFreeActions {
            freeActionOption
        }

        if let helperText = config.helperText {
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "71717A"))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "F4F4F5"))
                    .clipShape(Circle())

                Text(helperText)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "71717A"))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "F4F4F5"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "E4E4E7"), lineWidth: 1)
            )
        }
    }

    // MARK: - Pattern C: Metered Per Ad

    @ViewBuilder
    private var patternCContent: some View {
        if viewModel.freeActionsRemaining > 0 {
            // Free remaining
            Button {
                Task {
                    let approved = await viewModel.chooseFree(selectedCount: remainingCount)
                    await handleApproval(approved)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "71717A"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "F4F4F5"))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(config.actionVerb) 1 Free")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                        Text("\(viewModel.freeActionsRemaining) free remaining today")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "D4D4D8"))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "E4E4E7"), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else if !viewModel.isAdCapReached {
            // Ad-per-action
            Button {
                Task {
                    let approved = await viewModel.chooseAd(selectedCount: remainingCount)
                    await handleApproval(approved)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.categoryPurple)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.adButtonLabel(remainingCount))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))
                        Text("Watch a short video to continue")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "D4D4D8"))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.categoryPurple.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.categoryPurple.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isAdReady)
            .opacity(viewModel.isAdReady ? 1 : 0.5)
        } else {
            // Daily ad limit reached
            adCapReachedCard
        }
    }

    // MARK: - Free Action Option

    private var freeActionOption: some View {
        let count = min(viewModel.freeActionsRemaining, remainingCount)
        return Button {
            Task {
                let approved = await viewModel.chooseFree(selectedCount: remainingCount)
                await handleApproval(approved)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "71717A"))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "F4F4F5"))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(config.actionVerb) \(count) Free")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                    Text("\(viewModel.freeActionsRemaining) free \(config.actionVerb.lowercased())s remaining today")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "D4D4D8"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "E4E4E7"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ad Option (Pattern A)

    private var adOption: some View {
        Group {
            if viewModel.isAdCapReached {
                adCapReachedCard
            } else {
                Button {
                    Task {
                        let approved = await viewModel.chooseAd(selectedCount: remainingCount)
                        await handleApproval(approved)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.categoryPurple)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(config.adButtonLabel(remainingCount))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(hex: "1C1917"))
                            Text("Watch a short video to unlock more \(config.actionVerb.lowercased())s")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "A1A1AA"))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "D4D4D8"))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.categoryPurple.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.categoryPurple.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isAdReady)
                .opacity(viewModel.isAdReady ? 1 : 0.5)
            }
        }
    }

    // MARK: - Ad Cap Reached Card

    private var adCapReachedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.categoryAmber)
                .frame(width: 36, height: 36)
                .background(Color.categoryAmber.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Free Limit Reached")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                Text("Upgrade to Pro for unlimited access")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.categoryAmber.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.categoryAmber.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Pro Option

    private var proOption: some View {
        Button {
            Analytics.track("gate_chose_pro", properties: ["section": config.section.rawValue])
            dismiss()
            onPaywall("deletion_gate_\(config.section.rawValue)")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.categoryAmber)
                    .frame(width: 36, height: 36)
                    .background(Color.categoryAmber.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Pro — Unlimited")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                    Text("No ads, no limits, clean everything")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }

                Spacer()

                Text(BCLoc.goPro.tr)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.categoryAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.categoryAmber.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color.categoryAmber.opacity(0.08), Color.categoryAmber.opacity(0.02)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.categoryAmber.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
