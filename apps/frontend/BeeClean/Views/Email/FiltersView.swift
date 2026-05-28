import SwiftUI

// MARK: - Filters View
//
// Cleanup-targeted email filter. BitePal-style: a single sheet that
// pairs one-tap presets with the 6 dimensions users actually tune:
//
//   0. PRESET      — Old & big · Stale unread · Heavy attachments · Ancient
//   1. WHEN        — Older than 1w / 1m / 6m / 1y
//   2. STATUS      — Any / Unread / Read
//   3. SIZE        — Any / 1 MB+ / 5 MB+ / 10 MB+
//   4. ATTACHMENTS — Any / With / Without
//   5. PROTECT     — Keep starred mail safe (default ON)
//   6. SORT BY     — Newest / Oldest
//
// The apply bar shows "Applying to N emails in {Category}" when the
// parent passes `categoryHint` + `categoryTotal`, so the filter feels
// bound to a real list. Hidden `EmailFilters` fields (sender/subject
// text, keyword lists) are left alone on Apply so programmatic setters
// (Quick Clean) don't get silently wiped.
struct FiltersView: View {
    @Binding var filters: EmailFilters
    /// Optional category context — when passed, the apply bar shows
    /// "Apply to N emails in {Category}" so the user feels the filter
    /// is bound to a real list, not floating in the abstract.
    var categoryHint: String? = nil
    var categoryTotal: Int? = nil
    @Environment(\.dismiss) private var dismiss

    // MARK: - Preset combinations
    //
    // Named one-tap combos for the cleanups users actually run. Tapping
    // a preset sets every dimension at once. Selecting "Custom" leaves
    // the dimensions alone — it's just the deselected/empty state.
    enum FilterPreset: String, CaseIterable, Identifiable {
        case custom        = "Custom"
        case oldAndBig     = "Old & big"
        case staleUnread   = "Stale unread"
        case heavyAttach   = "Heavy attach"
        case ancient       = "Ancient"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .custom:      return "slider.horizontal.3"
            case .oldAndBig:   return "archivebox.fill"
            case .staleUnread: return "envelope.badge.fill"
            case .heavyAttach: return "paperclip.circle.fill"
            case .ancient:     return "calendar.badge.clock"
            }
        }
        var subtitle: String {
            switch self {
            case .custom:      return "Tune below"
            case .oldAndBig:   return "30d+ · 1 MB+"
            case .staleUnread: return "Unread · 1 mo+"
            case .heavyAttach: return "5 MB+"
            case .ancient:     return "1 year+"
            }
        }
    }

    enum AttachmentChoice: String, CaseIterable, Identifiable {
        case any  = "Any"
        case with = "With attachments"
        case none = "No attachments"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .any:  return "tray.full"
            case .with: return "paperclip"
            case .none: return "paperclip.badge.ellipsis"
            }
        }
        static func from(_ flag: Bool?) -> AttachmentChoice {
            switch flag {
            case .some(true):  return .with
            case .some(false): return .none
            default:           return .any
            }
        }
        var model: Bool? {
            switch self {
            case .any:  return nil
            case .with: return true
            case .none: return false
            }
        }
    }

    enum TimeChoice: String, CaseIterable, Identifiable {
        case all      = "All time"
        case week     = "Older than 1 week"
        case month    = "Older than 1 month"
        case sixMo    = "Older than 6 months"
        case year     = "Older than 1 year"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .all:   return nil
            case .week:  return 7
            case .month: return 30
            case .sixMo: return 180
            case .year:  return 365
            }
        }
        var icon: String {
            switch self {
            case .all:   return "infinity"
            case .week:  return "calendar"
            case .month: return "calendar"
            case .sixMo: return "calendar"
            case .year:  return "calendar.badge.clock"
            }
        }
    }

    enum ReadState: String, CaseIterable, Identifiable {
        case any    = "Any"
        case unread = "Unread"
        case read   = "Read"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .any:    return "Both read and unread"
            case .unread: return "Skipped, never opened"
            case .read:   return "Already viewed"
            }
        }
    }

    enum SizeChoice: String, CaseIterable, Identifiable {
        case any   = "Any size"
        case mb1   = "Over 1 MB"
        case mb5   = "Over 5 MB"
        case mb10  = "Over 10 MB"
        var id: String { rawValue }
        var model: EmailFilters.SizeFilter {
            switch self {
            case .any:  return .any
            case .mb1:  return .large
            case .mb5:  return .huge
            case .mb10: return .huge
            }
        }
        static func from(_ s: EmailFilters.SizeFilter) -> SizeChoice {
            switch s {
            case .large: return .mb1
            case .huge:  return .mb5
            default:     return .any
            }
        }
        var icon: String {
            switch self {
            case .any:  return "tray.full"
            case .mb1:  return "doc.fill"
            case .mb5:  return "doc.zipper"
            case .mb10: return "doc.zipper"
            }
        }
    }

    // MARK: - State

    @State private var timeChoice: TimeChoice = .all
    @State private var readState: ReadState = .any
    @State private var sizeChoice: SizeChoice = .any
    @State private var attachmentChoice: AttachmentChoice = .any
    @State private var protectStarred: Bool = true
    @State private var sortOrder: EmailFilters.SortOrder = .newest
    @State private var activePreset: FilterPreset = .custom

    // MARK: - Design tokens

    private let bg            = Color.white
    private let card          = Color(hex: "F5F5F7")
    private let cardBorder    = Color.black.opacity(0.05)
    private let ink           = Color(hex: "1C1917")
    private let inkMuted      = Color(hex: "78716C")
    private let labelMuted    = Color(hex: "9E9CA0")
    private let pillFill      = Color(hex: "EFEFF2")
    private let pillSelected  = Color(hex: "1C1917")
    private let accentAmber   = Color(hex: "F59E0B")

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 26) {
                        presetSection
                        timeSection
                        readStateSection
                        sizeSection
                        attachmentSection
                        protectSection
                        sortSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)

                applyBar
            }
        }
        .presentationBackground(bg)
        .environment(\.colorScheme, .light)
        .onAppear { loadCurrentFilters() }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(BCLoc.filters.tr)
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(ink)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(card))
                }
                Spacer()
                Button {
                    HapticManager.shared.impact(.light)
                    resetAll()
                } label: {
                    Text("Reset")
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(isDefault ? labelMuted : ink)
                }
                .disabled(isDefault)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 48)
    }

    // MARK: - Apply bar

    private var applyBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)

            VStack(spacing: 8) {
                if let hint = scopeHint {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(inkMuted)
                        Text(hint)
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(inkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                Button {
                    HapticManager.shared.impact(.medium)
                    applyFilters()
                    dismiss()
                } label: {
                    Text(applyButtonLabel)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(ink)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(bg)
    }

    private var applyButtonLabel: String {
        let n = activeCount
        if n == 0 { return "Show all" }
        return "Apply \(n) filter\(n == 1 ? "" : "s")"
    }

    /// "Apply to 5,226 emails in Promotions" — surfaces the scope so the
    /// filter sheet doesn't feel disconnected from the list behind it.
    private var scopeHint: String? {
        guard let name = categoryHint else { return nil }
        if let total = categoryTotal, total > 0 {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal)
            return "Applying to \(formatted) emails in \(name)"
        }
        return "Applying to \(name)"
    }

    // MARK: - Preset section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("QUICK PRESETS")
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .tracking(0.8)
                    .foregroundColor(labelMuted)
                Spacer()
                if activePreset != .custom {
                    Text(activePreset.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(inkMuted)
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterPreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func presetChip(_ preset: FilterPreset) -> some View {
        let selected = activePreset == preset
        return Button {
            HapticManager.shared.impact(.medium)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                applyPreset(preset)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: preset.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(preset.rawValue)
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(selected ? .white : ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selected ? pillSelected : card)
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.clear : cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// One-tap combo loader. Maps each preset to a coherent set of
    /// dimension values. "Custom" only clears the preset tag — leaves
    /// dimensions alone so the user can tune from where they are.
    private func applyPreset(_ preset: FilterPreset) {
        activePreset = preset
        switch preset {
        case .custom:
            return
        case .oldAndBig:
            timeChoice = .month
            sizeChoice = .mb1
            attachmentChoice = .any
            readState = .any
            protectStarred = true
            sortOrder = .newest
        case .staleUnread:
            timeChoice = .month
            sizeChoice = .any
            attachmentChoice = .any
            readState = .unread
            protectStarred = true
            sortOrder = .oldest
        case .heavyAttach:
            timeChoice = .all
            sizeChoice = .mb5
            attachmentChoice = .with
            readState = .any
            protectStarred = true
            sortOrder = .newest
        case .ancient:
            timeChoice = .year
            sizeChoice = .any
            attachmentChoice = .any
            readState = .any
            protectStarred = true
            sortOrder = .oldest
        }
    }

    // MARK: - Attachment section

    private var attachmentSection: some View {
        sectionCard(
            kicker: "ATTACHMENTS",
            title: "Attachment filter",
            subtitle: "Target — or skip — emails with files."
        ) {
            VStack(spacing: 8) {
                ForEach(AttachmentChoice.allCases) { choice in
                    iconPillRow(
                        icon: choice.icon,
                        label: choice.rawValue,
                        isSelected: attachmentChoice == choice
                    ) {
                        HapticManager.shared.impact(.light)
                        attachmentChoice = choice
                        activePreset = .custom
                    }
                }
            }
        }
    }

    // MARK: - Section 1: WHEN

    private var timeSection: some View {
        sectionCard(
            kicker: "WHEN",
            title: "How old?",
            subtitle: "Only show emails older than this."
        ) {
            VStack(spacing: 8) {
                ForEach(TimeChoice.allCases) { choice in
                    iconPillRow(
                        icon: choice.icon,
                        label: choice.rawValue,
                        isSelected: timeChoice == choice
                    ) {
                        HapticManager.shared.impact(.light)
                        timeChoice = choice
                        activePreset = .custom
                    }
                }
            }
        }
    }

    // MARK: - Section 2: STATUS

    private var readStateSection: some View {
        sectionCard(
            kicker: "STATUS",
            title: "Read state",
            subtitle: readState.subtitle
        ) {
            segmentedRow(
                options: ReadState.allCases,
                selection: $readState,
                label: { $0.rawValue }
            )
        }
    }

    // MARK: - Section 3: SIZE

    private var sizeSection: some View {
        sectionCard(
            kicker: "SIZE",
            title: "Free up the most space",
            subtitle: "Heavy attachments first."
        ) {
            VStack(spacing: 8) {
                ForEach(SizeChoice.allCases) { choice in
                    iconPillRow(
                        icon: choice.icon,
                        label: choice.rawValue,
                        isSelected: sizeChoice == choice
                    ) {
                        HapticManager.shared.impact(.light)
                        sizeChoice = choice
                        activePreset = .custom
                    }
                }
            }
        }
    }

    // MARK: - Section 4: PROTECT

    private var protectSection: some View {
        sectionCard(
            kicker: "PROTECT",
            title: "Keep starred mail safe",
            subtitle: "Starred emails stay no matter what."
        ) {
            HStack(spacing: 12) {
                Image(systemName: protectStarred ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(protectStarred ? accentAmber : labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(card)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect starred")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(ink)
                    Text(protectStarred ? "ON — starred mail skipped" : "OFF — starred can be deleted")
                        .font(.system(size: 12))
                        .foregroundColor(inkMuted)
                }

                Spacer()

                Toggle("", isOn: $protectStarred)
                    .labelsHidden()
                    .tint(ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Section 5: SORT

    private var sortSection: some View {
        sectionCard(
            kicker: "SORT BY",
            title: "Order",
            subtitle: "What lands at the top of the list."
        ) {
            segmentedRow(
                options: EmailFilters.SortOrder.allCases,
                selection: $sortOrder,
                label: { sortOrderShortLabel($0) }
            )
        }
    }

    private func sortOrderShortLabel(_ s: EmailFilters.SortOrder) -> String {
        switch s {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        }
    }

    // MARK: - Reusable primitives

    private func sectionCard<Content: View>(
        kicker: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .tracking(0.8)
                    .foregroundColor(labelMuted)

                Text(title)
                    .font(.custom("Poppins-Bold", size: 17))
                    .foregroundColor(ink)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(inkMuted)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 4)

            content()
        }
    }

    private func iconPillRow(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : inkMuted)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(isSelected ? .white : ink)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? pillSelected : card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : cardBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private func segmentedRow<T: Hashable & Identifiable>(
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    HapticManager.shared.impact(.light)
                    selection.wrappedValue = option
                } label: {
                    Text(label(option))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(isSelected ? .white : ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? pillSelected : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: isSelected)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(pillFill)
        )
    }

    // MARK: - Active-dimension tracking

    private var activeCount: Int {
        var n = 0
        if timeChoice != .all { n += 1 }
        if readState != .any { n += 1 }
        if sizeChoice != .any { n += 1 }
        if attachmentChoice != .any { n += 1 }
        if !protectStarred { n += 1 }
        if sortOrder != .newest { n += 1 }
        return n
    }

    private var isDefault: Bool { activeCount == 0 }

    // MARK: - Reset

    private func resetAll() {
        timeChoice = .all
        readState = .any
        sizeChoice = .any
        attachmentChoice = .any
        protectStarred = true
        sortOrder = .newest
        activePreset = .custom
    }

    // MARK: - Model bridging

    private func loadCurrentFilters() {
        switch filters.olderThan {
        case 7?:   timeChoice = .week
        case 30?:  timeChoice = .month
        case 180?: timeChoice = .sixMo
        case 365?: timeChoice = .year
        default:   timeChoice = .all
        }

        if filters.readOnly        { readState = .read }
        else if filters.unreadOnly { readState = .unread }
        else                       { readState = .any }

        sizeChoice = SizeChoice.from(filters.sizeFilter)
        attachmentChoice = AttachmentChoice.from(filters.hasAttachments)
        protectStarred = filters.excludeStarred
        sortOrder = filters.sortOrder
        activePreset = inferPreset()
    }

    /// Map the current local state back to a preset if it exactly matches
    /// one — otherwise return `.custom`. Lets the chips light up when the
    /// user re-opens the sheet on a known combination.
    private func inferPreset() -> FilterPreset {
        if timeChoice == .month, sizeChoice == .mb1, attachmentChoice == .any,
           readState == .any, protectStarred, sortOrder == .newest { return .oldAndBig }
        if timeChoice == .month, sizeChoice == .any, attachmentChoice == .any,
           readState == .unread, protectStarred, sortOrder == .oldest { return .staleUnread }
        if timeChoice == .all, sizeChoice == .mb5, attachmentChoice == .with,
           readState == .any, protectStarred, sortOrder == .newest { return .heavyAttach }
        if timeChoice == .year, sizeChoice == .any, attachmentChoice == .any,
           readState == .any, protectStarred, sortOrder == .oldest { return .ancient }
        return .custom
    }

    private func applyFilters() {
        filters.olderThan = timeChoice.days
        filters.sortOrder = sortOrder
        filters.sizeFilter = sizeChoice.model
        filters.hasAttachments = attachmentChoice.model
        filters.excludeStarred = protectStarred

        switch readState {
        case .any:    filters.readOnly = false; filters.unreadOnly = false
        case .read:   filters.readOnly = true;  filters.unreadOnly = false
        case .unread: filters.readOnly = false; filters.unreadOnly = true
        }

        // Sender / subject / keyword dimensions aren't surfaced in the
        // sheet UI — they're only set programmatically (e.g. by Quick
        // Clean). Leave any existing values alone so an Apply doesn't
        // silently wipe them.
    }
}

// MARK: - Identifiable conformances

extension EmailFilters.SortOrder: Identifiable {
    public var id: String { rawValue }
}

extension EmailFilters.SizeFilter: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Flow Layout
//
// Kept as a shared module-level layout helper. DuplicateGroupView depends
// on it for wrapping match-reason pills; the old keyword-chip section in
// FiltersView is gone, but FlowLayout itself is still useful.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, pos) in arrange(proposal: proposal, subviews: subviews).positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let w = proposal.width ?? .infinity
        var pts: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rh: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > w && x > 0 { x = 0; y += rh + spacing; rh = 0 }
            pts.append(CGPoint(x: x, y: y))
            rh = max(rh, s.height); x += s.width + spacing
        }
        return (pts, CGSize(width: w, height: y + rh))
    }
}

#Preview {
    FiltersView(filters: .constant(EmailFilters()))
}
