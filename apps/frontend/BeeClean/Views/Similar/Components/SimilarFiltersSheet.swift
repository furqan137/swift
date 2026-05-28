import SwiftUI

// MARK: - Similar Sort Option
//
// Three-option sort surfaced via the "Newest" pill on every similar /
// duplicate / screenshots / videos review screen. Distinct from
// `SortOption` (Compress) which carries Smallest as well — the similar
// flows reorder *groups*, not individual files, and "smallest group" is
// not a meaningful axis the user has asked for.
enum SimilarSortOption: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case largest = "Largest"
}

// MARK: - Similar Filters Sheet
struct SimilarFiltersSheet: View {
    @Binding var sortOption: SimilarSortOption
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var tempStartDate = Date()
    @State private var tempEndDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: "D4D4D8"))
                .frame(width: 40, height: 5)
                .padding(.top, 14)
                .padding(.bottom, 20)

            HStack(spacing: 12) {
                dateButton(
                    label: startDate.map { formatDate($0) } ?? "Pick start date",
                    isActive: startDate != nil
                ) {
                    showStartPicker = true
                }

                dateButton(
                    label: endDate.map { formatDate($0) } ?? "Pick end date",
                    isActive: endDate != nil
                ) {
                    showEndPicker = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Text("Sort by")
                .font(.custom("Poppins-Bold", size: 13))
                .tracking(0.4)
                .foregroundColor(Color(hex: "A1A1AA"))
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                ForEach(SimilarSortOption.allCases, id: \.self) { option in
                    sortButton(option)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                if startDate != nil || endDate != nil || sortOption != .newest {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            sortOption = .newest
                            startDate = nil
                            endDate = nil
                        }
                    } label: {
                        Text("Reset Filters")
                            .font(.custom("Poppins-Bold", size: 14))
                            .foregroundColor(Color(hex: "78716C"))
                    }
                    .padding(.bottom, 4)
                }

                Button { dismiss() } label: {
                    Text(BCLoc.apply.tr)
                        .font(.custom("Poppins-Bold", size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        // Shared BitePal canvas — cool blue-lavender → warm
        // light-gray gradient used by every secondary surface.
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "DDE1F2"), location: 0.0),
                    .init(color: Color(hex: "DDE1F2"), location: 0.45),
                    .init(color: Color(hex: "E3E6EE"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .sheet(isPresented: $showStartPicker) {
            datePickerSheet(title: "Start Date", date: $tempStartDate) {
                startDate = tempStartDate
                showStartPicker = false
            }
        }
        .sheet(isPresented: $showEndPicker) {
            datePickerSheet(title: "End Date", date: $tempEndDate) {
                endDate = tempEndDate
                showEndPicker = false
            }
        }
    }

    private func dateButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Poppins-Bold", size: 14))
                .foregroundColor(isActive ? Color(hex: "1C1917") : Color(hex: "78716C"))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "F2F2F7"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func sortButton(_ option: SimilarSortOption) -> some View {
        let isSelected = sortOption == option

        return Button {
            HapticManager.shared.impact(.light)
            withAnimation(.easeOut(duration: 0.15)) {
                sortOption = option
            }
        } label: {
            Text(option.rawValue)
                .font(.custom("Poppins-Bold", size: 17))
                .foregroundColor(isSelected ? Color(hex: "1C1917") : Color(hex: "78716C"))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white : Color(hex: "F2F2F7"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? Color(hex: "1C1917") : Color.black.opacity(0.06),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func datePickerSheet(title: String, date: Binding<Date>, onConfirm: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { showStartPicker = false; showEndPicker = false } label: {
                    Text("Cancel")
                        .font(.custom("Poppins-Bold", size: 15))
                        .foregroundColor(Color(hex: "78716C"))
                }

                Spacer()

                Text(title)
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                Button(action: onConfirm) {
                    Text(BCLoc.done.tr)
                        .font(.custom("Poppins-Bold", size: 15))
                        .foregroundColor(Color(hex: "1C1917"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            DatePicker("", selection: date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.background)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

// MARK: - Similar Sort Pill
//
// The "Newest" pill that lives in the large-title trailing slot. Label
// reflects the current `sortOption` so the user always sees the active
// sort at a glance.
struct SimilarSortPill: View {
    let sortOption: SimilarSortOption
    let onTap: () -> Void

    /// Non-default sorts tint the pill with the espresso ink so the user
    /// gets an at-a-glance read that filtering is on.
    private var isActive: Bool { sortOption != .newest }

    var body: some View {
        Button {
            // Filter / sort pills fire the cosmetic selection tick —
            // user is browsing options, not committing a destructive
            // action, so the lighter `filterChange` haptic is the
            // right semantic.
            HapticManager.shared.filterChange()
            onTap()
        } label: {
            // Glyph + font sizes / weights now match TopBarSelectAllPill's
            // compact mode (icon 12pt bold, label 12.5pt semibold) so the
            // two header chips line up in size as well as in surface.
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(
                        isActive
                            ? Color(hex: "1C1917")
                            : Color(hex: "1C1917").opacity(0.55)
                    )
                    .symbolRenderingMode(.hierarchical)

                Text(sortOption.rawValue)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .tracking(-0.1)
                    .contentTransition(.opacity)
            }
            // Background recipe now mirrors TopBarSelectAllPill exactly —
            // `.regularMaterial` blur (the soft frosted lozenge), with an
            // additional ink wash when active. Padding matches the
            // sibling pill (10 horizontal, 5.5 vertical in non-prominent
            // mode) so the two pills read as a single paired set in
            // the header strip.
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)

                    if isActive {
                        Capsule()
                            .fill(Color(hex: "1C1917").opacity(0.06))
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        Color(hex: "1C1917").opacity(isActive ? 0.16 : 0.10),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
            .animation(.easeOut(duration: 0.18), value: isActive)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Group sort/filter helper
//
// Applies the active sort + optional date range to a groups list. Used
// by every similar/duplicate/screenshots/videos view so the filter
// semantics stay identical across the app.
extension Array where Element == SimilarGroupVM {
    func applySimilarFilters(
        sort: SimilarSortOption,
        startDate: Date?,
        endDate: Date?
    ) -> [SimilarGroupVM] {
        let filtered: [SimilarGroupVM] = self.filter { group in
            if let start = startDate, group.createdAt < start { return false }
            if let end = endDate, group.createdAt > end { return false }
            return true
        }
        switch sort {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .largest:
            return filtered.sorted { $0.totalBytes > $1.totalBytes }
        }
    }
}
