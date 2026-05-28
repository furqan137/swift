import SwiftUI

// MARK: - Storage Overview Card
/// Premium storage dashboard card showing cleanable space with an animated ring,
/// category progress bars, and a green status footer.
struct HiveScoreCard: View {
    let stage: BeeStage
    let clutterBytes: Int64
    /// Optional override — if `nil`, headline is derived from `stage`.
    private let headlineOverride: String?

    @Environment(SimilarPhotosStore.self) private var similarVM
    @ObservedObject private var statsManager = HiveStatsManager.shared

    @AppStorage("beeclean.peakClutterBytes") private var peakClutterBytesRaw: Double = 0

    private var peakClutterBytes: Int64 {
        get { Int64(peakClutterBytesRaw) }
    }

    @State private var animatedProgress: CGFloat = 0
    @State private var totalBytes: Int64 = 0
    @State private var availableBytes: Int64 = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    // Auto-rescan paths are owned exclusively by SimilarPhotosStore.bootstrap
    // (called from ChargingView.task). bootstrap() loads the persisted cache
    // FIRST and only runs a full scan when the cache is empty — so the user
    // sees populated cards on every relaunch, never a fresh "Scanning…"
    // pass over the whole library. This card used to call its own scan
    // trigger from .onAppear, which fired SYNCHRONOUSLY and beat bootstrap's
    // async cache-load to the punch on every cold launch — flipping the
    // `Scanning…` state on every category card even though valid cached
    // groups were about to be hydrated milliseconds later.

    private let ringSize: CGFloat = 68
    private let ringStroke: CGFloat = 6.5

    // Clean state requires literally zero detected clutter. The scanner is always
    // running, so this is intentionally hard to reach — the ring keeps the user
    // engaged with ongoing work rather than prematurely rewarding.
    private let cleanThresholdBytes: Int64 = 1

    init(
        stage: BeeStage = .stage1,
        clutterBytes: Int64 = 0,
        headline: String? = nil
    ) {
        self.stage = stage
        self.clutterBytes = clutterBytes
        self.headlineOverride = headline
    }

    private var headline: String { headlineOverride ?? BCLoc.spaceToClean.tr }

    /// True when there's enough cleanable storage to warn the user with a red
    /// pulse and an unclean copy. Either: bee is locked at stage1 OR clutter
    /// crosses the absolute "too much" floor (5 GB).
    private var isUnclean: Bool {
        stage.isUnclean || clutterBytes > BeeStage.tooMuchCleanBytes
    }

    var body: some View {
        cardContent
        .frame(maxWidth: .infinity)
        .onAppear {
            loadDeviceStorage()
            updatePeakClutter()
            withAnimation(.easeOut(duration: 1.4).delay(0.2)) {
                animatedProgress = clutterFraction
            }
        }
        // Single consolidated handler — the two values fire together
        // during a delete (selection grows, clutter shrinks), and the
        // previous pair of identical onChange handlers scheduled two
        // overlapping `withAnimation` passes whose springs fought each
        // other and produced visible micro-judder. One composite signal
        // = one animation, one disk-storage refresh, one peak update.
        .onChange(of: "\(clutterBytes)|\(similarVM.totalBytesSaved)") { _, _ in
            updatePeakClutter()
            loadDeviceStorage()
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = clutterFraction
            }
        }
        .onChange(of: similarVM.isScanning) { _, scanning in
            // When a scan finishes, grab updated disk numbers for the gauge.
            if !scanning {
                loadDeviceStorage()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // App came back to foreground — refresh the device storage
            // numbers so the disk gauge matches reality, but do NOT kick
            // off a passive rescan. The user explicitly asked to stop the
            // background-rescan-on-return behaviour; they only want a scan
            // to run on first launch (until hasCompletedScan flips true)
            // and on explicit pull-to-refresh.
            if phase == .active {
                loadDeviceStorage()
                // Refresh hive stats cache asynchronously to avoid blocking scene update
                Task { await HiveStatsManager.shared.refreshPendingItemCount() }
            }
        }
    }

    private var cardContent: some View {
        VStack(spacing: 16) {
            // ── Top section: metric + ring ──
            topSection

            // ── Storage runway forecast ──
            // REPLACES the prior "Clutter / Used / Total" stat bars
            // (the old "tangible benefits" element). The runway is the
            // single piece of storage information the user actually
            // needs to act on — "when does my phone fill up" — and
            // cleaning visibly extends the date.
            StorageRunwayCard()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .background(glassSurface)
        .shadow(
            color: isUnclean ? Color.destructive.opacity(0.18) : Color.black.opacity(0.08),
            radius: isUnclean ? 20 : 14,
            x: 0,
            y: isUnclean ? 8 : 6
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        // Crossfade the stage-driven look (border tint, shadow, headline
        // color, unclean state) instead of snapping when BeeViewModel
        // evolves/devolves the stage.
        .animation(.easeInOut(duration: 0.45), value: stage)
        .animation(.easeInOut(duration: 0.45), value: isUnclean)
    }

    // MARK: - Glass Surface
    //
    // Same white→warm-off-white gradient + top sheen as the GlassPanel
    // primitive used by every other card on the homepage (photo/video
    // rows, segmented control, cleanup rows). HiveScoreCard keeps its
    // own surface (rather than using GlassPanel directly) only because
    // its outer stroke is state-aware — gold normally, destructive when
    // unclean — and that branch must stay locally controlled.
    private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
        // Adaptive surface fill — light keeps the warm off-white wash
        // the design started with; dark switches to a lifted slate so
        // the card reads on the polished glass canvas of the dashboard.
        let fillGradient: LinearGradient = colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "1B1C21"), Color(hex: "131418")],
                startPoint: .top,
                endPoint: .bottom)
            : LinearGradient(
                colors: [Color.white, Color(hex: "F2F3F5")],
                startPoint: .top,
                endPoint: .bottom)
        return ZStack {
            shape.fill(fillGradient)

            // State-aware outer stroke: gold normally, destructive when
            // unclean. Border helper already handles dark via its own
            // adaptive branch below.
            shape.stroke(glassBorderGradient, lineWidth: 1.1)
        }
        .compositingGroup()
    }

    private var glassBorderGradient: LinearGradient {
        if isUnclean {
            return LinearGradient(
                colors: [
                    Color.destructive.opacity(0.38),
                    Color.destructive.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color(hex: "CFAF5F").opacity(0.22),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                Color(hex: "CFAF5F").opacity(0.55),
                Color(hex: "7A5C2E").opacity(0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Top Section

    private var topSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.custom("Poppins-Bold", size: 11.5))
                    .foregroundColor(QuickAccessCard.headerColor)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .lineLimit(1)

                // Storage value stays in foreground even when unclean — keeps
                // the number readable. The headline + status footer carry the
                // red signal so the eye still gets the alarm.
                Text(formatStorageValue(clutterBytes))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(Color.foreground)
                    .tracking(-1.2)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            storageRing
        }
    }

    // MARK: - Storage Ring

    private var storageRing: some View {
        // Liquid-glass disc — mirrors the exact layer stack the card
        // itself uses (`glassSurface` above), scaled to a circle: frosted
        // material base, soft white tint for body luminosity, top
        // specular highlight fading to clear with `.plusLighter`, and a
        // hairline white→transparent stroke sealing the edge. Pure
        // light-mode white glass, no coloured ring, no colored arc.
        ZStack {
            // 0. Opaque backing — prevents the card's destructive shadow
            //    from bleeding through the translucent material layers.
            Circle()
                .fill(Color.white)

            // 1. Frosted base
            Circle()
                .fill(.ultraThinMaterial)

            // 2. White body tint — lifts the glass so it reads luminous
            //    rather than muddy grey.
            Circle()
                .fill(Color.white.opacity(0.22))

            // 3. Top specular highlight — additive light catching the
            //    upper arc of the disc.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.9)

            // 4. Inner edge highlight — additive rim light that gives
            //    the glass its "polished" feel.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)

            // 5. Hairline border — the neutral outer seal.
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)

            // 6. Center glyph — grey storage-drive disc by default,
            //    green check once the phone is fully clean.
            Image(systemName: isClean ? "checkmark" : "externaldrive.fill")
                .font(.system(size: isClean ? 22 : 20, weight: isClean ? .bold : .semibold))
                .foregroundColor(
                    isClean
                        ? Color.success
                        : Color.mutedForeground.opacity(0.75)
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: ringSize, height: ringSize)
        .compositingGroup()
        .shadowSm()
    }

    // MARK: - Stat Bars Section

    private var statBarsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            StatBarColumn(
                color: Color.destructive,
                label: "Clutter",
                value: formatCompact(clutterBytes),
                progress: usedBytes > 0
                    ? CGFloat(clutterBytes) / CGFloat(usedBytes)
                    : 0
            )

            StatBarColumn(
                color: Color.accentColor,
                label: "Used",
                value: formatCompact(usedBytes),
                progress: totalBytes > 0
                    ? CGFloat(usedBytes) / CGFloat(totalBytes)
                    : 0
            )

            StatBarColumn(
                // Emerald — distinct from the red Clutter and amber Used
                // dots so the three metrics read at a glance as a real
                // traffic-light trio instead of "two colors and a fade".
                color: Color(hex: "10B981"),
                label: "Total",
                value: formatCompact(totalBytes),
                progress: 1.0
            )
        }
    }

    // MARK: - Data

    private var usedBytes: Int64 {
        max(totalBytes - availableBytes, 0)
    }

    /// Fraction of the ring that should be filled.
    /// Measures remaining clutter against the peak clutter seen (the baseline established
    /// by the most recent scan). As the user cleans, this drains from 1.0 toward 0.
    private var clutterFraction: CGFloat {
        if isClean { return 0 }
        guard peakClutterBytes > 0 else { return 0 }
        let fraction = CGFloat(clutterBytes) / CGFloat(peakClutterBytes)
        return min(max(fraction, 0), 1)
    }

    private var isClean: Bool {
        clutterBytes < cleanThresholdBytes
    }

    /// Two-stop gradient keyed to the current bee stage. Shifts through
    /// red → orange → honey → lime → green as the user cleans, so the ring
    /// colour is the primary visual signal for stage progression.
    private var ringGradientColors: [Color] {
        if isClean {
            return [Color(hex: "34D399"), Color(hex: "10B981")]
        }
        // Hue: green=0.33 at empty, red=0.0 at full. Animated progress
        // drives the colour so as the user cleans the arc slides from
        // red → amber → green, matching the original ring design.
        let t = Double(min(max(animatedProgress, 0), 1))
        let hue = 0.33 - 0.33 * t
        let light = Color(hue: hue, saturation: 0.78, brightness: 0.95)
        let deep  = Color(hue: hue, saturation: 0.92, brightness: 0.78)
        return [light, deep]
    }

    // (Stage-keyed palette/glyph helpers were removed — the ring now uses
    // a neutral storage-drive icon and the card communicates stage through
    // border tint + headline color via `isUnclean`.)

    /// Establishes / updates the baseline the ring drains against.
    /// Peak is raised when a scan discovers more clutter, and reset once the user
    /// is below the clean threshold so the next scan becomes the new baseline.
    private func updatePeakClutter() {
        if clutterBytes > peakClutterBytes {
            peakClutterBytesRaw = Double(clutterBytes)
        } else if isClean {
            peakClutterBytesRaw = 0
        }
    }

    private func loadDeviceStorage() {
        // DeviceStorage helper = single source of truth shared with
        // StorageForecastManager. Off-main read via .utility detached task.
        Task {
            let snap = await DeviceStorage.readAsync()
            totalBytes = snap.total
            availableBytes = snap.free
            // Feed the forecast as well so runway always sees fresh free-byte readings.
            StorageForecastManager.shared.recordSnapshot(free: snap.free)
        }
    }

    // MARK: - Formatting

    private func formatStorageValue(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
        if bytes < 1_000_000 {
            return "\(bytes / 1_000) KB"
        } else if bytes < 1_000_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1f MB", mb)
        } else {
            let gb = Double(bytes) / 1_000_000_000.0
            return String(format: "%.1f GB", gb)
        }
    }

    private func formatCompact(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 MB" }
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

// MARK: - Stat Bar Column

private struct StatBarColumn: View {
    let color: Color
    let label: String
    let value: String
    let progress: CGFloat

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(label)
                    .font(.custom("Poppins-Bold", size: 11))
                    .foregroundColor(Color.mutedForeground)
                    .tracking(0.2)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mutedForeground.opacity(0.14))
                        .frame(height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.85), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * min(max(animatedProgress, 0), 1),
                            height: 5
                        )
                }
            }
            .frame(height: 5)

            Text(value)
                .font(.custom("Poppins-SemiBold", size: 14.5))
                .foregroundColor(Color.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.4)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HiveScoreCard(stage: .stage1, clutterBytes: 6_000_000_000)
        HiveScoreCard(stage: .stage3, clutterBytes: 600_000_000)
        HiveScoreCard(stage: .stage5, clutterBytes: 0)
    }
    .padding(.vertical, 40)
    .background(Color.background)
}
