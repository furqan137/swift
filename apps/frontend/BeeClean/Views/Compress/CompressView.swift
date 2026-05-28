import SwiftUI
import Photos
import PhotosUI
import AVFoundation

// MARK: - Compress Category
enum CompressCategory: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Videos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .photos: return "photo.fill"
        case .videos: return "video.fill"
        }
    }
}

// MARK: - Compress ViewModel (persists across tab switches)
//
// Inherits NSObject so it can register as a `PHPhotoLibraryChangeObserver`.
// That observer is the load-bearing mechanism that keeps the grid honest:
// any time iOS Photos broadcasts a library change (delete from BeeClean,
// delete from Photos.app, sync down a deletion from iCloud, Recently
// Deleted purge, etc.) we refetch the localIdentifiers of every row and
// drop the ones whose PHAsset has gone missing. This is the canonical
// fix for "I deleted a photo and the grid still shows it" — manual
// `removePhoto` calls in the detail view's `runDelete` path are kept as
// a fast-path so the UI reacts instantly without waiting for the system
// to broadcast, but the observer is the safety net for everything else.
@MainActor
class CompressViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = CompressViewModel()

    @Published var videos: [VideoAsset] = []
    @Published var videoTotalSize: Int64 = 0
    @Published var videoPotentialSavings: Int64 = 0
    @Published var isLoadingVideos = false
    @Published var hasLoadedVideos = false

    @Published var photos: [PhotoAsset] = []
    @Published var photoTotalSize: Int64 = 0
    @Published var photoPotentialSavings: Int64 = 0
    @Published var isLoadingPhotos = false
    @Published var hasLoadedPhotos = false

    // Scan progress — surfaced by the loading UI so users can see the
    // camera roll being swept through in real time instead of staring
    // at a spinner. `scanTotal` is the candidate count *after* the cheap
    // pre-filter; `scanProcessed` ticks up as each PHAssetResource fetch
    // returns. Both zero when idle.
    @Published var scanTotal: Int = 0
    @Published var scanProcessed: Int = 0
    var scanProgress: Double {
        scanTotal > 0 ? min(Double(scanProcessed) / Double(scanTotal), 1.0) : 0
    }

    private override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - PHPhotoLibraryChangeObserver
    //
    // Called on a non-main thread by Photos. Hop to MainActor, prune any
    // assets that disappeared, and queue ONE debounced incremental scan
    // for newly-arrived assets.
    //
    // iOS often broadcasts 3–5 change notifications in rapid succession
    // for a single user action (e.g., Save & Replace Original fires
    // change events for: write begin, write end, delete begin, delete
    // end, asset modified). Naively kicking off a fresh scan on each
    // would run 5 concurrent diff scans that race the same photos
    // array — that's what was causing the "rescan keeps happening"
    // lag the user reported. The 350ms coalescing window collapses
    // the burst into a single pass.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pruneDeletedAssetsFromGrid()
            self.scheduleIncrementalScan()
        }
    }

    /// Coalesce-and-dedupe the incremental scan so a burst of library
    /// change events runs at most one scan, and a scan in flight is
    /// never overlapped by a second one.
    @MainActor
    private func scheduleIncrementalScan() {
        // Cancel any pending coalesce timer — restart the window.
        pendingIncrementalScanTask?.cancel()
        pendingIncrementalScanTask = Task { @MainActor [weak self] in
            // 250ms coalesce window. The iOS burst from a single user
            // action (capture / edit / sync) settles inside ~200ms; 250ms
            // catches the tail without making the user notice a delay.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            // Single-flight: if a scan is already mid-pass, record that
            // *another* change came in. The in-flight pass might have
            // already enumerated past the new asset, so once it finishes
            // we run one more sweep to catch what it missed. Previously
            // the new change was just dropped, leaving the grid stale
            // until the user manually reopened the tab.
            guard !self.isIncrementalScanInFlight else {
                self.missedChangeDuringScan = true
                return
            }
            self.isIncrementalScanInFlight = true
            await self.incrementalScanForNewAssets()
            // Drain any change that arrived mid-scan before clearing the
            // in-flight flag — one extra pass max, then we settle.
            while self.missedChangeDuringScan {
                self.missedChangeDuringScan = false
                await self.incrementalScanForNewAssets()
            }
            self.isIncrementalScanInFlight = false
        }
    }

    /// True while `incrementalScanForNewAssets` is mid-pass. Gates the
    /// debounced scheduler so concurrent observer firings can't race
    /// each other and pile up multiple scans on the photos/videos arrays.
    @Published var isIncrementalScanInFlight = false

    /// Set when a library-change event fires while a scan is already
    /// running. The scan's completion handler drains this flag with a
    /// follow-up pass so the new asset doesn't get stranded outside the
    /// grid until the user re-enters the tab.
    var missedChangeDuringScan = false

    /// Pending coalesce task — replaced on each library-change event so
    /// only the most recent fires after the debounce window.
    var pendingIncrementalScanTask: Task<Void, Never>?

    // MARK: - Scan Tasks (owned by the singleton, NOT the view)
    //
    // The Compress tab's first scan can take 30–90 seconds on a large
    // library. If the user switches tabs (or opens a compression detail
    // view that pushes onto the NavigationStack), `CompressView` tears
    // down and SwiftUI cancels its `.task` modifier — which used to
    // own the load. The cancellation propagated through `await` into
    // `loadPhotos` / `loadVideos`, killing them mid-pass without ever
    // setting `hasLoadedPhotos = true`. On re-entry the view saw
    // `hasLoadedPhotos == false` and started the WHOLE scan over from
    // scratch — exactly the "rescan keeps happening when I come back"
    // bug.
    //
    // Holding the Task on the singleton severs that lifecycle link.
    // The view is free to be torn down and rebuilt at will; the scan
    // continues uninterrupted on the singleton, and on the next visit
    // the view simply observes the published state.
    var photoLoadTask: Task<Void, Never>?
    var videoLoadTask: Task<Void, Never>?

    /// Idempotent kickoff. Call from `CompressView.task` (or any other
    /// surface that needs the data ready). Starts a load task on the
    /// singleton if no scan is already running for that media type and
    /// the type hasn't already been loaded. Multiple calls coalesce —
    /// the second call sees an in-flight task and just returns.
    @MainActor
    func ensureLoaded() {
        if !hasLoadedPhotos, photoLoadTask == nil {
            photoLoadTask = Task { @MainActor [weak self] in
                await self?.loadPhotos()
                self?.photoLoadTask = nil
            }
        }
        if !hasLoadedVideos, videoLoadTask == nil {
            videoLoadTask = Task { @MainActor [weak self] in
                await self?.loadVideos()
                self?.videoLoadTask = nil
            }
        }
    }

}

// MARK: - Compress View
struct CompressView: View {
    var showsBackButton: Bool = false

    @StateObject var vm = CompressViewModel.shared
    @StateObject var resume = CompressResumeManager.shared

    // UI-only state (resets per visit — that's fine)
    @State var category: CompressCategory = .photos
    /// Set when the user taps "Let's Go" on the resume sheet — drives the
    /// `ScrollViewReader.onChange` that scrolls the grid back to the
    /// saved index once the sheet dismisses.
    @State var pendingScrollCategory: CompressCategory?
    @State var showFilters = false
    @State var sortOption: SortOption = .largest
    @State var startDate: Date?
    @State var endDate: Date?
    @State var selectedItems: [PhotosPickerItem] = []

    // Cached sort/filter outputs — see CompressView+Body's `.task(id:)`
    // modifiers for refresh logic. The previous build redeclared these
    // as computed properties that re-walked `vm.photos` / `vm.videos`
    // (filter + dedup + sort) every time they were read, and they were
    // read 5+ times per body render: by `currentDisplayCount`,
    // `filteredPhotoSavings`, `evaluateResumePrompt`, `contentGrid`'s
    // ForEach, and the `.onChange(of: currentDisplayCount)` modifier.
    // On a 4500-photo library the O(n log n) sort dominated body
    // re-evaluations and turned every sort-pill toggle into a 200ms+
    // CPU spike. Caching as @State lets the view treat them as
    // immutable per render — the refresh fires exactly once when
    // `(vm.photos.count, sortOption, startDate, endDate)` actually
    // changes.
    @State var sortedPhotos: [PhotoAsset] = []
    @State var sortedVideos: [VideoAsset] = []

    @Namespace var categoryNamespace
    @Environment(\.dismiss) var dismiss

    // MARK: Sort cache keys

    /// Composite identity of every input that drives `sortedPhotos`. The
    /// `.task(id:)` modifier on the body uses this; whenever any field
    /// changes, the task re-fires and `recomputeSortedPhotos()` rebuilds
    /// the cache. Using an `Equatable` struct (over a stringly-typed
    /// joined hash) lets SwiftUI's identity diff bail out cheaply when
    /// nothing has changed.
    struct PhotoSortKey: Equatable {
        let count: Int
        let sort: SortOption
        let startDate: Date?
        let endDate: Date?
    }

    struct VideoSortKey: Equatable {
        let count: Int
        let sort: SortOption
        let startDate: Date?
        let endDate: Date?
    }

    var photoSortKey: PhotoSortKey {
        PhotoSortKey(count: vm.photos.count, sort: sortOption, startDate: startDate, endDate: endDate)
    }

    var videoSortKey: VideoSortKey {
        VideoSortKey(count: vm.videos.count, sort: sortOption, startDate: startDate, endDate: endDate)
    }

    func recomputeSortedPhotos() {
        var seen = Set<String>()
        var filtered = vm.photos.filter { seen.insert($0.id).inserted }
        if let start = startDate {
            filtered = filtered.filter { $0.creationDate >= start }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            filtered = filtered.filter { $0.creationDate < endOfDay }
        }
        switch sortOption {
        case .largest:  sortedPhotos = filtered.sorted { $0.fileSize > $1.fileSize }
        case .smallest: sortedPhotos = filtered.sorted { $0.fileSize < $1.fileSize }
        case .newest:   sortedPhotos = filtered.sorted { $0.creationDate > $1.creationDate }
        case .oldest:   sortedPhotos = filtered.sorted { $0.creationDate < $1.creationDate }
        }
    }

    func recomputeSortedVideos() {
        var seen = Set<String>()
        var filtered = vm.videos.filter { seen.insert($0.id).inserted }
        if let start = startDate {
            filtered = filtered.filter { $0.creationDate >= start }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            filtered = filtered.filter { $0.creationDate < endOfDay }
        }
        switch sortOption {
        case .largest:  sortedVideos = filtered.sorted { $0.fileSize > $1.fileSize }
        case .smallest: sortedVideos = filtered.sorted { $0.fileSize < $1.fileSize }
        case .newest:   sortedVideos = filtered.sorted { $0.creationDate > $1.creationDate }
        case .oldest:   sortedVideos = filtered.sorted { $0.creationDate < $1.creationDate }
        }
    }

}

// MARK: - CompressView: Derived Data
extension CompressView {

    // MARK: - Derived data

    // `sortedVideos` and `sortedPhotos` live as @State on the main
    // CompressView struct above. They're refreshed exclusively by the
    // `.task(id: photoSortKey/videoSortKey)` hooks attached in
    // CompressView+Body — never by inline computed-property
    // re-evaluation. Reading them here is a Swift array indirection,
    // not a recomputation.

    var hasDateFilter: Bool {
        startDate != nil || endDate != nil
    }

    var filteredVideoSavings: Int64 {
        sortedVideos.reduce(0) { $0 + $1.potentialSavings }
    }

    var filteredPhotoSavings: Int64 {
        sortedPhotos.reduce(0) { $0 + $1.potentialSavings }
    }

    var isCurrentLoading: Bool {
        // The loading view is only shown when there's genuinely nothing to
        // render yet. As soon as the streaming scan flushes its first
        // batch into the published list, we switch to the grid — users
        // see cards populating live, with the savings banner's totals
        // ticking up as more batches arrive.
        if category == .videos {
            return (vm.isLoadingVideos || !vm.hasLoadedVideos) && vm.videos.isEmpty
        } else {
            return (vm.isLoadingPhotos || !vm.hasLoadedPhotos) && vm.photos.isEmpty
        }
    }

    var currentTotalSize: Int64 {
        category == .videos ? vm.videoTotalSize : vm.photoTotalSize
    }

    var currentPotentialSavings: Int64 {
        category == .videos ? vm.videoPotentialSavings : vm.photoPotentialSavings
    }

    var currentFilteredSavings: Int64 {
        category == .videos ? filteredVideoSavings : filteredPhotoSavings
    }

    var currentSourceCount: Int {
        category == .videos ? vm.videos.count : vm.photos.count
    }

    var currentDisplayCount: Int {
        category == .videos ? sortedVideos.count : sortedPhotos.count
    }

    var currentIsEmpty: Bool {
        category == .videos ? vm.videos.isEmpty : vm.photos.isEmpty
    }

}

