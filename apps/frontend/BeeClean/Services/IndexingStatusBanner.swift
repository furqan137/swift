import SwiftUI
import UIKit

// MARK: - Global Indexing Status Banner
/// Drop-in SwiftUI banner that mirrors the current pipeline state. Attach it
/// as an overlay on the app root so indexing progress is visible on every
/// screen, not only Ask Bee.
///
/// Example:
/// ```swift
/// ContentView()
///     .overlay(alignment: .top) { IndexingStatusBanner() }
/// ```
struct IndexingStatusBanner: View {
    @ObservedObject private var service = PhotoIndexingService.shared

    var body: some View {
        // Error states take priority — if indexing failed, surface it
        // even after the run "ended" so the user knows search results
        // may be incomplete and can act on it.
        if let failure = service.surfacedFailure {
            errorBanner(failure: failure)
        } else {
            progressBanner
        }
    }

    @ViewBuilder
    private var progressBanner: some View {
        let shouldShow = service.isIndexingEmbeddings
            || service.isIndexing
            || service.isPaused
            || (service.hasPendingWork && !(service.embeddingProgress.isComplete))

        if shouldShow {
            HStack(spacing: 10) {
                // Left: state icon
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(accentColor))

                // Middle: status line + sub-metric
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)
                    if let sub = secondaryText {
                        Text(sub)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                // Right: percent + tiny progress
                if progress.totalAssets > 0 && !service.isPaused {
                    Text("\(progress.percent)%")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: service.statusLine)
        }
    }

    // MARK: Derived bindings
    private var progress: IndexingProgress {
        return service.isIndexingEmbeddings ? service.embeddingProgress : service.progress
    }

    private var primaryText: String {
        if !service.statusLine.isEmpty { return service.statusLine }
        if service.isPaused { return "Paused — will resume when allowed" }
        if progress.isComplete { return "Indexing complete" }
        return progress.phase
    }

    private var secondaryText: String? {
        let rate = service.metrics.assetsPerSecond
        if service.isIndexingEmbeddings && rate > 0.1 {
            let fail = service.metrics.failureRate
            if fail > 0.02 {
                return String(format: "%.1f/s · %.0f%% failed", rate, fail * 100)
            }
            return String(format: "%.1f assets/sec", rate)
        }
        if service.isPaused {
            return "Progress saved at \(progress.processedAssets)/\(progress.totalAssets)"
        }
        return nil
    }

    private var iconName: String {
        if service.isPaused { return "pause.fill" }
        if progress.isComplete { return "checkmark" }
        if service.isIndexingEmbeddings { return "sparkles" }
        return "arrow.triangle.2.circlepath"
    }

    private var accentColor: Color {
        if service.isPaused { return Color(hex: "A1A1AA") }
        if progress.isComplete { return Color(hex: "10B981") }
        return Color(hex: "1C1917")
    }

    // MARK: - Error banner
    //
    // Red-accented variant for surfaced indexing failures. Picks the
    // action that actually unblocks the user:
    //   - `.permissionDenied` → "Open Settings" (only the user can fix
    //     this; in-app retry would just fail again)
    //   - `.retryable`        → "Retry" → `retryAfterError()`
    @ViewBuilder
    private func errorBanner(failure: PhotoIndexingService.SurfacedFailure) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(hex: "DC2626")))

            VStack(alignment: .leading, spacing: 1) {
                Text(errorPrimaryText(for: failure))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .lineLimit(1)
                Text(errorSecondaryText(for: failure))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button(action: { handleErrorAction(failure) }) {
                Text(errorActionTitle(for: failure))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                    )
            }
            .buttonStyle(.plain)

            // Dismiss — clears the surfaced failure so the persistent
            // red banner stops covering the streak + settings buttons
            // in the dashboard header. A future indexing run will
            // re-raise the banner if the same problem recurs.
            Button(action: { service.dismissSurfacedFailure() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "78716C"))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: "DC2626").opacity(0.25), lineWidth: 0.6)
        )
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func errorPrimaryText(for failure: PhotoIndexingService.SurfacedFailure) -> String {
        switch failure {
        case .permissionDenied: return "Photos access needed"
        case .retryable:        return "Indexing didn't finish"
        }
    }

    private func errorSecondaryText(for failure: PhotoIndexingService.SurfacedFailure) -> String {
        switch failure {
        case .permissionDenied: return "Search won't return your photos without access."
        case .retryable:
            return service.embeddingProgress.error ?? "Tap Retry to try again."
        }
    }

    private func errorActionTitle(for failure: PhotoIndexingService.SurfacedFailure) -> String {
        switch failure {
        case .permissionDenied: return "Settings"
        case .retryable:        return "Retry"
        }
    }

    private func handleErrorAction(_ failure: PhotoIndexingService.SurfacedFailure) {
        switch failure {
        case .permissionDenied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .retryable:
            service.retryAfterError()
        }
    }
}
