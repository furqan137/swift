import SwiftUI
import Contacts
import ContactsUI

// MARK: - Merge Preview View
//
// Cleanup-mirrored merge-preview flow, on the Bitepal theme.
//
// Entry: user has checkmarked ≥1 duplicate in ContactListView (.duplicates)
// and tapped the blue "See Merge Preview" CTA.
//
// Layout (top → bottom):
//   • Bitepal cool-gradient canvas
//   • Lavender-pill back chevron, top-left
//   • "Duplicates" Poppins-Bold title + "{N} Contact" subtitle (N = number
//     of groups that will produce a merged-result, NOT total contacts)
//   • One white glass card per group-with-selection:
//       – "{count} Contacts Merged" header + lavender X chip
//       – Single tappable preview row showing the merged-result name +
//         all combined phones (• -joined). Outline accent in Bitepal blue.
//   • Empty state when nothing is left to merge: "No Preview Available"
//   • Sticky blue capsule CTA: "Merge {N} Contacts"
//   • Confirm alert → backup prompt sheet → on-device merge via
//     `ContactsViewModel.mergeSelectedContactsByGroup`
//
// Tap a preview row → native `CNContactViewController(forUnknownContact:)`
// in read-only mode, populated with a CNMutableContact built from the
// selected subset. Lets the user see EXACTLY what the merged contact will
// look like before committing. No mock data — every field comes from real
// CNContact records via CNContactStore.
struct MergePreviewView: View {
    let groups: [DuplicateGroup]
    /// Live binding to the parent's selection set. Bound (not a copy) so
    /// the per-group X-dismiss in this sheet can REMOVE that group's
    /// contact IDs from the parent's selectedContacts directly. Without
    /// the binding, dismissing a group from the preview would leave its
    /// IDs marked-for-merge in the parent — selection and preview would
    /// drift, the bottom CTA could keep showing for ghost selections,
    /// and the next preview open would re-include the dismissed group.
    @Binding var selectedIds: Set<String>
    let onMerge: () async -> (merged: Int, deleted: Int)

    @ObservedObject var viewModel = ContactsViewModel.shared
    @ObservedObject var backupService = BackupService.shared
    @Environment(\.dismiss) var dismiss

    @State var previewContact: PreviewContact?
    @State var showConfirmAlert = false
    @State var showBackupPrompt = false
    @State var isMerging = false
    @State var isBackingUp = false
    @State var didMerge = false
    /// Number of duplicate GROUPS the most recent merge collapsed.
    /// Used by the success state to read back "N Contacts Merged".
    @State var mergedGroupCount: Int = 0
    /// Number of individual DUPLICATE contacts that were absorbed into
    /// their group's primary (i.e. the count that disappeared from the
    /// address book). The success copy uses this to show the user what
    /// they actually freed up.
    @State var mergedDeletedCount: Int = 0
    /// Surfaces a backup failure to the user so the merge isn't silently
    /// committed against an un-backed library. Non-nil = failed alert.
    @State var backupErrorMessage: String?

    // MARK: - Derived

    /// Groups that should appear in the preview — those with ≥2 selected
    /// contacts. The X-dismiss button works by removing that group's
    /// contact IDs from `selectedIds` directly, so a dismissed group
    /// naturally fails this ≥2 test and disappears — no separate
    /// "dismissed" set needed, and the parent's selection stays in
    /// lock-step with what's visible here.
    /// After a merge completes, this collapses to empty and the empty
    /// state renders.
    var visibleGroups: [DuplicateGroup] {
        guard !didMerge else { return [] }
        return groups.compactMap { group in
            selectedContactsInGroup(group).count >= 2 ? group : nil
        }
    }

    var totalMergedContacts: Int {
        visibleGroups.count
    }

    var totalContactsToMerge: Int {
        visibleGroups.reduce(0) { $0 + selectedContactsInGroup($1).count }
    }

    func selectedContactsInGroup(_ group: DuplicateGroup) -> [AppContact] {
        group.contacts.filter { selectedIds.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                BitepalCanvas()

                VStack(spacing: 0) {
                    header

                    if didMerge {
                        // Just-finished merge — show the celebration
                        // state with the actual numbers, not the
                        // generic "go back and select" empty copy.
                        successView
                    } else if visibleGroups.isEmpty {
                        emptyStateView
                    } else {
                        previewListContent
                    }
                }

                if !visibleGroups.isEmpty {
                    // Sticky bottom CTA inside a backdrop strip so the
                    // scroll content behind it doesn't visibly bleed
                    // past the button. The "Before you merge" footer
                    // lives INLINE below the merged card now (in
                    // `previewListContent`), per user direction —
                    // explainer reads as adjacent to the merged
                    // result, not as a separate bottom anchor.
                    VStack(spacing: 0) {
                        Spacer()
                        bottomCTABackdrop {
                            mergeCTA
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.light)
        .alert(
            "Are you sure you want to merge duplicate contacts?",
            isPresented: $showConfirmAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Yes") {
                // Don't merge yet — surface the backup prompt first. The
                // backup is itself optional ("No, Thanks" is allowed) but
                // the user gets one chance to capture state before the
                // change becomes irreversible.
                showBackupPrompt = true
            }
        } message: {
            Text("This process cannot be reversed.")
        }
        .sheet(isPresented: $showBackupPrompt) {
            backupPromptSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(hex: "F4F5FA"))
        }
        // Backup-failure alert. Driven by `backupErrorMessage` going
        // non-nil from `runBackupThenMerge` when `createBackup` returns
        // false — without this surface, a write failure would silently
        // commit the merge against an un-backed library.
        .alert(
            "Backup didn't save",
            isPresented: Binding(
                get: { backupErrorMessage != nil },
                set: { if !$0 { backupErrorMessage = nil } }
            ),
            presenting: backupErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(item: $previewContact) { wrap in
            NativeContactPreview(contact: wrap.contact)
        }
    }

}

// MARK: - Preview Contact Wrapper
//
// Identifiable wrapper around CNContact for `.sheet(item:)` — the system
// CNContact type doesn't conform to Identifiable in the SDK, and even if
// it did, presenting an in-memory unsaved contact via the system sheet
// API requires our own stable id.
struct PreviewContact: Identifiable {
    let id = UUID()
    let contact: CNContact
}

// MARK: - Native Contact Preview
//
// Wraps `CNContactViewController(forUnknownContact:)` in a SwiftUI sheet.
// "Unknown contact" mode is the right API for previewing a contact that
// hasn't been saved to CNContactStore yet — it renders the standard iOS
// contact card layout (avatar, name, phones, emails) read-only, with the
// caller responsible for dismissal.
//
// Read-only on purpose: `allowsActions = false` removes the Add to
// Existing Contact / Create New Contact CTAs at the bottom (we don't want
// the user to accidentally save the preview as a separate contact),
// `allowsEditing = false` removes the Edit toolbar item.
struct NativeContactPreview: UIViewControllerRepresentable {
    let contact: CNContact
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = CNContactViewController(forUnknownContact: contact)
        preview.allowsActions = false
        preview.allowsEditing = false
        preview.contactStore = CNContactStore()
        // Top-LEFT close (X) button — standard iOS modal placement so
        // the user reads it instantly as "close this preview, take me
        // back to the merge flow." CNContactViewController ships without
        // a reliable bar button in `forUnknownContact:` mode, AND it
        // calls setNavigationBarHidden(true) on its parent during its
        // own viewWillAppear, which is why the previous attempt's
        // button was invisible — the bar itself was hidden by the
        // system controller. `PreviewNavController` below intercepts
        // that hide and keeps the bar visible so our X always renders.
        let coordinator = context.coordinator
        coordinator.dismiss = { dismiss() }
        let closeImage = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )
        let closeButton = UIBarButtonItem(
            image: closeImage,
            style: .plain,
            target: coordinator,
            action: #selector(Coordinator.handleDone)
        )
        closeButton.tintColor = UIColor(red: 28/255, green: 25/255, blue: 23/255, alpha: 1)
        closeButton.accessibilityLabel = "Close"
        preview.navigationItem.leftBarButtonItem = closeButton

        let nav = PreviewNavController(rootViewController: preview)
        nav.navigationBar.prefersLargeTitles = false
        nav.setNavigationBarHidden(false, animated: false)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var dismiss: (() -> Void)?

        @objc func handleDone() {
            dismiss?()
        }
    }
}

/// UINavigationController subclass that refuses to hide its bar.
/// CNContactViewController(forUnknownContact:) calls
/// `setNavigationBarHidden(true)` on its parent during viewWillAppear —
/// without this override our left-side X button vanishes the moment the
/// preview appears, which is the bug the user hit.
final class PreviewNavController: UINavigationController {
    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(false, animated: animated)
    }
}
