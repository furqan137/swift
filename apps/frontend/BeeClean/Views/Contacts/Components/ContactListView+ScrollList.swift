import SwiftUI
import Contacts

extension ContactListView {

    // MARK: - Contact Scroll List
    var contactScrollList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(contacts, id: \.id) { contact in
                    let isSelected = selectedContacts.contains(contact.id)

                    HStack(spacing: 14) {
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

                if hasMore {
                    loadMoreFooter
                        .onAppear { loadMore() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, selectedContacts.isEmpty ? 20 : 100)
        }
        .refreshable { await viewModel.loadContacts() }
    }

}

