import SwiftUI

// MARK: - Shared Similar/Duplicate state components
//
// All four photo-cleanup screens (SimilarPhotos, DuplicatePhotos,
// Screenshots, SimilarVideos) share the same non-scan UI: a small
// chrome header, an idle "tap to scan" empty state, a scanning
// progress block, and a deletion progress bar. Pulling these into
// one file deletes ~120 lines of near-identical boilerplate from
// each view and ensures any future polish hits all four screens at
// once.

// MARK: - Category Header (back chevron + title + optional cancel)
//
// The compact 44pt-tall chrome rendered above the empty / scanning /
// idle states. The list states use `CollapsingHeaderLayout` instead.
struct SimilarCategoryHeader: View {
    let title: String
    let isScanning: Bool
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Button(action: {
                HapticManager.shared.arrowNudge(.backward)
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
            }

            Spacer()

            Text(title)
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(Color(hex: "1C1917"))

            Spacer()

            if isScanning {
                Button("Cancel", action: onCancel)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.destructive)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }
}

// MARK: - Idle (not yet scanned) state
struct SimilarIdleState: View {
    let iconName: String
    let tint: Color
    let title: String
    let subtitle: String
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Image(systemName: iconName)
                    .font(.system(size: 44))
                    .foregroundColor(tint)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Poppins-Bold", size: 20))
                    .foregroundColor(Color(hex: "1C1917"))

                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .multilineTextAlignment(.center)
            }

            PrimaryButton("Scan Photos", iconName: "magnifyingglass", action: onScan)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Scanning progress block
struct SimilarScanningProgressState: View {
    let phase: String
    let progress: Double
    let percentComplete: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: tint))
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text(phase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("\(percentComplete)%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(tint)
            }

            Spacer()
        }
    }
}

// MARK: - Delete progress bar (pinned to bottom while deleting)
struct SimilarDeleteProgressBar: View {
    let deleted: Int
    let totalToDelete: Int
    let fraction: Double
    let currentChunk: Int
    let totalChunks: Int

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: fraction)
                .progressViewStyle(LinearProgressViewStyle(tint: .destructive))

            HStack {
                Text("Deleting… \(deleted)/\(totalToDelete)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                if totalChunks > 1 {
                    Text("Batch \(currentChunk)/\(totalChunks)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
        }
        .padding(16)
        .background(Color.surfaceLight)
    }
}

// MARK: - Stale cache banner ("results may be outdated, tap to rescan")
struct SimilarStaleCacheBanner: View {
    let onRescan: () -> Void

    var body: some View {
        Button(action: onRescan) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.warning)

                Text("Results may be outdated — tap to rescan")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "A1A1AA"))

                Spacer()
            }
            .padding(12)
            .background(Color.warning.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}
