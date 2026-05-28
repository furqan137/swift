import SwiftUI

// MARK: - Backups List View
struct BackupsListView: View {
    @ObservedObject private var backupService = BackupService.shared
    @ObservedObject private var viewModel = ContactsViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateConfirm = false
    @State private var selectedBackup: ContactBackup?
    @State private var showDeleteConfirm = false
    @State private var backupToDelete: ContactBackup?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Bitepal cool-gray gradient — same canvas as ContactsView.
                BitepalCanvas()

                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .center) {
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

                        Text("Backups")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))

                        Spacer()

                        // + Button (blue circle)
                        Button {
                            showCreateConfirm = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "1C1917"))
                                    .frame(width: 40, height: 40)
                                    .shadow(color: Color(hex: "1C1917").opacity(0.3), radius: 8, y: 3)

                                if backupService.isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .disabled(backupService.isCreating)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                    // Backups List
                    if backupService.backups.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 14) {
                                ForEach(Array(backupService.backups.enumerated()), id: \.element.id) { index, backup in
                                    Button {
                                        selectedBackup = backup
                                    } label: {
                                        backupCard(backup)
                                    }
                                    .buttonStyle(ContactTileButtonStyle())
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            backupToDelete = backup
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete Backup", systemImage: "trash")
                                        }
                                    }
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 10)
                                    .animation(
                                        .easeOut(duration: 0.35).delay(Double(index) * 0.06),
                                        value: appeared
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .alert("Create Backup?", isPresented: $showCreateConfirm) {
            Button("Backup Now") {
                Task { await createBackup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save all \(viewModel.totalContacts) contacts to a local backup on your device.")
        }
        .alert("Delete Backup?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let backup = backupToDelete {
                    withAnimation(.easeOut(duration: 0.25)) {
                        backupService.deleteBackup(id: backup.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This backup will be permanently deleted.")
        }
        .sheet(item: $selectedBackup) { backup in
            BackupDetailView(backup: backup)
        }
        .preferredColorScheme(.light)
        .swipeToDismiss()
    }

    // MARK: - Backup Card
    private func backupCard(_ backup: ContactBackup) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(backup.formattedDate)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("\(backup.contactCount) Contacts")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "9B9490"))
            }

            Spacer()

            Text(backup.formattedTime)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "9B9490"))
                .padding(.trailing, 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "9B9490").opacity(0.5))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contactGlass(cornerRadius: 18)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: "1C1917").opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(Color(hex: "1C1917").opacity(0.6))
            }

            Text("No Backups Yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "1A1A1A"))

            Text("Tap the + button to create your\nfirst contacts backup.")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "9B9490"))
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Create Backup
    private func createBackup() async {
        HapticManager.shared.impact(.medium)
        let success = await backupService.createBackup(contacts: viewModel.allContacts)
        if success {
            HapticManager.shared.notify(.success)
        } else {
            HapticManager.shared.notify(.error)
        }
    }
}

#Preview {
    BackupsListView()
        .preferredColorScheme(.light)
}
