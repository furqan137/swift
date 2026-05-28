import SwiftUI

// MARK: - Indexing Progress View

/// Full-screen progress view shown when Ask Bee is tapped before indexing
/// is complete. Purely observational — dismissing this view has zero effect
/// on the underlying indexing pipeline.
struct IndexingProgressView: View {
    @ObservedObject private var indexingService = IndexingService.shared
    @Environment(\.dismiss) private var dismiss

    // Analytics tracking
    @State private var viewAppearedAt: Date?
    @State private var userInitiatedDismissal = false
    /// One-shot guard for the indexing-complete haptic. `.onChange`
    /// fires once per state CHANGE, but if the pipeline ever bounces
    /// from `.complete` to a non-complete state and back (e.g. a
    /// library-change-triggered re-index that finishes again), we
    /// don't want to re-play the celebratory sparkle every time.
    @State private var didPlayCompletionHaptic = false

    private let teaserQueries = [
        "Photos of my dog at the beach",
        "Screenshots from last month",
        "Sunset photos from 2024"
    ]

    var body: some View {
        ZStack {
            BitepalCanvas()

            VStack(spacing: 0) {
                // Back button
                HStack {
                    Button {
                        userInitiatedDismissal = true
                        HapticManager.shared.arrowNudge(.backward)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(Color(hex: "F5F5F4"))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer().frame(height: 20)

                        // Bee avatar
                        AppIconAvatar(size: 100)

                        // Title
                        Text("Bee is getting ready for you")
                            .font(.titleLarge)
                            .foregroundColor(.foreground)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        // Dynamic content based on state
                        stateContent

                        Spacer().frame(height: 16)

                        // Teaser queries
                        if !isTerminalState {
                            teaserSection
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .onAppear {
            viewAppearedAt = Date()
            AnalyticsService.shared.log("indexing_progress_view_opened", properties: [
                "state": indexingService.state.description
            ])
        }
        .onDisappear {
            guard userInitiatedDismissal else { return }
            switch indexingService.state {
            case .inProgress, .paused:
                let secondsOnScreen = viewAppearedAt.map { Date().timeIntervalSince($0) } ?? 0
                var props: [String: Any] = [
                    "seconds_on_screen": Int(secondsOnScreen)
                ]
                if case .inProgress(let stage, let progress) = indexingService.state {
                    props["progress_pct"] = Int(progress * 100)
                    props["stage"] = stage.rawValue
                }
                AnalyticsService.shared.log("indexing_progress_view_abandoned", properties: props)
            default:
                return
            }
        }
        .onChange(of: indexingService.state) { _, newState in
            if newState == .complete && !didPlayCompletionHaptic {
                // One-time dopamine moment — "we just finished
                // indexing your whole photo library". streakReveal
                // is the three-spark CoreHaptics rise already used
                // for Charging-streak milestones, so it lands as
                // celebratory rather than a single medium pop.
                // Guarded by `didPlayCompletionHaptic` so a library
                // change → re-index → re-complete cycle doesn't
                // re-fire the sparkle once it's already been seen.
                didPlayCompletionHaptic = true
                HapticManager.shared.streakReveal()
            }
        }
    }

    // MARK: - State-Dependent Content

    @ViewBuilder
    private var stateContent: some View {
        switch indexingService.state {
        case .notStarted:
            notStartedContent

        case .inProgress(let stage, let progress):
            inProgressContent(stage: stage, progress: progress)

        case .paused:
            pausedContent

        case .complete:
            completeContent

        case .failed(let error):
            failedContent(error: error)

        case .blockedNoPhotoPermission:
            blockedContent
        }
    }

    private var notStartedContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "1C1917"))

            Text("Preparing to scan your photo library...")
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func inProgressContent(stage: IndexingStage, progress: Double) -> some View {
        VStack(spacing: 16) {
            // Dynamic status line
            Text(dynamicStatusLine(stage: stage))
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Progress bar
            VStack(spacing: 8) {
                if progress > 0 {
                    ProgressView(value: progress)
                        .tint(Color(hex: "1C1917"))
                        .padding(.horizontal, 48)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.foreground)
                } else {
                    ProgressView()
                        .tint(Color(hex: "1C1917"))

                    Text("Starting...")
                        .font(.labelMedium)
                        .foregroundColor(.mutedForeground)
                }
            }

            // ETA estimate
            if let eta = estimatedTimeRemaining(progress: progress) {
                Text(eta)
                    .font(.labelMedium)
                    .foregroundColor(.mutedForeground)
            }
        }
    }

    private var pausedContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "1C1917"))

            Text("Indexing paused — will resume shortly")
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var completeContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.success)

            Text("Bee is ready!")
                .font(.titleMedium)
                .foregroundColor(.foreground)

            Button {
                HapticManager.shared.impact(.medium, intensity: 0.7)
                dismiss()
            } label: {
                Text("Start chatting")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                    )
            }
            .padding(.horizontal, 48)
        }
    }

    private func failedContent(error: String) -> some View {
        VStack(spacing: 16) {
            Text("Something went wrong")
                .font(.titleMedium)
                .foregroundColor(.foreground)

            Text(error)
                .font(.bodySmall)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                HapticManager.shared.impact(.medium, intensity: 0.7)
                indexingService.retry()
            } label: {
                Text(BCLoc.retry.tr)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                    )
            }
            .padding(.horizontal, 48)
        }
    }

    private var blockedContent: some View {
        VStack(spacing: 16) {
            Text("Bee needs access to your photos to learn your library.")
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            let photoStatus = PhotoKitService.shared.authorizationStatus
            if photoStatus == .denied || photoStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(BCLoc.openSettings.tr)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                }
                .padding(.horizontal, 48)
            } else {
                Button {
                    Task {
                        let granted = await PhotoKitService.shared.requestAuthorization()
                        if granted {
                            indexingService.startIfNeeded()
                        }
                    }
                } label: {
                    Text("Allow Photo Access")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                }
                .padding(.horizontal, 48)
            }
        }
    }

    // MARK: - Teaser Section

    private var teaserSection: some View {
        VStack(spacing: 12) {
            Text("Soon you can ask things like:")
                .font(.labelMedium)
                .foregroundColor(.mutedForeground)

            VStack(spacing: 8) {
                ForEach(teaserQueries, id: \.self) { query in
                    Text(query)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.foreground.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "F5F5F4"))
                        )
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private var isTerminalState: Bool {
        switch indexingService.state {
        case .complete, .failed: return true
        default: return false
        }
    }

    private func dynamicStatusLine(stage: IndexingStage) -> String {
        switch stage {
        case .metadataScan:
            let p = PhotoIndexingService.shared.progress
            if p.totalAssets > 0 {
                return "Scanning \(p.processedAssets) of \(p.totalAssets) photos"
            }
            return "Scanning your photo library..."
        case .contentEmbeddings:
            let p = PhotoIndexingService.shared.embeddingProgress
            if p.totalAssets > 0 {
                return "Learning your photos — \(p.processedAssets) of \(p.totalAssets)"
            }
            return "Learning your photo library..."
        }
    }

    private func estimatedTimeRemaining(progress: Double) -> String? {
        guard progress > 0.01 else { return nil }
        let rate = PhotoIndexingService.shared.metrics.assetsPerSecond
        guard rate > 0.1 else { return nil }

        let remaining: Double
        if case .inProgress(let stage, _) = indexingService.state {
            switch stage {
            case .contentEmbeddings:
                let p = PhotoIndexingService.shared.embeddingProgress
                let left = p.totalAssets - p.processedAssets
                guard left > 0 else { return nil }
                remaining = Double(left) / rate
            case .metadataScan:
                let p = PhotoIndexingService.shared.progress
                let left = p.totalAssets - p.processedAssets
                guard left > 0 else { return nil }
                remaining = Double(left) / rate
            }
        } else {
            return nil
        }

        if remaining < 60 {
            return "About a minute remaining"
        } else {
            let minutes = Int(remaining / 60)
            return "About \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        }
    }
}

#Preview {
    IndexingProgressView()
}
