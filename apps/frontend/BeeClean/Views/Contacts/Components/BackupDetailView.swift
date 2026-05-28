import SwiftUI

// MARK: - Backup Detail View (Restore Backup)
struct BackupDetailView: View {
    let backup: ContactBackup
    @ObservedObject private var backupService = BackupService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [BackupContact] = []
    @State private var isLoading = true
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var restoreSuccess = false
    @State private var appeared = false

    private var groupedContacts: [(letter: String, contacts: [BackupContact])] {
        let grouped = Dictionary(grouping: contacts) { $0.sortLetter }
        return grouped.sorted { $0.key < $1.key }
            .map { (letter: $0.key, contacts: $0.value.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }) }
    }

    private var sectionLetters: [String] {
        groupedContacts.map { $0.letter }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BitepalCanvas()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    if isLoading {
                        loadingView
                    } else if contacts.isEmpty {
                        emptyView
                    } else {
                        // A-Z indexed contact list
                        ZStack(alignment: .trailing) {
                            contactScrollView
                            letterIndex
                        }
                    }

                    // Restore button
                    if !contacts.isEmpty && !isLoading {
                        restoreButton
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            let loaded = await backupService.loadBackupContacts(backupID: backup.id)
            contacts = loaded
            isLoading = false
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .alert("Restore Backup?", isPresented: $showRestoreConfirm) {
            Button("Restore") {
                Task { await performRestore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will add \(contacts.count) contacts from this backup to your phone. Existing contacts will not be modified.")
        }
        .alert("Restore Complete", isPresented: $restoreSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("\(contacts.count) contacts have been restored to your phone.")
        }
        .alert("Delete Backup?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                withAnimation(.easeOut(duration: 0.25)) {
                    backupService.deleteBackup(id: backup.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This backup will be permanently deleted.")
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "1A1A1A"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Text("All Contacts")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "1C1917"))
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Text("\(backup.contactCount) Contacts")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "9B9490"))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Contact Scroll View with Sections
    private var contactScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16, pinnedViews: []) {
                    ForEach(groupedContacts, id: \.letter) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            // Letter badge
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: "1C1917"))
                                    .frame(width: 48, height: 48)

                                Text(section.letter)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .id(section.letter)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: appeared)

                            // Contacts in section
                            VStack(spacing: 0) {
                                ForEach(Array(section.contacts.enumerated()), id: \.element.id) { index, contact in
                                    backupContactRow(contact)

                                    if index < section.contacts.count - 1 {
                                        Rectangle()
                                            .fill(Color(hex: "E8E4DF").opacity(0.5))
                                            .frame(height: 0.5)
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                            .contactGlass(cornerRadius: 16)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 100)
                .padding(.trailing, 20) // Room for letter index
            }
            .onChange(of: scrollTarget) { _, letter in
                if let letter {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(letter, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }
        }
    }

    @State private var scrollTarget: String?

    // MARK: - Letter Index (right side)
    private var letterIndex: some View {
        VStack(spacing: 1) {
            ForEach(sectionLetters, id: \.self) { letter in
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

    // MARK: - Backup Contact Row
    private func backupContactRow(_ contact: BackupContact) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient(for: contact.fullName))
                    .frame(width: 42, height: 42)
                Text(contact.initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .lineLimit(1)

                if let phone = contact.phoneNumbers.first {
                    Text(phone.value)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "9B9490"))
                        .lineLimit(1)
                } else if let email = contact.emailAddresses.first {
                    Text(email.value)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "9B9490"))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Action Buttons
    private var restoreButton: some View {
        HStack(spacing: 12) {
            // Delete button
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red)
                            .shadow(color: Color.red.opacity(0.3), radius: 10, y: 4)
                    )
            }

            // Restore button
            Button {
                showRestoreConfirm = true
            } label: {
                HStack(spacing: 10) {
                    if backupService.isRestoring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text("Restore Backup")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "1C1917"))
                        .shadow(color: Color(hex: "1C1917").opacity(0.35), radius: 12, y: 5)
                )
            }
            .disabled(backupService.isRestoring)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 34)
        .background(
            LinearGradient(
                colors: [Color(hex: "F7F7F7").opacity(0), Color(hex: "F7F7F7")],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)
            .offset(y: -30)
        , alignment: .top)
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                .scaleEffect(1.2)
            Text("Loading backup...")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "9B9490"))
            Spacer()
        }
    }

    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color(hex: "9B9490").opacity(0.5))
            Text("Backup is empty")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "9B9490"))
            Spacer()
        }
    }

    // MARK: - Avatar Gradient
    private func avatarGradient(for name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let colors: [(Color, Color)] = [
            (Color(hex: "4A90D9"), Color(hex: "2563B0")),
            (Color(hex: "8B5CF6"), Color(hex: "6D28D9")),
            (Color(hex: "D97BB5"), Color(hex: "B0477A")),
            (Color(hex: "2EC4A2"), Color(hex: "1A9B7E")),
            (Color(hex: "E5930E"), Color(hex: "C47A0A")),
            (Color(hex: "E8453C"), Color(hex: "C23028"))
        ]
        let pair = colors[hash % colors.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Restore Action
    private func performRestore() async {
        HapticManager.shared.impact(.medium)
        let success = await backupService.restoreBackup(contacts: contacts)
        if success {
            HapticManager.shared.notify(.success)
            restoreSuccess = true
        } else {
            HapticManager.shared.notify(.error)
        }
    }
}

#Preview {
    BackupDetailView(
        backup: ContactBackup(id: "preview", contactCount: 1502, createdAt: Date())
    )
    .preferredColorScheme(.light)
}
