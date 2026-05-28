import SwiftUI
import Contacts

extension ContactListView {

    // MARK: - Duplicate Group List
    var duplicateGroupList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(viewModel.duplicateGroups) { group in
                    duplicateGroupSection(group)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, selectedContacts.isEmpty ? 20 : 100)
        }
        .refreshable { await viewModel.loadContacts() }
    }

    func duplicateGroupSection(_ group: DuplicateGroup) -> some View {
        let groupIDs = Set(group.contacts.map { $0.id })
        let allSelected = groupIDs.isSubset(of: selectedContacts)

        // Phone keys that drove the union for THIS group, in the
        // same last-10-digits form `findDuplicates` indexed on. We
        // highlight any phone in any row whose normalized suffix
        // matches one of these, so the user can see the algorithm's
        // actual evidence — e.g. Aaron-1's `+19733078519` and
        // Aaron-4's `+19733078519` both go bold-espresso while
        // Aaron-1's other unrelated numbers fade to caption gray.
        let sharedPhoneKeys: Set<String> = Set(
            group.matchReasons
                .filter { $0.kind == .phone }
                .map { $0.detail }
        )
        let sharedEmailKeys: Set<String> = Set(
            group.matchReasons
                .filter { $0.kind == .email }
                .map { $0.detail }
        )

        return VStack(spacing: 0) {
            // Header — mirrors the photo cleanup "X Similar" group header.
            //   • Title on the left with count
            //   • "Keep All" green pill below the title — clears any
            //     selection in this group, marking the cluster as "leave
            //     it alone" (only meaningful once items are selected, so
            //     it fades in/out based on `anySelected`).
            //   • "Select All" / "Deselect" link top-right.
            HStack(alignment: .center) {
                // Subtitle removed — the phone numbers themselves below
                // tell the story. Title is enough as the section header.
                Text("\(group.count) Duplicate Contacts")
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if allSelected {
                            selectedContacts.subtract(groupIDs)
                        } else {
                            selectedContacts.formUnion(groupIDs)
                        }
                    }
                } label: {
                    BitePalSelectPillLabel(
                        text: allSelected ? "Deselect" : "Select All",
                        isActive: allSelected
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Contact rows — each one is now its own rounded sub-card
            // (subtle lavender ground inside the white parent glass) so
            // the rows read as separated tiles instead of hairline-divided
            // table rows. 8pt vertical breathing room between sub-cards.
            VStack(spacing: 8) {
                ForEach(group.contacts, id: \.id) { contact in
                    let isSelected = selectedContacts.contains(contact.id)

                    HStack(spacing: 0) {
                        Button {
                            selectedForDetail = contact
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.fullName.isEmpty ? "No name" : contact.fullName)
                                    .font(.custom("Poppins-Bold", size: 16))
                                    .foregroundColor(Color(hex: "1C1917"))
                                    .lineLimit(1)

                                if !contact.phoneNumbers.isEmpty {
                                    Self.matchedPhoneLine(
                                        phones: contact.phoneNumbers,
                                        sharedKeys: sharedPhoneKeys
                                    )
                                } else if let email = contact.emails.first {
                                    let isMatched = sharedEmailKeys.contains(
                                        email.lowercased().trimmingCharacters(in: .whitespaces)
                                    )
                                    Text(email)
                                        .font(.system(size: 13, weight: isMatched ? .bold : .medium))
                                        .foregroundColor(Color(hex: isMatched ? "1C1917" : "9A9590"))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                if isSelected {
                                    selectedContacts.remove(contact.id)
                                } else {
                                    selectedContacts.insert(contact.id)
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color(hex: "C8C7CD"), lineWidth: 1.4)
                                    .frame(width: 26, height: 26)
                                if isSelected {
                                    Circle()
                                        .fill(Color(hex: "DC2626"))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundColor(.white)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        // Sub-card surface — subtle BitePal lavender wash
                        // inside the white parent glass. Selected rows
                        // get a faint red wash + accent border so the
                        // marked state reads at a glance.
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color(hex: "DC2626").opacity(0.06) : Color(hex: "F4F5FA"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        isSelected ? Color(hex: "DC2626").opacity(0.30) : Color.black.opacity(0.04),
                                        lineWidth: isSelected ? 1 : 0.5
                                    )
                            )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .contactGlass(cornerRadius: 18)
    }

    /// Build the phone evidence line for a duplicate row. Matched
    /// phones (whose last-10-digits suffix appears in `sharedKeys`)
    /// render in bold espresso and come first; the rest follow in a
    /// faded caption gray. Concatenation uses a `Text` chain so the
    /// styling is per-phone rather than per-line.
    fileprivate static func matchedPhoneLine(
        phones: [String],
        sharedKeys: Set<String>
    ) -> some View {
        func key(_ phone: String) -> String {
            let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return String(digits.suffix(min(digits.count, 10)))
        }
        var matched: [String] = []
        var rest: [String] = []
        for p in phones {
            if sharedKeys.contains(key(p)) {
                matched.append(p)
            } else {
                rest.append(p)
            }
        }

        let matchedText = matched.enumerated().reduce(Text("")) { acc, pair in
            let prefix = pair.offset == 0 ? "" : "  •  "
            return acc + Text(prefix + pair.element)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "1C1917"))
        }
        let restText = rest.enumerated().reduce(Text("")) { acc, pair in
            let prefix = (matched.isEmpty && pair.offset == 0) ? "" : "  •  "
            return acc + Text(prefix + pair.element)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "A8A29E"))
        }
        return (matchedText + restText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Plain-language summary of why a duplicate group was unioned.
    /// Surfaces the algorithm's actual signal so users can verify the
    /// match instead of assuming we grouped by name.
    func matchReasonSummary(for group: DuplicateGroup) -> String {
        let kinds = Set(group.matchReasons.map(\.kind))
        let hasPhone = kinds.contains(.phone)
        let hasEmail = kinds.contains(.email)
        switch (hasPhone, hasEmail) {
        case (true, true):  return "Same phone + email"
        case (true, false): return "Same phone number"
        case (false, true): return "Same email address"
        default:            return "Matched contacts"
        }
    }

    // MARK: - Contact Avatar
    @ViewBuilder
    func contactAvatar(_ contact: AppContact, size: CGFloat) -> some View {
        if contact.hasThumbnail, let data = contact.thumbnailData {
            ContactAvatarImage(data: data, size: size)
        } else {
            ZStack {
                Circle()
                    .fill(avatarGradient(for: contact.fullName))
                    .frame(width: size, height: size)
                Text(contact.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    func avatarGradient(for name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let colors: [(Color, Color)] = [
            (Color(hex: "C48B9F"), Color(hex: "A8707F")),  // muted rose
            (Color(hex: "D4A373"), Color(hex: "B8895C")),  // warm amber
            (Color(hex: "B5838D"), Color(hex: "9A6B74")),  // dusty mauve
            (Color(hex: "C9A96E"), Color(hex: "AE9058")),  // soft gold
            (Color(hex: "A8A0B5"), Color(hex: "8E869E")),  // muted lavender
            (Color(hex: "B0A090"), Color(hex: "968878")),  // warm taupe
        ]
        let pair = colors[hash % colors.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Merge All Banner
    var mergeAllBanner: some View {
        Group {
            if let result = mergeAllResult {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "22A55B"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Merge Complete")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(hex: "1A1A1A"))
                        Text("\(result.merged) groups merged, \(result.deleted) duplicates removed")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "9B9490"))
                    }
                    Spacer()
                }
                .padding(14)
                .contactGlass(cornerRadius: 14)
            } else {
                Button { showMergeAllConfirm = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "1C1917").opacity(0.1))
                                .frame(width: 40, height: 40)

                            if isMergingAll {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.merge")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(Color(hex: "1C1917"))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Merge All Duplicates")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: "1A1A1A"))
                            Text("Clean up \(viewModel.duplicateGroups.count) groups at once")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "9B9490"))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917").opacity(0.5))
                    }
                    .padding(14)
                    .contactGlass(cornerRadius: 14)
                }
                .buttonStyle(ContactTileButtonStyle())
                .disabled(isMergingAll)
            }
        }
    }

}
