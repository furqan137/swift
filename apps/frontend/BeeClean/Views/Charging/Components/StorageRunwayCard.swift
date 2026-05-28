import SwiftUI

// MARK: - Storage Runway Card
/// Compact runway-forecast element that lives inside the Hive card.
/// Replaces the older "tangible benefits" tile with a real, data-driven
/// projection of when the user's phone will run out of space. Cleaning
/// visibly pushes the projection out — that's the whole feedback loop.
struct StorageRunwayCard: View {

    @ObservedObject private var forecastManager = StorageForecastManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerStack
            runwayBar
            subLine
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45),
                   value: tierColor)
    }

    // MARK: - Header

    /// Label row + headline number stacked. Label sits on its own line at
    /// the top; the number gets the bulk of the visual weight underneath.
    private var headerStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headlineLabel)
                    .font(.custom("Poppins-Bold", size: 11))
                    .foregroundColor(Color.mutedForeground)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Brief "+N days" accent after a cleanup. Renders only
                // when the manager surfaces a positive delta — manager
                // schedules its own cleardown after a few seconds.
                if forecastManager.runwayDeltaDays > 0 {
                    Text("+\(forecastManager.runwayDeltaDays) days")
                        .font(.custom("Poppins-SemiBold", size: 11))
                        .foregroundColor(Color(hex: "10B981"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(hex: "10B981").opacity(0.14))
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35),
                       value: forecastManager.runwayDeltaDays)

            Text(headlineNumber)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Runway bar

    @ViewBuilder
    private var runwayBar: some View {
        switch forecastManager.forecast {
        case .calibrating:
            calibratingIndicator
        case .stable:
            stableIndicator
        case .days:
            daysBar
        }
    }

    private var daysBar: some View {
        GeometryReader { geo in
            let frac = freeFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.mutedForeground.opacity(0.14))
                    .frame(height: 6)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tierColor.opacity(0.85), tierColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geo.size.width * frac,
                        height: 6
                    )
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: frac)
            }
        }
        .frame(height: 6)
    }

    private var calibratingIndicator: some View {
        // Subtle indeterminate hint — soft pulsing capsule. No fake
        // progress value, never reads as a real measurement.
        Capsule()
            .fill(Color.mutedForeground.opacity(0.18))
            .frame(height: 6)
            .modifier(PulseOpacityModifier(active: !reduceMotion))
    }

    private var stableIndicator: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "10B981").opacity(0.65),
                        Color(hex: "10B981")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 6)
    }

    // MARK: - Sub-line

    private var subLine: some View {
        Text(subLineText)
            .font(.custom("Poppins-Regular", size: 12))
            .foregroundColor(Color.mutedForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    // MARK: - Surface
    //
    // Mirrors the GlassPanel look used by sibling components (soft
    // white fill, hairline stroke, gentle shadow) so this card reads as
    // part of the same family inside the Hive card.

    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        let fill: LinearGradient = colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "1F2026"), Color(hex: "16171B")],
                startPoint: .top,
                endPoint: .bottom)
            : LinearGradient(
                colors: [Color.white, Color(hex: "F6F4EF")],
                startPoint: .top,
                endPoint: .bottom)
        return ZStack {
            shape.fill(fill)
            shape.stroke(
                tierColor.opacity(colorScheme == .dark ? 0.38 : 0.22),
                lineWidth: 1
            )
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
            radius: 6, x: 0, y: 2
        )
    }

    // MARK: - State-driven content

    private var headlineLabel: String {
        switch forecastManager.forecast {
        case .calibrating: return "STORAGE RUNWAY"
        case .stable:      return "STORAGE RUNWAY"
        case .days:        return "PHONE FULL IN"
        }
    }

    private var headlineNumber: String {
        switch forecastManager.forecast {
        case .calibrating:
            return "Learning your pace…"
        case .stable:
            return "You're gaining space — nice."
        case .days(let n, let conf):
            let label = displayDays(n)
            // Confidence hedge — keep wording neutral on low conf so the
            // user doesn't anchor on a still-rough estimate.
            return conf == .high ? label : "~\(label)"
        }
    }

    private var subLineText: String {
        let free = formatBytes(forecastManager.displayedFreeBytes)
        switch forecastManager.forecast {
        case .calibrating:
            return "\(free) free · BeeClean is tracking your usage"
        case .stable:
            return "\(free) free · holding steady"
        case .days:
            let rate = formatBytes(forecastManager.fillRatePerDay)
            return "\(free) free · filling ~\(rate)/day"
        }
    }

    private var tierColor: Color {
        switch forecastManager.forecast {
        case .calibrating:
            return Color.mutedForeground
        case .stable:
            return Color(hex: "10B981")
        case .days(let n, _):
            if n < 7  { return Color.destructive }       // urgent red
            if n <= 30 { return Color(hex: "F59E0B") }    // amber warning
            return Color(hex: "10B981")                   // emerald calm
        }
    }

    /// How much of the bar is "currently free". Anchored to the runway
    /// ceiling so the bar reads as "lots of room left" near the cap and
    /// nearly empty near zero days.
    private var freeFraction: CGFloat {
        guard case let .days(n, _) = forecastManager.forecast else { return 0 }
        let pct = CGFloat(n) / CGFloat(StorageForecastEstimator.maxDisplayDays)
        return min(max(pct, 0.04), 1.0)
    }

    /// Cap absurd day counts at "6+ months" so the UI never renders a
    /// physically meaningless integer (1200 days, etc.).
    private func displayDays(_ n: Int) -> String {
        if n >= StorageForecastEstimator.maxDisplayDays {
            return "6+ months"
        }
        if n <= 1 { return "1 day" }
        return "\(n) days"
    }

    private var accessibilityDescription: String {
        switch forecastManager.forecast {
        case .calibrating:
            return "Storage runway: BeeClean is still learning your usage pace."
        case .stable:
            return "Storage runway is stable. You're gaining or holding space."
        case .days(let n, _):
            let free = formatBytes(forecastManager.displayedFreeBytes)
            let rate = formatBytes(forecastManager.fillRatePerDay)
            return "Storage runway: phone projected to be full in about \(displayDays(n)). " +
                   "\(free) free, filling about \(rate) per day."
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else if bytes < 1_000_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.0f MB", mb)
        } else {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.1f GB", gb)
        }
    }
}

// MARK: - Helpers

/// Subtle pulsing-opacity modifier for the calibrating indicator.
/// Respects ReduceMotion by collapsing to a static low-opacity capsule
/// when `active == false`.
private struct PulseOpacityModifier: ViewModifier {
    let active: Bool
    @State private var on: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 1.0 : 0.55) : 0.7)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 24) {
        StorageRunwayCard()
    }
    .padding(20)
    .background(Color.background)
}
