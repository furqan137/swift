import SwiftUI
import Contacts
import ContactsUI

// MARK: - Contact Detail View
//
// Native iOS contact card. Tapping any AppContact — from the regular
// contacts list OR a duplicate group — surfaces this view, which is just
// `CNContactViewController(for:)` wrapped for SwiftUI.
//
// We use the system view, NOT a custom layout, because the user wants
// the EXACT Contacts.app card: avatar, big name header, message / call /
// FaceTime / mail action chips, "Contact Photo & Poster" row, mobile +
// phone fields with native call-on-tap, Notes, edit/share/delete in the
// nav bar. A bespoke SwiftUI redraw of that surface drifted on every iOS
// release and looked obviously off next to a real contact card — so the
// only correct answer is to host Apple's view controller verbatim.
//
// The CNContact passed in must already carry every key listed in
// `ContactsManager.fetchKeys` (which includes
// `CNContactViewController.descriptorForRequiredKeys()`); otherwise the
// view controller throws on `assertKeysAreAvailable:`. AppContacts
// loaded by `ContactsManager.fetchAllContacts()` already include the
// full set, so this works straight from the list.
struct ContactDetailView: View {
    let contact: AppContact
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let cn = contact.cnContact {
            NativeContactCard(contact: cn, onDone: { dismiss() })
                .ignoresSafeArea()
        } else {
            // Fallback path — only hit when AppContact was constructed
            // without a backing CNContact (currently never happens for
            // contacts loaded from CNContactStore, but keep a sane
            // failure state instead of presenting an empty sheet).
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Contact unavailable")
                    .font(.headline)
                Text("This contact can't be opened. It may have been removed from your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Native Contact Card
//
// Hosts `CNContactViewController(for:)` inside a UINavigationController
// so the system supplies its own large title, Edit/Share/Delete
// toolbar, and Cancel-on-edit handling. We add ONLY a "Done" left-nav
// button on the root so the user can dismiss the sheet without going
// through the system's edit flow.
//
// `allowsEditing = true` and `allowsActions = true` are deliberate —
// the user explicitly asked for the iOS Contacts experience: tap a
// number to call, tap "Edit" to mutate the saved record, tap "Delete
// Contact" at the bottom to remove it. The contact lives in the real
// address book (CNContactStore), so any change made here propagates
// system-wide just like an edit inside Apple's Contacts.app.
struct NativeContactCard: UIViewControllerRepresentable {
    let contact: CNContact
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(for: contact)
        vc.contactStore = CNContactStore()
        vc.allowsEditing = true
        vc.allowsActions = true
        vc.delegate = context.coordinator

        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.handleDone)
        )
        // Place on the leading edge — Apple uses Done on the LEFT for
        // sheets where there's no separate save action (saved contact
        // view). System Edit lives on the trailing edge as usual.
        vc.navigationItem.leftBarButtonItem = doneButton

        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        @objc func handleDone() { onDone() }

        // Fires when the user finishes (or cancels) an Edit pass, OR
        // when the contact is deleted from the action sheet at the
        // bottom of the card. In either case dismiss the sheet so the
        // user lands back on the list — which will refresh from
        // CNContactStore on the next observer tick.
        func contactViewController(
            _ viewController: CNContactViewController,
            didCompleteWith contact: CNContact?
        ) {
            onDone()
        }
    }
}
