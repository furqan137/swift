import SwiftUI

// MARK: - Scanning Overlay
//
// Cosmetic scan-progress takeover shown while the home tab kicks off
// `runFullScan(force:)`. Visual only — the bar and counters are derived
// from elapsed time, not from the actual scan engine, since this view
// presents while the heavy work runs out of process and we want a
// stable UX regardless of scan duration.
//
// Timing model:
//   • Total run-time = `totalDuration` seconds (5s by default).
//   • Redraws are driven by a SwiftUI `TimelineView(.periodic(...))`
//     instead of a `Timer.scheduledTimer`. The previous build ticked
//     at 100ms while two adjacent `Text` labels carried
//     `.contentTransition(.numericText())` — that fired numeric
//     crossfade animations 10×/sec on the main thread WHILE the real
//     scan was competing for the same thread. TimelineView batches
//     redraws against the display refresh cycle, so the overlay
//     never burns frames mid-scan.
//   • Cadence dropped 100ms → 280ms. Below display-refresh granularity
//     the user can't perceive the difference, and `.numericText()` was
//     where the work lived anyway — removing it (the percent label is
//     monospaced; the percent number sliding cleanly is the right
//     read, not a crossfade) gives back the main-thread budget.
//   • Completion is fired by a single one-shot `.task` rather than a
//     repeating timer's `if progress >= 1.0` branch — eliminates the
//     subtle off-by-one where the timer could fire one tick past 100%
//     and stack two completion calls.

struct ScanningOverlay: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    /// Wall-clock start of the cosmetic progress run. Captured once on
    /// appear so derived progress = elapsed / totalDuration is monotonic.
    @State private var startTime: Date = .distantFuture
    @State private var glowPulse = false
    @State private var appeared = false

    private let totalDuration: TimeInterval = 5.0
    /// Synthetic items-scanned ceiling — same constant as the prior
    /// timer-driven build so the visible "1847 items" landing number
    /// stays consistent.
    private let totalItems: Int = 1847

    private let statusMessages = [
        "Scanning photos...",
        "Analyzing videos...",
        "Finding duplicates...",
        "Checking screenshots...",
        "Optimizing results..."
    ]

    var body: some View {
        ZStack {
            Color.background.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon with ambient glow
                ZStack {
                    Circle()
                        .fill(Color.primaryColor.opacity(glowPulse ? 0.08 : 0.03))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowPulse)

                    Circle()
                        .fill(Color.white.opacity(0.025))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.06), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.35))
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.9)
                .animation(.easeOut(duration: 0.4), value: appeared)
                .padding(.bottom, 32)

                // Progress + counters block — wrapped in a single
                // TimelineView so all three derived values (status
                // message, items count, progress fraction) update
                // together off ONE redraw schedule. SwiftUI batches the
                // tick against display refresh; the rest of the
                // overlay (icon glow, cancel button, etc.) does not
                // re-render every tick.
                TimelineView(.periodic(from: startTime, by: 0.28)) { context in
                    let progress = scanProgress(at: context.date)
                    let itemsScanned = Int(Double(totalItems) * progress)
                    let messageIndex = min(Int(progress * Double(statusMessages.count)), statusMessages.count - 1)
                    let statusText = statusMessages[messageIndex]

                    VStack(spacing: 0) {
                        Text(statusText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .contentTransition(.opacity)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                        // Items-count line — `.numericText()` removed.
                        // The previous build crossfaded this number on
                        // every 100ms tick; with the cadence relaxed
                        // and the value visibly sliding upward, a
                        // crossfade adds churn without legibility.
                        Text("\(itemsScanned) items")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(.top, 4)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.04))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.primaryColor.opacity(0.6), Color.primaryColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * progress, height: 4)
                                    .shadow(color: Color.primaryColor.opacity(0.3), radius: 6, y: 0)
                                    .animation(.linear(duration: 0.28), value: progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 60)
                        .padding(.top, 32)

                        // Percent label — `.numericText()` removed for
                        // the same reason. Monospaced design + the
                        // bar's continuous slide convey the reading.
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                            .padding(.top, 12)
                    }
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            glowPulse = true
            appeared = true
            startTime = Date()
        }
        // Single one-shot completion task — replaces the repeating
        // timer's `if progress >= 1.0` branch, so we can't double-fire
        // onComplete if a tick lands past 100%.
        .task {
            try? await Task.sleep(nanoseconds: UInt64(totalDuration * 1_000_000_000) + 300_000_000)
            guard !Task.isCancelled else { return }
            isPresented = false
            onComplete()
        }
    }

    /// Elapsed-time → fraction in [0, 1]. Returns 0 before `startTime`
    /// is set on appear (initial state is `.distantFuture`).
    private func scanProgress(at date: Date) -> Double {
        guard startTime != .distantFuture else { return 0 }
        let elapsed = date.timeIntervalSince(startTime)
        guard elapsed > 0 else { return 0 }
        return min(1.0, elapsed / totalDuration)
    }
}

#Preview {
    ScanningOverlay(isPresented: .constant(true)) {}
        .preferredColorScheme(.dark)
}
