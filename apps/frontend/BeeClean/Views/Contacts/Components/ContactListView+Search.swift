import SwiftUI
import Contacts

extension ContactListView {

    // MARK: - Search Bar
    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "A1A1AA"))

            TextField("Search contacts...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "1A1A1A"))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "EEEDF3"))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Stats Bar
    var statsBar: some View {
        HStack(spacing: 6) {
            if category == .duplicates {
                Text("\(viewModel.duplicateCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                Text("duplicate\(viewModel.duplicateCount == 1 ? "" : "s") in \(viewModel.duplicateGroupCount) group\(viewModel.duplicateGroupCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "9B9490"))
            } else {
                let total = allCategoryContacts.count
                let showing = contacts.count
                if hasMore {
                    Text("Showing \(showing)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "1A1A1A"))
                    Text("of \(total) contact\(total == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "9B9490"))
                } else {
                    Text("\(total)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "1A1A1A"))
                    Text(searchText.isEmpty ? "contact\(total == 1 ? "" : "s")" : "result\(total == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "9B9490"))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    /// Build the ID set without intermediate Array buffers — `flatMap` +
    /// `map` + `Set` was allocating two large transient arrays on every
    /// selection toggle, which compounded into Duplicates-tab lag.
    func collectDuplicateIDs() -> Set<String> {
        var ids = Set<String>()
        ids.reserveCapacity(viewModel.duplicateCount * 2)
        for group in viewModel.duplicateGroups {
            for c in group.contacts { ids.insert(c.id) }
        }
        return ids
    }

    @ViewBuilder
    var toolbarSelectAllButton: some View {
        if category == .duplicates && !viewModel.duplicateGroups.isEmpty {
            let allDupeIDs = collectDuplicateIDs()
            let allSelected = allDupeIDs.isSubset(of: selectedContacts)
            Button {
                HapticManager.shared.impact(.light)
                withAnimation(.easeOut(duration: 0.2)) {
                    if allSelected {
                        selectedContacts.removeAll()
                    } else {
                        selectedContacts = allDupeIDs
                    }
                }
            } label: {
                BitePalSelectPillLabel(
                    text: allSelected ? "Deselect All" : "Select All",
                    isActive: allSelected,
                    restingIcon: "checkmark.circle",
                    activeIcon: "checkmark.circle.fill"
                )
            }
        } else if !allCategoryContacts.isEmpty {
            let ids = Set(allCategoryContacts.map { $0.id })
            let allSelected = selectedContacts.isSuperset(of: ids)
            Button {
                HapticManager.shared.impact(.light)
                withAnimation(.easeOut(duration: 0.2)) {
                    if allSelected {
                        selectedContacts.removeAll()
                    } else {
                        selectedContacts = ids
                    }
                }
            } label: {
                BitePalSelectPillLabel(
                    text: allSelected ? "Deselect All" : "Select All",
                    isActive: allSelected,
                    restingIcon: "checkmark.circle",
                    activeIcon: "checkmark.circle.fill"
                )
            }
        }
    }

}

