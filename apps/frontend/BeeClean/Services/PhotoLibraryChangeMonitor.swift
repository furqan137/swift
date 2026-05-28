import Foundation
import os
import Photos

// MARK: - Photo Library Change Monitor
//
// Watches the user's photo library and fires `onChange` whenever PhotoKit
// reports an add/delete/edit. This is what makes the scan cards feel alive:
// without it, new screenshots and camera captures don't show up until the
// user manually triggers a rescan.
//
// PhotoKit delivers notifications on an arbitrary background thread and can
// fire them in rapid bursts (a 50-photo import produces one per asset). We
// coalesce with a 2s debounce so the refresh runs once when things settle,
// not 50 times.
//
// Stop() race fix: the previous build released the lock immediately after
// scheduling the debounce task and ran the post-sleep `onChange()` invocation
// outside any synchronization. If `stop()` was called concurrently with a
// debounce task that had already passed `Task.isCancelled` but hadn't yet
// invoked `onChange`, the closure could fire into a coordinator that was
// already torn down. Rare but reproducible after deletes from another app
// (Files / AirDrop save) since those drive multiple `photoLibraryDidChange`
// calls on a background thread while the foreground app is also tearing
// the monitor down on dismiss. The fix:
//
//   • `isStopped` flag set under the lock in `stop()`
//   • The debounce task acquires the lock post-sleep, snapshots the
//     `onChange` closure ONLY if `isStopped` is still false, and invokes
//     outside the lock with the snapshot — never the live ivar.
//
// `Task.isCancelled` alone wasn't enough because it only catches the
// pre-cancellation race, not "stop() called between cancellation check and
// closure invocation."
final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    private let onChange: @Sendable () -> Void
    /// Async-safe primitive — `NSLock.lock`/`unlock` is unavailable in
    /// async contexts under Swift 6. `OSAllocatedUnfairLock`'s
    /// `withLock` closure runs synchronously inside the lock and
    /// returns the closure's value, so the post-sleep `isStopped`
    /// check inside the debounce task can use the same primitive
    /// without tripping the strict-concurrency checker.
    private let lock = OSAllocatedUnfairLock()
    private var debounceTask: Task<Void, Never>?
    private var isRegistered = false
    /// Set under `lock` in `stop()`. Read under `lock` post-sleep by the
    /// debounce task before invoking `onChange` — drops late deliveries
    /// that would otherwise hit a deinitialised owner.
    private var isStopped = false

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
    }

    func start() {
        lock.withLock {
            guard !isRegistered else { return }
            PHPhotoLibrary.shared().register(self)
            isRegistered = true
            isStopped = false
        }
    }

    func stop() {
        lock.withLock {
            guard isRegistered else { return }
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isRegistered = false
            isStopped = true
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.withLock {
            if isStopped { return }
            debounceTask?.cancel()
            // Capture `onChange` directly into the detached task. The
            // post-sleep `isStopped` re-check inside the task is the
            // real fix — without it, `stop()` could run between
            // `Task.isCancelled` returning false and the closure
            // invocation, and the call would land on a deinitialised
            // owner.
            let captured = self.onChange
            debounceTask = Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                guard let self = self else { return }
                // OSAllocatedUnfairLock.withLock is safe in async
                // contexts because the closure is synchronous and the
                // lock release is guaranteed on return.
                let stopped = self.lock.withLock { self.isStopped }
                if stopped { return }
                captured()
            }
        }
    }

    deinit {
        // Observer API holds a weak reference — if we're being deallocated,
        // we were already unregistered. Just tear down the debounce.
        debounceTask?.cancel()
    }
}
