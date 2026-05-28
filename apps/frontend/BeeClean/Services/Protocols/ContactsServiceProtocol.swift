import Foundation
import Contacts

protocol ContactsServiceProtocol: AnyObject {
    func permissionStatus() -> CNAuthorizationStatus
    var hasAccess: Bool { get }
    func requestAccess() async throws -> Bool
    func loadContacts() async throws -> [AppContact]
    func merge(primary: AppContact, duplicates: [AppContact]) async throws
    func remove(_ contacts: [AppContact]) async throws
    func export(_ contacts: [AppContact]) throws -> URL
    func backup(_ contacts: [AppContact]) throws -> URL
}
