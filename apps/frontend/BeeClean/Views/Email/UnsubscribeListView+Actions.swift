import SwiftUI

extension UnsubscribeListView {
    // MARK: - Actions

    func performUnsubscribe(from sender: EmailSender, deleteExisting: Bool) async {
        isUnsubscribing = sender.email
        HapticManager.shared.impact(.medium)

        let success = await emailService.unsubscribe(from: sender.email, deleteExisting: deleteExisting)
        isUnsubscribing = nil

        if success {
            HapticManager.shared.notify(.success)
            _ = withAnimation(.easeOut(duration: 0.25)) {
                unsubscribedEmails.insert(sender.email)
            }
            withAnimation(.easeOut(duration: 0.4)) {
                displayedEmails = max(0, displayedEmails - sender.count)
                displayedSenders = max(0, displayedSenders - 1)
            }
        } else {
            HapticManager.shared.notify(.error)
        }
    }
}

#Preview {
    NavigationStack { UnsubscribeListView() }
        .preferredColorScheme(.light)
}
