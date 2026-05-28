import SwiftUI

// MARK: - Undo Toast State Manager
/// Manages the transient "Moved to Trash / Deleted Items — Undo" state.
///
/// Driven by `BulkMailActionResult`: knows how many succeeded vs failed, which
/// provider the action ran against (so wording matches the user's mailbox),
/// and where to move messages back to on undo. Soft delete is the assumed
/// contract — this manager never invokes permanent delete.
@MainActor
class EmailUndoManager: ObservableObject {
    @Published var isShowing = false
    @Published var message = ""
    @Published var secondaryMessage: String? = nil
    @Published var isRecovering = false

    private var succeededMessageIds: [String] = []
    private var provider: MailProviderKind = .gmail
    private var originalMailbox: MailboxRef = .inbox
    private var emailService = EmailService.shared
    private var dismissTimer: Timer?
    private var onRecoverComplete: ((_ recovered: Bool) -> Void)?

    /// Preferred entry point. Builds the toast wording from the structured
    /// bulk result: "Moved 24 to Trash" or "Moved 24 to Deleted Items", with
    /// a secondary "2 couldn't be moved" line on partial failure.
    func showUndo(
        result: BulkMailActionResult,
        provider: MailProviderKind = .gmail,
        originalMailbox: MailboxRef = .inbox,
        onRecoverComplete: ((_ recovered: Bool) -> Void)? = nil
    ) {
        // Nothing to undo.
        guard !result.succeededIds.isEmpty else {
            // All failed — still surface the failure briefly, no Undo.
            if !result.failed.isEmpty {
                presentTransient(
                    primary: "Couldn't move \(result.failed.count) \(Self.noun(count: result.failed.count))",
                    secondary: nil
                )
            }
            onRecoverComplete?(false)
            return
        }

        self.succeededMessageIds = result.succeededIds
        self.provider = provider
        self.originalMailbox = originalMailbox
        self.onRecoverComplete = onRecoverComplete

        let folder = provider.trashFolderLabel
        let count = result.succeededIds.count
        self.message = count == 1
            ? "Moved to \(folder)"
            : "Moved \(count) to \(folder)"
        self.secondaryMessage = result.failed.isEmpty
            ? nil
            : "\(result.failed.count) couldn't be moved"
        self.isShowing = true

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    /// Back-compat shim for older call sites that pass a prebuilt string.
    /// New code should call the `result:` variant for automatic wording.
    func showUndo(
        messageIds: [String],
        message: String,
        provider: MailProviderKind = .gmail,
        onRecoverComplete: ((_ recovered: Bool) -> Void)? = nil
    ) {
        self.succeededMessageIds = messageIds
        self.provider = provider
        self.originalMailbox = .inbox
        self.message = message
        self.secondaryMessage = nil
        self.onRecoverComplete = onRecoverComplete
        self.isShowing = true

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    /// Brief informational toast (no Undo). Used for "all failed" and similar
    /// terminal states where there's nothing to reverse.
    private func presentTransient(primary: String, secondary: String?) {
        message = primary
        secondaryMessage = secondary
        succeededMessageIds = []
        isShowing = true
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// User tapped Undo — recover the emails via the provider abstraction.
    func undo() {
        dismissTimer?.invalidate()
        guard !succeededMessageIds.isEmpty else {
            isShowing = false
            onRecoverComplete?(false)
            return
        }
        isRecovering = true

        let ids = succeededMessageIds
        let providerKind = provider
        let origin = originalMailbox
        Task {
            let result = await emailService.untrashMessagesDetailed(
                messageIds: ids,
                originalMailbox: origin,
                provider: providerKind
            )
            isRecovering = false
            isShowing = false
            onRecoverComplete?(!result.succeededIds.isEmpty)
        }
    }

    /// Auto-dismiss (timer expired, user didn't undo)
    func dismiss() {
        dismissTimer?.invalidate()
        isShowing = false
        succeededMessageIds = []
        secondaryMessage = nil
        let callback = onRecoverComplete
        onRecoverComplete = nil
        callback?(false)
    }

    private static func noun(count: Int) -> String {
        count == 1 ? "email" : "emails"
    }
}

// MARK: - Undo Toast View Modifier
/// Use this as .undoToast(undoManager) on any view
struct UndoToastModifier: ViewModifier {
    @ObservedObject var undoManager: EmailUndoManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if undoManager.isShowing {
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        if undoManager.isRecovering {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)

                            Text("Recovering...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(undoManager.message)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if let secondary = undoManager.secondaryMessage {
                                    Text(secondary)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Button {
                                undoManager.undo()
                            } label: {
                                Text("Undo")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primaryColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.primaryColor.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.15, green: 0.15, blue: 0.18))
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: undoManager.isShowing)
                .animation(.easeOut(duration: 0.2), value: undoManager.isRecovering)
            }
        }
    }
}

extension View {
    func undoToast(_ undoManager: EmailUndoManager) -> some View {
        modifier(UndoToastModifier(undoManager: undoManager))
    }
}
