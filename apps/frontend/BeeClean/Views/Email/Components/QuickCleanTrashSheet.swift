import SwiftUI

struct QuickCleanTrashSheet: View {
    @ObservedObject var vm: QuickCleanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyConfirm = false
    @State private var deleteConfirmEmail: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if vm.trashedSenders.isEmpty {
                    emptyState
                } else {
                    senderList
                }

                if vm.isDeleting {
                    progressOverlay
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.foreground)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.trashCount > 0 {
                        Text("\(vm.trashCount) sender\(vm.trashCount == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.foregroundSecondary)
                    }
                }
            }
        }
        .confirmationDialog(
            "Permanently delete all \(vm.trashCount) sender\(vm.trashCount == 1 ? "" : "s")? This cannot be undone.",
            isPresented: $showEmptyConfirm,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task { await vm.emptyTrash() }
            }
        }
        .confirmationDialog(
            "Permanently delete this sender and all their emails? This cannot be undone.",
            isPresented: Binding(
                get: { deleteConfirmEmail != nil },
                set: { if !$0 { deleteConfirmEmail = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Forever", role: .destructive) {
                if let email = deleteConfirmEmail {
                    Task { await vm.deleteSenderForever(email: email) }
                }
            }
        }
    }

    // MARK: - Sender List
    private var senderList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.trashedSenders) { sender in
                        senderRow(sender)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Divider()
                PrimaryButton("Empty Trash", iconName: "trash.fill", isDestructive: true) {
                    showEmptyConfirm = true
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.background)
        }
    }

    private func senderRow(_ sender: TrashedSenderInfo) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Text(String(sender.name.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor(for: sender.email))
                .clipShape(Circle())

            // Name + email + count
            VStack(alignment: .leading, spacing: 2) {
                Text(sender.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.foreground)
                    .lineLimit(1)

                Text("\(sender.email) \u{00B7} \(sender.count) email\(sender.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.foregroundSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Restore
            Button {
                withAnimation { vm.restoreSender(email: sender.email) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.success)
                    .frame(width: 36, height: 36)
                    .background(Color.success.opacity(0.12))
                    .clipShape(Circle())
            }

            // Delete forever
            Button {
                deleteConfirmEmail = sender.email
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.destructive)
                    .frame(width: 36, height: 36)
                    .background(Color.destructive.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.foregroundSecondary.opacity(0.5))

            Text("Trash is empty")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.foreground)

            Text("Senders you swipe left on will appear here.")
                .font(.system(size: 14))
                .foregroundColor(.foregroundSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Progress Overlay
    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.2)

                Text("Deleting \(vm.deleteProgress) / \(vm.totalToDelete)...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
            )
        }
    }

    // MARK: - Helpers
    private func avatarColor(for email: String) -> Color {
        let colors: [Color] = [
            .categoryHoney, .categoryTeal, .categoryAmber,
            .categoryRose, .categoryViolet, .categorySky
        ]
        let hash = abs(email.hashValue)
        return colors[hash % colors.count]
    }
}
