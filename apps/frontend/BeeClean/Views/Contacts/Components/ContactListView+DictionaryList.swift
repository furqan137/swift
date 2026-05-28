import SwiftUI
import Contacts

extension ContactListView {

    // MARK: - Dictionary Contact List (A-Z sections)
    //
    // Memoized at the call site via a single helper that runs the grouping
    // ONCE per render. The previous design had `dictionaryGrouped` as a
    // computed property called by both the section ForEach and the A-Z
    // index rail (`dictionarySectionLetters` walked it again), so each
    // body invalidation re-grouped + re-sorted the contact list two or
    // three times. With 150+ duplicate contacts and selection toggles
    // firing body updates per tap, that compounded into the visible
    // multi-second hang the user reported on the Duplicates tab.
    fileprivate static func computeDictionaryGrouped(
        _ contacts: [AppContact]
    ) -> [(letter: String, contacts: [AppContact])] {
        let grouped = Dictionary(grouping: contacts) { contact -> String in
            let name = contact.fullName.uppercased()
            guard let first = name.first, first.isLetter else { return "#" }
            return String(first)
        }
        return grouped.sorted { $0.key < $1.key }
            .map { (letter: $0.key, contacts: $0.value.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }) }
    }

    var dictionaryContactList: some View {
        // Compute the grouping ONCE per body and reuse for both the
        // section ForEach and the A-Z rail. See the comment on
        // `computeDictionaryGrouped` for the rationale.
        let grouped = Self.computeDictionaryGrouped(contacts)
        let letters = grouped.map { $0.letter }

        return ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10, pinnedViews: []) {
                        ForEach(grouped, id: \.letter) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                // Letter badge — clean black rounded square
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(hex: "1C1917"))
                                        .frame(width: 44, height: 44)

                                    Text(section.letter)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .id(section.letter)
                                .padding(.top, 6)

                                // Individual cards per contact
                                ForEach(section.contacts, id: \.id) { contact in
                                    let isSelected = selectedContacts.contains(contact.id)

                                    HStack(spacing: 14) {
                                        // Initials in rounded rect
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color(hex: "E8E8ED"))
                                                .frame(width: 42, height: 42)
                                            Text(contact.initials)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(Color(hex: "78716C"))
                                        }

                                        Text(contact.fullName.isEmpty ? "No name" : contact.fullName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color(hex: "1C1917"))
                                            .lineLimit(1)

                                        Spacer()

                                        // Circle radio checkbox
                                        Circle()
                                            .stroke(
                                                isSelected ? Color(hex: "1C1917") : Color(hex: "C8C8CC"),
                                                lineWidth: isSelected ? 7 : 2
                                            )
                                            .frame(width: 28, height: 28)
                                            .animation(.easeOut(duration: 0.15), value: isSelected)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contactGlass(cornerRadius: 16)
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                                    .onTapGesture {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            if isSelected {
                                                selectedContacts.remove(contact.id)
                                            } else {
                                                selectedContacts.insert(contact.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Load more trigger
                        if hasMore {
                            loadMoreFooter
                                .onAppear { loadMore() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, selectedContacts.isEmpty ? 20 : 100)
                    .padding(.trailing, 16)
                }
                .refreshable { await viewModel.loadContacts() }
                .onChange(of: scrollTarget) { _, letter in
                    if let letter {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(letter, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }
            }

            // A-Z letter index — same `letters` array the section ForEach
            // walks above, so the side rail and the content can never go
            // out of sync (and we don't pay for a second grouping pass).
            VStack(spacing: 1) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        HapticManager.shared.impact(.light)
                        scrollTarget = letter
                    } label: {
                        Text(letter)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .frame(width: 16, height: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 4)
            .padding(.vertical, 8)
        }
    }
}

