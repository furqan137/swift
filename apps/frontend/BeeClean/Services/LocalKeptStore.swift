import Foundation
import Combine

// MARK: - LocalKeptStore
/// On-device persistence for "kept" identifiers across features:
/// long videos, blurry photos, contact duplicate groups, and email senders.
///
/// Storage: one JSON blob per namespace under Application Support/BeeClean/kept/.
/// Thread model: `@MainActor` singleton — all reads/writes are serialized on the
/// main actor, which matches how the view models that consume it are modeled.
/// Each namespace stores a `Set<String>` of normalized identifiers.
@MainActor
final class LocalKeptStore: ObservableObject {
    static let shared = LocalKeptStore()

    enum Namespace: String, CaseIterable {
        case longVideos
        case blurryPhotos
        case contactDuplicateGroups
        case emailSenders
    }

    // One published set per namespace so Views can observe changes.
    @Published private(set) var longVideoIds: Set<String> = []
    @Published private(set) var blurryPhotoIds: Set<String> = []
    @Published private(set) var contactGroupHashes: Set<String> = []
    @Published private(set) var emailSenders: Set<String> = []

    private let fileManager = FileManager.default
    private let directoryURL: URL

    private init() {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.directoryURL = base
            .appendingPathComponent("BeeClean", isDirectory: true)
            .appendingPathComponent("kept", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Disk reads (4 JSON files) are dispatched to a userInitiated
        // detached Task so the singleton's first access doesn't block
        // app startup or whichever main-actor view body happens to
        // resolve `LocalKeptStore.shared` first. Until the load
        // completes the published sets are empty — `@Published` fires
        // an update wave once the load lands so consumers re-render
        // automatically. The transient-empty window only affects the
        // blurry-photos / long-videos / contact-dups / email-senders
        // "kept" filters; worst case a previously-kept item shows up
        // for ~1 frame before getting filtered out.
        Task { [weak self] in await self?.loadAllAsync() }
    }

    // MARK: - Public API

    func contains(_ id: String, in namespace: Namespace) -> Bool {
        switch namespace {
        case .longVideos: return longVideoIds.contains(id)
        case .blurryPhotos: return blurryPhotoIds.contains(id)
        case .contactDuplicateGroups: return contactGroupHashes.contains(id)
        case .emailSenders: return emailSenders.contains(normalizeEmail(id))
        }
    }

    func ids(in namespace: Namespace) -> Set<String> {
        switch namespace {
        case .longVideos: return longVideoIds
        case .blurryPhotos: return blurryPhotoIds
        case .contactDuplicateGroups: return contactGroupHashes
        case .emailSenders: return emailSenders
        }
    }

    func add(_ id: String, to namespace: Namespace) {
        add([id], to: namespace)
    }

    func add(_ ids: some Sequence<String>, to namespace: Namespace) {
        let normalized: Set<String> = {
            switch namespace {
            case .emailSenders: return Set(ids.map(normalizeEmail).filter { !$0.isEmpty })
            default: return Set(ids.filter { !$0.isEmpty })
            }
        }()
        guard !normalized.isEmpty else { return }

        switch namespace {
        case .longVideos:
            let before = longVideoIds
            longVideoIds.formUnion(normalized)
            if longVideoIds != before { persist(namespace, longVideoIds) }
        case .blurryPhotos:
            let before = blurryPhotoIds
            blurryPhotoIds.formUnion(normalized)
            if blurryPhotoIds != before { persist(namespace, blurryPhotoIds) }
        case .contactDuplicateGroups:
            let before = contactGroupHashes
            contactGroupHashes.formUnion(normalized)
            if contactGroupHashes != before { persist(namespace, contactGroupHashes) }
        case .emailSenders:
            let before = emailSenders
            emailSenders.formUnion(normalized)
            if emailSenders != before { persist(namespace, emailSenders) }
        }
    }

    func remove(_ id: String, from namespace: Namespace) {
        let key: String = namespace == .emailSenders ? normalizeEmail(id) : id
        switch namespace {
        case .longVideos:
            guard longVideoIds.remove(key) != nil else { return }
            persist(namespace, longVideoIds)
        case .blurryPhotos:
            guard blurryPhotoIds.remove(key) != nil else { return }
            persist(namespace, blurryPhotoIds)
        case .contactDuplicateGroups:
            guard contactGroupHashes.remove(key) != nil else { return }
            persist(namespace, contactGroupHashes)
        case .emailSenders:
            guard emailSenders.remove(key) != nil else { return }
            persist(namespace, emailSenders)
        }
    }

    func clear(_ namespace: Namespace) {
        switch namespace {
        case .longVideos: longVideoIds = []
        case .blurryPhotos: blurryPhotoIds = []
        case .contactDuplicateGroups: contactGroupHashes = []
        case .emailSenders: emailSenders = []
        }
        persist(namespace, [])
    }

    // MARK: - Disk I/O

    private func fileURL(for namespace: Namespace) -> URL {
        directoryURL.appendingPathComponent("\(namespace.rawValue).json")
    }

    private func loadAllAsync() async {
        // All 4 disk reads + JSON decodes run on a detached background
        // Task so they never block the main actor — one trip off-main,
        // back to apply results in a single batched main-actor write.
        let dir = directoryURL
        let loaded = await Task.detached(priority: .userInitiated) { () -> [String: Set<String>] in
            var out: [String: Set<String>] = [:]
            for ns in Namespace.allCases {
                let url = dir.appendingPathComponent("\(ns.rawValue).json")
                if let data = try? Data(contentsOf: url),
                   let arr = try? JSONDecoder().decode([String].self, from: data) {
                    out[ns.rawValue] = Set(arr)
                } else {
                    out[ns.rawValue] = []
                }
            }
            return out
        }.value

        // Merge instead of clobber. MainActor serializes the user's
        // `add(...)` taps against this continuation, but if a tap landed
        // first while the disk read was in-flight, the published set
        // already holds in-flight entries — `=` would wipe them out.
        // The in-memory adds were also synchronously persisted to disk,
        // so they exist in `loaded` too; `formUnion` makes the merge a
        // no-op for already-present ids.
        longVideoIds.formUnion(loaded[Namespace.longVideos.rawValue] ?? [])
        blurryPhotoIds.formUnion(loaded[Namespace.blurryPhotos.rawValue] ?? [])
        contactGroupHashes.formUnion(loaded[Namespace.contactDuplicateGroups.rawValue] ?? [])
        emailSenders.formUnion(loaded[Namespace.emailSenders.rawValue] ?? [])
    }

    private func persist(_ namespace: Namespace, _ set: Set<String>) {
        let url = fileURL(for: namespace)
        // Sort for stable diffs if file is ever inspected.
        let arr = Array(set).sorted()
        do {
            let data = try JSONEncoder().encode(arr)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[LocalKeptStore] persist \(namespace.rawValue) failed: \(error)")
        }
    }

    // MARK: - Hashing helpers

    /// Stable hash of a contact duplicate group — sorted member contact IDs
    /// joined by `|`. Same input always yields the same hash, regardless of
    /// which contact the VM happened to label the "primary".
    /// `nonisolated` because the body is pure (no actor state) and we
    /// need to call it from background tasks (e.g. the detached
    /// duplicate-detection pass) without bouncing back to MainActor.
    nonisolated static func contactGroupHash(contactIds: [String]) -> String {
        contactIds.sorted().joined(separator: "|")
    }

    private func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
