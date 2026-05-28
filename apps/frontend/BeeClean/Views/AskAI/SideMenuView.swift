import SwiftUI

// MARK: - Side Menu View
/// Pure panel content — positioning, gestures, and backdrop are owned by the parent.
struct SideMenuView: View {
    let isOpen: Bool
    let onClose: () -> Void
    let onNewChat: () -> Void
    let onSelectHistory: (ChatSession) -> Void

    @ObservedObject private var history = ChatHistoryService.shared

    @State private var page: SideMenuPage = .menu
    /// Confirmation gate for the header trash button. Wipes every
    /// chat session at once so the user can start fresh.
    @State private var showClearAllAlert = false

    enum SideMenuPage {
        case menu
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
                .padding(.top, 12)
                .padding(.bottom, 12)
                .padding(.horizontal, 20)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)

            menuContent
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BitepalCanvas())
        .onChange(of: isOpen) { _, newValue in
            if !newValue {
                // Reset to menu when closed so it's fresh next open
                withAnimation(.easeInOut(duration: 0.15)) {
                    page = .menu
                }
            }
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack {
            if page != .menu {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page = .menu
                    }
                } label: {
                    Image(systemName: "chevron.left")
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

            if page == .menu {
                Text("Ask Bee")
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(Color(hex: "1C1917"))
            } else {
                Spacer()

                Text("People")
                    .font(.custom("Poppins-Bold", size: 19))
                    .foregroundColor(Color(hex: "1C1917"))
            }

            Spacer()

            // Clear-all trash button — only renders when there's actual
            // history to wipe. Sits next to the close X so it's a peer
            // header action, not buried in a context menu somewhere.
            if !history.sessions.isEmpty {
                Button {
                    HapticManager.shared.impact(.light, intensity: 0.5)
                    showClearAllAlert = true
                } label: {
                    Image(systemName: "trash")
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
                .accessibilityLabel("Clear all chats")
                .padding(.trailing, 6)
            }

            Button {
                HapticManager.shared.impact(.light, intensity: 0.5)
                onClose()
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
        .alert("Clear all chats?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                HapticManager.shared.notify(.warning)
                withAnimation(.easeOut(duration: 0.25)) {
                    // Snapshot the IDs first since `delete` mutates the
                    // sessions array we'd otherwise be iterating.
                    let ids = history.sessions.map(\.id)
                    for id in ids { history.delete(id) }
                }
            }
        } message: {
            Text("This will delete \(history.sessions.count) chat\(history.sessions.count == 1 ? "" : "s"). This can't be undone.")
        }
    }

    // MARK: - Menu Content

    private var menuContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                menuRow(icon: "plus.circle", title: "New Chat", subtitle: "Start a fresh conversation") {
                    // Heavy primary-commit feel — starting a new chat
                    // is a committed action, not a browse. Matches the
                    // "New Chat" button in AskAIView's top header so
                    // both entry points land at the same weight.
                    HapticManager.shared.primaryCommit()
                    onNewChat()
                }

                menuDivider

                // Inline conversation list
                if !history.sessions.isEmpty {
                    inlineConversationList
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Inline Conversation List

    private var inlineConversationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !history.pinnedSessions.isEmpty {
                sectionHeader("Saved")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ForEach(history.pinnedSessions) { session in
                    inlineSessionRow(session)
                }
            }

            if !history.recentSessions.isEmpty {
                sectionHeader("Recent")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ForEach(history.recentSessions) { session in
                    inlineSessionRow(session)
                }
            }
        }
    }

    private func inlineSessionRow(_ session: ChatSession) -> some View {
        Button {
            // Scope-change rotor tick — same as the ChatHistoryView
            // session row + Progress range pills. The two history
            // surfaces must feel identical since they drive the
            // same state.
            HapticManager.shared.filterChange()
            onSelectHistory(session)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)

                    Text(session.preview)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .lineLimit(1)

                    Text(relativeDate(session.updatedAt))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "C7C7CC"))
                        .padding(.top, 2)
                }

                Spacer(minLength: 8)

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "F5F5F4"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                HapticManager.shared.impact(.light, intensity: 0.6)
                history.togglePin(session.id)
            } label: {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive) {
                HapticManager.shared.notify(.warning)
                history.delete(session.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func menuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "F5F5F4"))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("Poppins-Bold", size: 16))
                        .foregroundColor(Color(hex: "1C1917"))

                    // Was `#A1A1AA` at 12pt — barely visible against the
                    // cool-gray Bitepal canvas. Bumped to `#78716C`
                    // (espresso warm gray, same subtitle token used in
                    // Contacts/Email rows) at 13pt medium so the
                    // subtitle actually reads.
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "78716C"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "D4D4D8"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.04))
            .frame(height: 0.5)
            .padding(.leading, 70)
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
    SideMenuView(isOpen: true, onClose: {}, onNewChat: {}, onSelectHistory: { (_: ChatSession) in })
}
