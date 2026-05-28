import SwiftUI

// MARK: - Sort Option
enum SortOption: String, CaseIterable, Identifiable {
    case largest = "Largest"
    case smallest = "Smallest"
    case newest = "Newest"
    case oldest = "Oldest"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .largest: return "arrow.down.circle.fill"
        case .smallest: return "arrow.up.circle.fill"
        case .newest: return "clock.fill"
        case .oldest: return "clock.arrow.circlepath"
        }
    }

    /// Short, scannable byline shown beneath the sort name on the grid
    /// pill. Kept under ~22 chars so the grid lays out at 2 columns
    /// without truncation.
    var byline: String {
        switch self {
        case .largest: return "Biggest first"
        case .smallest: return "Smallest first"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }
}

// MARK: - Compress Filters Sheet
//
// Bitepal-style filter sheet for the Compress tab. Three real
// requirements:
//
//   1. **Looks sleek.** The previous build read as flat-white-on-flat-
//      white with stark "Pick start date" buttons and a generic
//      Apply CTA — visually it had no relationship to the rest of the
//      Compress chrome. This rewrite uses the same chrome-glass
//      lighting the BottomNavBar / merge-preview cards use:
//      gradient body, top rim-light, hairline silhouette, soft
//      shadow, espresso-ink primary. Sort is a 2-col grid of
//      icon-pill cards. Date range is a single inline expander pill.
//
//   2. **Tap-to-apply.** Selection mutates the binding (which the
//      parent reads via `sortedPhotos` / `sortedVideos` recomputed
//      via `.task(id: photoSortKey/videoSortKey)`) IMMEDIATELY. The
//      bottom Done button is just a dismiss — there is no separate
//      "Apply" step and no ambiguity over whether the change took.
//      The Compress tab's sheet detent (540pt + background-interaction
//      enabled) means the grid behind the sheet is visible and the
//      user can SEE the reorder happen as they tap.
//
//   3. **Date pickers don't nest sheets.** Inline graphical
//      DatePicker rendered in-line under the row — no chained
//      `.sheet(isPresented:)`, no `tempStartDate` that fails to
//      seed from the existing binding (prior bug: the wheel always
//      opened on "today" and Done silently no-op'd if the user
//      thought they'd picked a date).
struct CompressFiltersSheet: View {
    @Binding var sortOption: SortOption
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    /// Toggles the inline date-range editor under the date row. False
    /// by default; when the user has set either boundary we surface
    /// the section open on appear so they don't have to tap to see
    /// what they previously picked.
    @State private var dateExpanded: Bool = false

    private let inkColor = Color(hex: "1C1917")
    private let mutedColor = Color(hex: "78716C")
    private let chipColor = Color(hex: "F5F5F4")
    private let cardBorder = Color.black.opacity(0.06)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                topBar
                sortGrid
                dateBlock
                if hasAnyFilter { resetRow }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.background)
        .onAppear {
            // Auto-expand if there's already a value — picks up where
            // the user left off instead of hiding their existing range
            // behind a chevron.
            if startDate != nil || endDate != nil {
                dateExpanded = true
            }
        }
    }

    // MARK: Header

    /// Top bar — drag-handle dot + title on the left, Done button on
    /// the right. Replaces the old "Apply" CTA at the bottom (which
    /// implied the user had to click something for the filter to take
    /// effect).
    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Filter")
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(inkColor)
                Text("Tap a sort or date to apply instantly")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(mutedColor)
            }
            Spacer()
            Button {
                HapticManager.shared.impact(.light)
                dismiss()
            } label: {
                Text(BCLoc.done.tr)
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(inkColor)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Sort Grid

    private var hasAnyFilter: Bool {
        startDate != nil || endDate != nil || sortOption != .largest
    }

    /// 2x2 grid of sort pills. Each tap mutates the binding directly
    /// (no separate Apply step) so the grid behind the sheet visibly
    /// reorders the moment the user picks. The selected pill takes
    /// the espresso ink fill + white glyph; unselected pills sit on
    /// the chip background.
    private var sortGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Sort")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(SortOption.allCases) { option in
                    sortPill(option)
                }
            }
        }
    }

    private func sortPill(_ option: SortOption) -> some View {
        let isSelected = sortOption == option
        return Button {
            HapticManager.shared.impact(.light)
            withAnimation(.easeOut(duration: 0.18)) {
                sortOption = option
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.16) : chipColor)
                        .frame(width: 30, height: 30)
                    Image(systemName: option.icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(isSelected ? .white : inkColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.custom("Poppins-Bold", size: 14))
                        .foregroundColor(isSelected ? .white : inkColor)
                    Text(option.byline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? Color.white.opacity(0.75) : mutedColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isSelected {
                        // Espresso ink with the same lit-from-above
                        // gradient the BottomNavBar uses, so the
                        // selected pill reads as the same family of
                        // chrome rather than a flat black box.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "2C2C2E"),
                                        Color(hex: "0A0A0A")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.8
                            )
                            .blendMode(.plusLighter)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "FAFAFA"))
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(cardBorder, lineWidth: 0.5)
                    }
                }
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.18) : Color.black.opacity(0.04),
                radius: isSelected ? 10 : 3,
                y: isSelected ? 4 : 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Date Block

    /// Single expandable card. Tap the row to reveal the inline
    /// graphical DatePicker pair underneath. NO nested sheet — the
    /// previous build presented date pickers via a chained
    /// `.sheet(isPresented:)` and an unsynced `tempStartDate`, which
    /// silently dropped picks if the user had a date already set.
    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Date range")

            VStack(spacing: 0) {
                // Header row — toggles the expander. Shows the
                // active range as a compact summary so the user
                // knows what's set without opening.
                Button {
                    HapticManager.shared.impact(.light)
                    withAnimation(.easeInOut(duration: 0.22)) {
                        dateExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(chipColor)
                                .frame(width: 30, height: 30)
                            Image(systemName: "calendar")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(inkColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateSummaryTitle)
                                .font(.custom("Poppins-Bold", size: 14))
                                .foregroundColor(inkColor)
                            Text(dateSummaryDetail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(mutedColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: dateExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(mutedColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if dateExpanded {
                    Divider().padding(.horizontal, 12)
                    inlineDatePickers
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "FAFAFA"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardBorder, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        }
    }

    private var dateSummaryTitle: String {
        if startDate == nil && endDate == nil { return "Any date" }
        return "\(formatDate(startDate)) → \(formatDate(endDate))"
    }

    private var dateSummaryDetail: String {
        if startDate == nil && endDate == nil { return "Tap to set start / end" }
        return "Tap to edit · X to clear"
    }

    private var inlineDatePickers: some View {
        VStack(spacing: 8) {
            datePickerRow(
                label: "Start",
                date: $startDate,
                clampedRange: ...((endDate ?? Date.distantFuture))
            )
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 6)
            datePickerRowFrom(
                label: "End",
                date: $endDate,
                clampedRange: (startDate ?? Date.distantPast)...
            )
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func datePickerRow(
        label: String,
        date: Binding<Date?>,
        clampedRange: PartialRangeThrough<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            datePickerHeader(label: label, date: date)
            DatePicker(
                "",
                selection: Binding(
                    get: { date.wrappedValue ?? Date() },
                    set: { date.wrappedValue = $0 }
                ),
                in: clampedRange,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(inkColor)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func datePickerRowFrom(
        label: String,
        date: Binding<Date?>,
        clampedRange: PartialRangeFrom<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            datePickerHeader(label: label, date: date)
            DatePicker(
                "",
                selection: Binding(
                    get: { date.wrappedValue ?? Date() },
                    set: { date.wrappedValue = $0 }
                ),
                in: clampedRange,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(inkColor)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func datePickerHeader(label: String, date: Binding<Date?>) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.custom("Poppins-Bold", size: 11))
                .foregroundColor(mutedColor)
                .tracking(0.5)
            Spacer()
            if date.wrappedValue != nil {
                Button {
                    HapticManager.shared.impact(.light)
                    withAnimation(.easeOut(duration: 0.18)) {
                        date.wrappedValue = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "C7C7CC"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Reset

    private var resetRow: some View {
        Button {
            HapticManager.shared.impact(.medium)
            withAnimation(.easeOut(duration: 0.2)) {
                sortOption = .largest
                startDate = nil
                endDate = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .heavy))
                Text("Reset filters")
                    .font(.custom("Poppins-Bold", size: 14))
            }
            .foregroundColor(Color(hex: "B91C1C"))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule()
                    .fill(Color(hex: "B91C1C").opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.custom("Poppins-Bold", size: 12))
            .foregroundColor(mutedColor)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 4)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "Any" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

#Preview {
    CompressFiltersSheet(
        sortOption: .constant(.largest),
        startDate: .constant(nil),
        endDate: .constant(nil)
    )
}
