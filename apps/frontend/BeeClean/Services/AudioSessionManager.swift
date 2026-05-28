import AVFoundation
import UIKit

/// Owns the app's `AVAudioSession` lifecycle.
///
/// Why this exists: before this, the app never configured a session, so
/// `AVAudioPlayer` defaulted to `.soloAmbient`. Symptoms:
///   1. After any interruption (call, Siri, AirPods reconnect, app pushes
///      audio briefly), the session stayed deactivated and every later
///      `play()` was a silent no-op until relaunch — exactly matching
///      "sound gets stuck and stops working entirely" from TestFlight.
///   2. `CHHapticEngine` stopped on the same interruptions and never
///      restarted because `HapticManager`'s stoppedHandler was empty.
///
/// Strategy: `.playback + .mixWithOthers` — media the user expects to
/// hear. `.playback` ignores the physical silent/ringer switch, so cleanup
/// video audio plays even when the phone is silenced (the per-video mute
/// toggle still applies on top). `.mixWithOthers` lets Spotify/Podcasts
/// keep playing underneath instead of being force-stopped. We observe the
/// three notifications iOS uses to tell us something went wrong and
/// re-`setActive(true)` so the next `play()` from any of our players just
/// works.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private let session = AVAudioSession.sharedInstance()
    private var hasConfigured = false

    /// Notification fan-out so `HapticManager` (and any future audio
    /// engine) can also rebuild its state on interruption-end without
    /// each component duplicating the AVAudioSession plumbing.
    static let didReactivate = Notification.Name("BeeCleanAudioSessionDidReactivate")

    /// Reference count for `requestExclusivePlayback()` calls. The swipe
    /// deck, guided cleanup, and any future flow that wants to take over
    /// audio from Spotify/YouTube/etc. enters via `requestExclusivePlayback()`
    /// and exits via `releaseExclusivePlayback()`. The count is reference-
    /// counted so nested call sites (a swipe deck launched from inside
    /// guided cleanup) don't release each other's hold.
    private var exclusiveHoldCount: Int = 0

    private init() {}

    // MARK: - Public

    /// Call once at app launch. Idempotent — repeat calls just re-activate.
    func configure() {
        if !hasConfigured {
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } catch {
                print("[AudioSession] setCategory failed: \(error.localizedDescription)")
            }

            // One-time observer registration. Using NotificationCenter (not
            // structured concurrency) so the handlers fire even when the
            // app is mid-suspension on backgrounding.
            let nc = NotificationCenter.default
            nc.addObserver(
                self,
                selector: #selector(handleInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
            nc.addObserver(
                self,
                selector: #selector(handleRouteChange(_:)),
                name: AVAudioSession.routeChangeNotification,
                object: session
            )
            nc.addObserver(
                self,
                selector: #selector(handleMediaServicesReset),
                name: AVAudioSession.mediaServicesWereResetNotification,
                object: session
            )
            nc.addObserver(
                self,
                selector: #selector(handleAppForeground),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
            hasConfigured = true
        }
        activate()
    }

    /// Idempotent best-effort activation. Call before every `play()` —
    /// cheap when already active, recovers automatically if the session
    /// got deactivated by an interruption we missed.
    @discardableResult
    func ensureActive() -> Bool {
        // setActive(true) is cheap when already active; iOS short-circuits.
        return activate()
    }

    // MARK: - Exclusive Playback (Spotify/YouTube take-over)
    //
    // Reference-counted "take over the system audio" mode. Used by the
    // Quick Cleanup swipe deck and Guided Cleanup so any background
    // audio (Spotify, YouTube Music, podcasts, etc.) gets PAUSED while
    // the cleanup flow is active, and our own audio (video previews,
    // sound effects) plays uninterrupted. On release we tell the system
    // others may resume.
    //
    // Implementation: switch the category to `.playback` with NO
    // `.mixWithOthers` option, then `setActive(true)`. iOS pauses any
    // other-app audio at that point. On release we `setActive(false,
    // options: .notifyOthersOnDeactivation)` which is the
    // documented hint to Spotify/YouTube to auto-resume their playback.

    /// Request exclusive audio. Reference-counted — every call must be
    /// matched with `releaseExclusivePlayback()`. Safe to nest.
    func requestExclusivePlayback() {
        exclusiveHoldCount += 1
        guard exclusiveHoldCount == 1 else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[AudioSession] requestExclusivePlayback failed: \(error.localizedDescription)")
        }
    }

    /// Release one exclusive-playback hold. When the count returns to
    /// zero we re-enter `.mixWithOthers` and notify other apps so
    /// Spotify/YouTube etc. can auto-resume their audio.
    func releaseExclusivePlayback() {
        guard exclusiveHoldCount > 0 else { return }
        exclusiveHoldCount -= 1
        guard exclusiveHoldCount == 0 else { return }
        do {
            // Deactivate FIRST with the notify flag so other apps wake.
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            // Restore the app-wide ambient default so taps/haptics still
            // work and we don't keep blocking other audio post-flow.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[AudioSession] releaseExclusivePlayback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    @discardableResult
    private func activate() -> Bool {
        do {
            try session.setActive(true, options: [])
            return true
        } catch {
            print("[AudioSession] setActive(true) failed: \(error.localizedDescription)")
            return false
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            // System has paused our audio. Don't fight it; we'll resume on .ended.
            print("[AudioSession] interruption began")
        case .ended:
            // Re-activate so the next play() / haptic call works. The
            // shouldResume option from the system is informational; for
            // UI sounds we always want to be ready when the user taps.
            print("[AudioSession] interruption ended → reactivating")
            if activate() {
                NotificationCenter.default.post(name: AudioSessionManager.didReactivate, object: nil)
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // Headphones unplugged, AirPods disconnected, etc. iOS may have
        // implicitly deactivated the session. Re-activate to be safe.
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep:
            activate()
        default:
            break
        }
    }

    @objc private func handleMediaServicesReset() {
        // Rare but real: the audio server crashed and iOS rebuilt it.
        // Everything we configured is gone — re-do category + activate.
        print("[AudioSession] mediaServicesWereReset → reconfiguring")
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            print("[AudioSession] setCategory after reset failed: \(error.localizedDescription)")
        }
        if activate() {
            NotificationCenter.default.post(name: AudioSessionManager.didReactivate, object: nil)
        }
    }

    @objc private func handleAppForeground() {
        // Backgrounding can leave the session inactive. Reactivate so the
        // first tap on return doesn't silently fail.
        activate()
    }
}
