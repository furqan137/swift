import SwiftUI

// MARK: - Chat History View
struct ChatHistoryView: View {
    @ObservedObject private var history = ChatHistoryService.shared
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a session to restore it.
    let onSelect: ([AIMessage]) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    historyContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("History")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(Color(hex: "1C1917"))
                .tracking(-0.4)

            Spacer()

            Button {
                HapticManager.shared.impact(.light, intensity: 0.6)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(hex: "F5F5F4"))
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - History Content

    private var historyContent: some View {
        Group {
            if history.sessions.isEmpty {
                historyEmptyState
            } else {
                List {
                    if !history.pinnedSessions.isEmpty {
                        Section {
                            ForEach(history.pinnedSessions) { session in
                                sessionRow(session)
                            }
                        } header: {
                            sectionHeader("Saved")
                        }
                    }

                    if !history.recentSessions.isEmpty {
                        Section {
                            ForEach(history.recentSessions) { session in
                                sessionRow(session)
                            }
                        } header: {
                            sectionHeader("Recent")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.white)
            }
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: ChatSession) -> some View {
        Button {
            // Session switch is a scope change, same family as the
            // Progress range pills / SavedFinds category chips. Using
            // filterChange keeps the haptic language consistent app-
            // wide and reads identically to the side-menu row.
            HapticManager.shared.filterChange()
            onSelect(session.messages)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)

                    Text(relativeDate(session.updatedAt))
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }

                Spacer()

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "78716C"))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "D4D4D8"))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                history.delete(session.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                history.togglePin(session.id)
            } label: {
                Label(session.isPinned ? "Unpin" : "Pin",
                      systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color(hex: "1C1917"))
        }
    }

    // MARK: - Empty State

    private var historyEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color(hex: "D4D4D8"))

            Text("No chat history yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))

            Text("Your conversations will appear here")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "A1A1AA"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(hex: "A1A1AA"))
            .tracking(1.2)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ChatHistoryView(onSelect: { _ in })
}
