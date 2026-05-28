import SwiftUI

// MARK: - Streak Detail View
//
// Presented as a `.sheet` from the home-screen StreakBadge. Dark navy
// canvas, big streak-count headline + flame, then a Sun-start month
// calendar where days with logged activity merge into a single peach
// pill for each contiguous run within a row.
struct StreakDetailView: View {
    /// Optional close handler — when set, a chevron-down dismisses the
    /// sheet. Wired up for the full-screen-cover presentation so the
    /// user has an unambiguous "back" affordance now that drag-down is
    /// gone with the sheet.
    var onClose: (() -> Void)? = nil

    @ObservedObject private var stats = HiveStatsManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var activeDays: Set<DayKey> = []
    @State private var displayedMonth: Date = Calendar.streakCalendar.startOfMonth(for: Date())
    /// Sticky motivational line for this sheet presentation. Picked once
    /// on appear instead of re-rolled inside `body`, so the copy stays
    /// stable through every redraw (theme toggle, stat refresh, scroll)
    /// instead of shuffling on the user mid-read.
    @State private var stickyMotivation: String = ""
    /// Tracks the streak tier we picked the sticky line for. If the user
    /// crosses a tier boundary while the sheet is open, refresh.
    @State private var stickyMotivationStreak: Int = -1

    // Theme-aware palette. Day mode mirrors the BitePal light canvas
    // used by FAQ / Email / More — same surface family across the app.
    // Night mode preserves the existing dark-with-peach-accent identity.
    private var isNight: Bool { theme.isNightMode }

    private var canvas: AnyView {
        if isNight {
            return AnyView(Color.black)
        } else {
            // Cal AI-inspired: pristine near-white canvas, no gradient.
            // The crispness IS the design — let the orange flame and
            // jet-black headline do the visual work.
            return AnyView(Color(hex: "FAFAF8"))
        }
    }

    /// Flame + active-day pill color. Day mode uses the same honey
    /// yellow `#FFC648` as the "Start Quick Cleanup" CTA so the streak
    /// chrome lives in the same color family as the rest of the app
    /// instead of standing out as a foreign orange. Night mode keeps
    /// the existing pale-peach to preserve the dark-mode identity.
    private var accent: Color {
        isNight ? Color(hex: "F2D4B0") : Color(hex: "FFC648")
    }

    /// The big "N day streak" headline color. Peach at night (matches
    /// the flame), jet ink in day mode — Cal AI keeps the count
    /// monochrome and lets the flame carry the chroma.
    private var headlineColor: Color {
        isNight ? Color(hex: "F2D4B0") : Color(hex: "0A0A0A")
    }

    /// Text sitting on top of an active-day pill. Dark ink in both
    /// modes — the honey-yellow day pill and the pale-peach night pill
    /// both need dark text for contrast (matches the "Start Quick
    /// Cleanup" CTA which uses black-on-yellow).
    private var pillInk: Color {
        Color(hex: "1F1F1F")
    }

    /// Day-number color for INACTIVE cells (white at night, near-black
    /// in day mode) so the calendar reads cleanly on either canvas.
    private var inactiveNumberColor: Color {
        isNight ? .white : Color(hex: "111827")
    }

    /// Header / divider / muted text tints, theme-flipped.
    private var headerInk: Color {
        isNight ? .white : Color(hex: "0A0A0A")
    }

    private var mutedText: Color {
        isNight ? Color.white.opacity(0.55) : Color(hex: "6B7280")
    }

    private var weekdayText: Color {
        isNight ? Color.white.opacity(0.5) : Color(hex: "9CA3AF")
    }

    private var hairline: Color {
        isNight ? Color.white.opacity(0.08) : Color(hex: "ECECE7")
    }

    var body: some View {
        ZStack {
            canvas
                .ignoresSafeArea()

            // Glass polish overlay — soft warm radial glow at the top
            // center. In night mode it warms the black canvas with a
            // peach halo behind the streak count + flame; in day mode
            // it's a subtle bright wash that gives the gray gradient
            // some depth instead of reading flat. Same lighting model
            // both ways, just dialed for the canvas underneath.
            RadialGradient(
                colors: [
                    accent.opacity(isNight ? 0.08 : 0),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .blendMode(isNight ? .plusLighter : .normal)

            VStack(alignment: .leading, spacing: 0) {
                if let onClose {
                    Button(action: onClose) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill((isNight ? Color.white : Color.black).opacity(0.32))
                            .frame(width: 38, height: 5)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                headerRow
                    .padding(.horizontal, 24)
                    .padding(.top, onClose == nil ? 24 : 12)
                    .padding(.bottom, 20)

                Rectangle()
                    .fill(hairline)
                    .frame(height: 0.5)

                monthNav
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                MonthStreakCalendar(
                    month: displayedMonth,
                    activeDays: activeDays,
                    accent: accent,
                    pillInk: pillInk,
                    inactiveNumberColor: inactiveNumberColor,
                    weekdayText: weekdayText,
                    flatPill: !isNight
                )
                .padding(.horizontal, 24)

                // Bias the badge slightly above center — the top spacer
                // is unconstrained, the bottom one is capped so the
                // pill sits in the upper third of the void below the
                // calendar instead of dead-centered.
                Spacer(minLength: 0)

                bestStreakBadge
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
                    .frame(maxHeight: 120)
            }
        }
        .task {
            refreshStickyMotivationIfNeeded()
            await loadActiveDays()
        }
        .onChange(of: stats.currentStreak) { _, _ in
            refreshStickyMotivationIfNeeded()
        }
    }

    /// Pick a new motivational line only when the user crosses a tier
    /// boundary (or on first show), so the copy doesn't reshuffle on
    /// every body invalidation.
    private func refreshStickyMotivationIfNeeded() {
        if stickyMotivationStreak == stats.currentStreak && !stickyMotivation.isEmpty {
            return
        }
        stickyMotivation = motivationLine
        stickyMotivationStreak = stats.currentStreak
    }

    // MARK: - Best Streak Badge

    private var bestStreakBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)

            Text("BEST · \(stats.bestStreak) DAY\(stats.bestStreak == 1 ? "" : "S")")
                .font(.custom("Poppins-Bold", size: 15.5))
                .tracking(0.8)
                .foregroundColor(headerInk.opacity(0.92))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(isNight
                      ? Color.white.opacity(0.08)
                      : Color.white)
        )
        .overlay(
            Capsule()
                .stroke(
                    isNight
                        ? Color.white.opacity(0.20)
                        : Color.black.opacity(0.05),
                    lineWidth: isNight ? 0.7 : 0.5
                )
        )
        // Day-mode soft shadow gives the pill the same "floating card"
        // elevation Cal AI uses for its bottom CTAs.
        .shadow(
            color: isNight ? .clear : Color.black.opacity(0.06),
            radius: 14,
            x: 0,
            y: 4
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // Inline streak line — "2 day streak" reads as one
                // continuous phrase on a single row, with the count and
                // the descriptor sharing the same baseline.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(stats.currentStreak)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundColor(headlineColor)
                        .contentTransition(.numericText())
                        .monospacedDigit()

                    Text(stats.currentStreak == 1 ? "day streak" : "day streak")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(headlineColor)
                }
                // Peach halo behind the entire phrase — night mode only.
                // Cal AI's day-mode aesthetic is crisp, not dreamy, so a
                // soft glow under jet-black text would just look smudged.
                .background(
                    accent
                        .opacity(isNight ? 0.18 : 0)
                        .blur(radius: 24)
                        .offset(y: 4)
                )

                Text(stickyMotivation.isEmpty ? motivationLine : stickyMotivation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "flame.fill")
                .font(.system(size: 86, weight: .heavy))
                .foregroundStyle(accent)
                // Halo only at night; in day mode the vivid orange on
                // pristine white reads sharp on its own.
                .background(
                    accent
                        .opacity(isNight ? 0.22 : 0)
                        .blur(radius: 28)
                        .offset(y: 6)
                )
                .padding(.top, 4)
        }
    }

    /// Single-sentence motivational pools per tier. Each line reads as a
    /// complete thought — no more procedural concatenation of three
    /// fragments that landed as choppy and robotic.
    private var motivationLine: String {
        let lines = motivationPool(for: stats.currentStreak)
        return lines.randomElement() ?? lines[0]
    }

    private func motivationPool(for streak: Int) -> [String] {
        switch streak {
        case 0:
            return [
                "Your streak starts with one tap. Pick a category and dive in.",
                "The hive's empty today. One quick sweep gets the flame going.",
                "Bee's waiting on you. A single duplicate is enough to start.",
                "Fresh slate today. Knock out one thing and the streak begins.",
                "No streak yet. That's fine, today's the day to change that.",
                "It only takes one tap to flip this on. Start with photos, easiest win.",
                "Beebuddy is patient, but the hive could use some love today.",
                "Tap any tile below to light the first day of the streak.",
                "Day zero is a great place to start. Pick anything, go.",
                "You're one cleanup away from the streak counter ticking up."
            ]
        case 1:
            return [
                "Day one is in the books. The hard part is showing up tomorrow.",
                "First day locked in. Come back in 24 hours and double it.",
                "You started. Now make it two. That's where the habit actually forms.",
                "One down. Tomorrow is what turns this into a streak you'll defend.",
                "Bee's smiling today. Don't let the flame go out before sunset tomorrow.",
                "The streak begins. The real test is whether you're back tomorrow.",
                "Day 1 was the easy part. Day 2 is what proves you mean it.",
                "Lit the first day. Tomorrow's cleanup seals the second.",
                "First brick laid. Stack another tomorrow and you're rolling.",
                "Streak counter says 1. Let's see it say 2 tomorrow."
            ]
        case 2...6:
            return [
                "\(streak) days in. Momentum is real. Don't break it now.",
                "You're stacking days. Day 7 is the next milestone worth chasing.",
                "The habit's forming. Every day from here makes it harder to quit.",
                "\(streak) consecutive days. This is where most people peel off; you won't.",
                "Bee's buzzing. Keep showing up and this becomes routine.",
                "Multi-day streak going. One more day pushes you past the first week.",
                "You've cleared the early-quit zone. Stay consistent toward day 7.",
                "Day \(streak) feels easy now. That's how the habit takes hold.",
                "Streak's a thing. The bee's keeping score and you're winning.",
                "\(streak) days deep. The chain's getting harder to break the longer it grows."
            ]
        case 7...29:
            return [
                "A full week-plus deep. The hardest part is officially behind you.",
                "\(streak) days. You're cruising past the point most people quit.",
                "Past day 7 means the habit's wired. Push toward 30 from here.",
                "This is what consistency looks like. \(streak) days and counting.",
                "You're in pro mode now. 30 days is the next checkpoint, easy.",
                "Bee respects the grind. \(streak) days of showing up is no joke.",
                "Rhythm-level streak. Two more weeks and you're untouchable.",
                "Past the hard part. Now it's just maintenance toward a month.",
                "\(streak) days strong. You're already in the top 5% of users.",
                "Cruise control. Keep stacking days and the month-mark is yours."
            ]
        case 30...99:
            return [
                "A month-plus deep. This is identity-level commitment now.",
                "\(streak) days locked. The bee bows. You're built different.",
                "Past 30 days is rare air. Push toward triple digits, why stop now?",
                "Bee's in awe. \(streak) consecutive days is sustained excellence.",
                "Compound interest on consistency. \(streak) days makes the next 30 trivial.",
                "Veteran-tier streak. You're the standard for the whole hive.",
                "\(streak) days of pure muscle memory. 100 is in sight.",
                "This is what discipline looks like. \(streak) days, no excuses.",
                "Cruise mode unlocked. You don't even think about the streak anymore.",
                "\(streak)-day streak. Habit isn't a goal anymore, it's who you are."
            ]
        default:
            return [
                "\(streak) days. Legendary. The bee bows down.",
                "Triple digits. Habit isn't real anymore, you are the streak.",
                "\(streak) consecutive days of cleanup. The hive belongs to you.",
                "This isn't discipline, it's gravity. \(streak) days and counting.",
                "Centurion tier. You're the standard for the entire app.",
                "Pure inevitability. \(streak) days of showing up no matter what.",
                "Apex of the hive. The bee follows YOUR lead now.",
                "\(streak) days. There's no breaking this. It's just who you are.",
                "Hall of fame energy. \(streak) days of zero-excuse consistency.",
                "Eternal streak vibes. The flame doesn't go out anymore."
            ]
        }
    }

    // MARK: - Month nav

    private var monthNav: some View {
        HStack(spacing: 16) {
            Text(monthHeaderText(for: displayedMonth))
                .font(.system(size: 16, weight: .heavy))
                .tracking(0.6)
                .foregroundColor(headerInk)

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.arrowNudge(.backward)
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(headerInk.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.arrowNudge(.forward)
                shiftMonth(by: 1)
            } label: {
                ChevronGlyph(tint: headerInk.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func monthHeaderText(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.streakCalendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM ''yy"
        return fmt.string(from: date).uppercased()
    }

    private func shiftMonth(by months: Int) {
        let cal = Calendar.streakCalendar
        if let next = cal.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = cal.startOfMonth(for: next)
        }
    }

    // MARK: - Data

    private func loadActiveDays() async {
        // Network fetch first (StreakService is its own actor / async).
        let entries = await StreakService.shared.fetchActivities(limit: 365)
        let span = max(stats.currentStreak, 0)

        // All the calendar arithmetic moves off MainActor — a 365-entry
        // activity log + a 100+ day streak guarantee would otherwise
        // burn ~500+ `Calendar.dateComponents` calls on main while the
        // sheet animates in.
        let finalKeys: Set<DayKey> = await Task.detached(priority: .userInitiated) {
            let cal = Calendar.streakCalendar
            var keys: Set<DayKey> = []
            for entry in entries {
                guard let date = entry.date,
                      entry.bytesSaved > 0 || entry.itemCount > 0
                else { continue }
                let c = cal.dateComponents([.year, .month, .day], from: date)
                if let y = c.year, let m = c.month, let d = c.day {
                    keys.insert(DayKey(year: y, month: m, day: d))
                }
            }
            let today = Date()
            for offset in 0..<span {
                if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                    let c = cal.dateComponents([.year, .month, .day], from: d)
                    if let y = c.year, let m = c.month, let day = c.day {
                        keys.insert(DayKey(year: y, month: m, day: day))
                    }
                }
            }
            return keys
        }.value

        await MainActor.run { self.activeDays = finalKeys }
    }
}

// MARK: - Day key (Hashable y/m/d so we can Set-lookup active dates)

struct DayKey: Hashable {
    let year: Int
    let month: Int
    let day: Int
}

// MARK: - Month calendar with contiguous-run pills

private struct MonthStreakCalendar: View {
    let month: Date
    let activeDays: Set<DayKey>
    let accent: Color
    let pillInk: Color
    let inactiveNumberColor: Color
    let weekdayText: Color
    var flatPill: Bool = false

    private let cal = Calendar.streakCalendar
    private let cellHeight: CGFloat = 46
    // Tight uniform spacing — same pixel gap between every week row.
    private let rowSpacing: CGFloat = 4

    /// DayKey for "today" so we can ring the current day inside the
    /// calendar. Renders on top of both an active-day pill (current
    /// streak end) and a bare date (no activity logged today yet).
    private var todayKey: DayKey {
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return DayKey(
            year: c.year ?? 0,
            month: c.month ?? 0,
            day: c.day ?? 0
        )
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            // Weekday header (Sun-start) — slightly brighter, uppercase
            // tracking so it reads as a labeled axis rather than a fading
            // afterthought.
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(weekdayText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)

            // Date rows
            ForEach(weekRows.indices, id: \.self) { rowIndex in
                weekRow(weekRows[rowIndex])
            }
        }
    }

    // Sun, Mon, Tue, Wed, Thu, Fri, Sat
    private var weekdaySymbols: [String] {
        let raw = cal.shortStandaloneWeekdaySymbols // ["Sun","Mon",...] with firstWeekday=1
        // Rotate so the first symbol matches cal.firstWeekday (already 1 = Sun for streakCalendar)
        return raw
    }

    /// 2D grid of cells, padded with nil for the leading days before
    /// the 1st of `month`. Each row is exactly 7 entries.
    private var weekRows: [[CalCell?]] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard
            let year = comps.year,
            let monthNum = comps.month,
            let firstOfMonth = cal.date(from: comps),
            let range = cal.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }

        // weekday(1...7) — Sun = 1 in streakCalendar
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadingBlanks = firstWeekday - cal.firstWeekday

        var cells: [CalCell?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            let key = DayKey(year: year, month: monthNum, day: day)
            cells.append(CalCell(day: day, key: key, active: activeDays.contains(key)))
        }
        // Pad trailing nils so the final row has 7 entries
        let trailing = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailing))

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<$0+7])
        }
    }

    private func weekRow(_ row: [CalCell?]) -> some View {
        // Compute contiguous active runs in this row so we can render a
        // single capsule background that spans the whole run rather than
        // a separate pill behind each day.
        let runs = activeRuns(in: row)
        // HStack-driven layout (no GeometryReader on the row's primary
        // axis). Every cell takes `.frame(maxWidth: .infinity, height: cellHeight)`
        // so the row's height is mathematically pinned to `cellHeight`
        // and the VStack above gets a perfectly uniform gap between
        // every week. The pill is overlaid via `.background` using a
        // GeometryReader scoped to the HStack's measured width — that
        // reader can't bleed into the row's height.
        return HStack(spacing: 0) {
            ForEach(row.indices, id: \.self) { i in
                cellView(row[i])
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
            }
        }
        .background(alignment: .leading) {
            GeometryReader { geo in
                let cellWidth = geo.size.width / 7
                ZStack(alignment: .leading) {
                    ForEach(runs, id: \.startIndex) { run in
                        Capsule()
                            .fill(
                                flatPill
                                    ? AnyShapeStyle(accent)
                                    : AnyShapeStyle(LinearGradient(
                                        colors: [accent, accent.opacity(0.86)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                            )
                            .overlay(
                                // Glassy edge highlight reads great over
                                // a dark canvas; on a bright orange pill
                                // against white it just looks washed out.
                                // Skip it in flat (day-mode) mode.
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(flatPill ? 0 : 0.45),
                                                Color.white.opacity(0.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .center
                                        ),
                                        lineWidth: 0.7
                                    )
                                    .blendMode(.plusLighter)
                            )
                            .frame(
                                width: cellWidth * CGFloat(run.length),
                                height: cellHeight - 6
                            )
                            .offset(
                                x: cellWidth * CGFloat(run.startIndex),
                                y: 3
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: CalCell?) -> some View {
        if let cell {
            // Today is no longer marked with a separate white disc —
            // the peach pill across active days IS the "you are here"
            // anchor (today is always the rightmost day of the run).
            // The dark ink on active days carries the read.
            Text("\(cell.day)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(cell.active ? pillInk : inactiveNumberColor)
        } else {
            Color.clear
        }
    }

    private func activeRuns(in row: [CalCell?]) -> [Run] {
        var runs: [Run] = []
        var i = 0
        while i < row.count {
            if let cell = row[i], cell.active {
                let start = i
                while i < row.count, let c = row[i], c.active { i += 1 }
                runs.append(Run(startIndex: start, length: i - start))
            } else {
                i += 1
            }
        }
        return runs
    }
}

private struct CalCell {
    let day: Int
    let key: DayKey
    let active: Bool
}

private struct Run {
    let startIndex: Int   // 0..6 column
    let length: Int       // consecutive active cells
}

// MARK: - Sun-start calendar helper

private extension Calendar {
    /// Sun-start Gregorian calendar — matches the mockup's "Sun Mon Tue …"
    /// header regardless of the device's regional locale.
    static let streakCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    func startOfMonth(for date: Date) -> Date {
        self.date(from: self.dateComponents([.year, .month], from: date)) ?? date
    }
}

#Preview {
    StreakDetailView()
}
