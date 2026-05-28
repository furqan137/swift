import Foundation
import Contacts
import Combine
import SwiftUI

// MARK: - Contacts ViewModel (Presentation Layer)
@MainActor
class ContactsViewModel: ObservableObject {
    static let shared = ContactsViewModel()

    // MARK: - Published State
    @Published var allContacts: [AppContact] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var incompleteContacts: [AppContact] = []
    @Published var permissionStatus: CNAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Computed Stats (dynamic)
    var totalContacts: Int { allContacts.count }
    var duplicateCount: Int { duplicateGroups.reduce(0) { $0 + max(0, $1.count - 1) } }
    var duplicateGroupCount: Int { duplicateGroups.count }
    var incompleteCount: Int { incompleteContacts.count }

    var hasAccess: Bool {
        permissionStatus.grantsContactAccess
    }

    // MARK: - Dependencies
    let service: any ContactsServiceProtocol
    var changeObserver: AnyCancellable?
    /// Cancelled whenever a new error arrives so rapid-fire failures don't
    /// pile up stale auto-clear tasks that fight each other.
    var errorClearTask: Task<Void, Never>?

    /// In-flight bulk merge / delete Task. Stored here (not owned by the
    /// view) so that dismissing the contacts sheet mid-merge doesn't
    /// orphan an unowned Task that's still calling into CNSaveRequest
    /// and writing back to `duplicateGroups` / `allContacts` after the
    /// view dismisses. Multi-thousand-contact merges can run for 10+
    /// seconds; the user shouldn't have to wait on the dismiss to
    /// complete the work, but they also shouldn't see late writes
    /// flicker into the next surface they navigate to. Replaced on each
    /// new bulk operation; cancelled in `cancelInFlight()`.
    var inFlightBulkTask: Task<Void, Never>?

    // MARK: - Init
    init() {
        self.service = ContactsManager.shared
        self.permissionStatus = ContactsManager.shared.permissionStatus()
        observeContactChanges()
    }

    // MARK: - Permissions (Step 1)

    func requestPermission() async -> Bool {
        do {
            let granted = try await service.requestAccess()
            permissionStatus = service.permissionStatus()
            return granted || hasAccess
        } catch {
            setError(error.localizedDescription)
            permissionStatus = service.permissionStatus()
            return hasAccess
        }
    }

    func checkPermission() {
        permissionStatus = service.permissionStatus()
    }

    // MARK: - Load Contacts (Step 2)

    func loadContacts() async {
        // Prevent concurrent loads
        guard !isLoading else { return }
        isLoading = true
        error = nil

        checkPermission()
        if !hasAccess {
            let granted = await requestPermission()
            if !granted {
                isLoading = false
                return
            }
        }

        do {
            allContacts = try await service.loadContacts()
            await findDuplicates()
            findIncomplete()

            if allContacts.isEmpty {
                print("[ContactsVM] 0 contacts loaded (normal on simulator).")
            } else {
                print("[ContactsVM] \(allContacts.count) contacts, \(duplicateGroups.count) dup groups, \(incompleteContacts.count) incomplete.")
            }
        } catch {
            setError("Failed to load contacts: \(error.localizedDescription)")
            print("[ContactsVM] Load error: \(error)")
        }

        isLoading = false
    }

    /// Remove stale IDs from a selection set after contacts have been reloaded.
    func pruneSelection(_ selection: inout Set<String>) {
        let validIDs = Set(allContacts.map { $0.id })
        selection = selection.intersection(validIDs)
    }


    deinit {
        errorClearTask?.cancel()
    }

}
