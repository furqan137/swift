import UIKit
import CoreHaptics

/// Singleton that owns pre-warmed haptic generators so every tap doesn't
/// allocate a new one.  Respects the user's "hapticFeedback" preference.
///
/// `@MainActor` because every call site lives in a SwiftUI view / VM and the
/// mutable state (`engineNeedsRebuild`, `searchPlayer`, `isSearchPulsing`,
/// `lastScrubTick`) was previously read/written from multiple threads with no
/// synchronization — strict-concurrency surfaces that as a data race.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    /// Documented intensity scale for `impact(_:intensity:)` calls.
    /// Most call sites should reach for the semantic wrappers below
    /// (`buttonTap`, `primaryCommit`, etc.) instead of passing raw
    /// intensities — keep this scale in sync if those wrappers change.
    enum Intensity {
        /// Background / filter taps. Reads as a quiet acknowledgement.
        static let subtle: CGFloat = 0.4
        /// The default tap intensity. Use when no other tier fits.
        static let standard: CGFloat = 0.6
        /// Primary-action commits. Reserved for moments that should
        /// feel definitive — submit, confirm, complete.
        static let strong: CGFloat = 0.85
    }

    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact   = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact  = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private var hapticEngine: CHHapticEngine?
    /// True after a `stoppedHandler` fires (audio interruption, low-power
    /// mode, app backgrounded). The next play call rebuilds the engine
    /// instead of trying to use the dead one — that was the "haptics get
    /// stuck and never come back" bug.
    private var engineNeedsRebuild = true
    private var searchPlayer: CHHapticAdvancedPatternPlayer?
    private var isSearchPulsing = false
    /// Last time `chartScrubTick()` fired — used to throttle the chart
    /// drag gesture so a fast scrub doesn't queue ticks faster than the
    /// haptic hardware can render them as distinct pulses.
    private var lastScrubTick: CFTimeInterval = 0
    /// Lazily-built `quickAccessCommit` pattern. Patterns are immutable
    /// and survive engine rebuilds, so caching the pattern (not the
    /// player) skips the per-fire allocation without leaking state
    /// across audio-session interruptions. Players are still rebuilt
    /// each call — cheap relative to pattern construction.
    private var commitPattern: CHHapticPattern?
    /// Last time the unified commit haptic fired. Coalesces rapid taps
    /// so a button mash never queues a backlog of overlapping CoreHaptics
    /// events (which used to trip the engine's pattern-queue limit and
    /// silently kill haptics until the next foreground).
    private var lastCommitFire: CFTimeInterval = 0
    /// Minimum gap between two commit fires. ~40ms matches the two-beat
    /// pattern's natural envelope — anything tighter just stacks the
    /// second commit on top of the first beat of the previous tap.
    private static let commitMinInterval: CFTimeInterval = 0.040
    /// Last time `selection()` fired. Chart scrubs and drag gestures
    /// fan this out dozens of times per second; if every call hits
    /// the `UISelectionFeedbackGenerator` SwiftUI starts queueing
    /// haptic frames behind the main thread and the app visibly
    /// hitches (and on busy devices the CoreHaptics queue can outright
    /// crash the engine). 30ms cap = max ~33 Hz, still well above the
    /// "every tick feels distinct" threshold.
    private var lastSelectionFire: CFTimeInterval = 0
    private static let selectionMinInterval: CFTimeInterval = 0.030

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hapticFeedback")
    }

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        // Was missing — the first `selection()` call would arrive with
        // a cold generator and silently no-op on some devices. Every
        // chip / range pill / nav tap routes through `selection()`, so
        // a single missed first-fire reads to the user as "haptics
        // don't work."
        selectionGen.prepare()
        notification.prepare()
        _ = ensureEngine()

        // Rebuild the engine when the audio session comes back from an
        // interruption — CHHapticEngine and AVAudioSession share the same
        // underlying media services and tend to stop together.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionReactivated),
            name: AudioSessionManager.didReactivate,
            object: nil
        )
    }

    // MARK: - CoreHaptics Engine

    /// Returns a started engine, rebuilding it if it died. Call this
    /// instead of touching `hapticEngine` directly. Cheap when the engine
    /// is already up — `start()` is a no-op on a running engine.
    @discardableResult
    private func ensureEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }

        // MainActor isolation now serializes all state access — the old
        // `engineQueue.sync` was redundant once the class went @MainActor
        // and would block the main thread waiting on itself.
        if !engineNeedsRebuild, let engine = hapticEngine {
            do {
                try engine.start()
                return engine
            } catch {
                print("[Haptics] engine.start() failed, rebuilding: \(error.localizedDescription)")
                engineNeedsRebuild = true
                hapticEngine = nil
            }
        }

        do {
            let engine = try CHHapticEngine()
            // resetHandler / stoppedHandler fire on CoreHaptics' internal
            // dispatch queue; bridge back to MainActor before touching any
            // of our isolated state.
            engine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try self.hapticEngine?.start()
                    } catch {
                        self.engineNeedsRebuild = true
                        print("[Haptics] resetHandler restart failed: \(error.localizedDescription)")
                    }
                }
            }
            engine.stoppedHandler = { [weak self] reason in
                print("[Haptics] engine stopped: \(reason.rawValue)")
                Task { @MainActor [weak self] in
                    self?.engineNeedsRebuild = true
                }
            }
            try engine.start()
            hapticEngine = engine
            engineNeedsRebuild = false
            return engine
        } catch {
            print("[Haptics] engine init failed: \(error.localizedDescription)")
            hapticEngine = nil
            engineNeedsRebuild = true
            return nil
        }
    }

    // NotificationCenter delivers on the posting thread; bridge to
    // MainActor before touching @MainActor-isolated state.
    @objc private nonisolated func handleAudioSessionReactivated() {
        Task { @MainActor [weak self] in
            self?.engineNeedsRebuild = true
        }
    }

    // MARK: - Search Haptics (Cal.ai-style)

    /// Crisp initial "thunk" when the user sends a message. Routed
    /// through the unified commit pattern so the chat send feels
    /// continuous with every other primary tap in the app.
    func searchSendImpact() { quickAccessCommit() }

    /// Rhythmic pulsing pattern that loops while AI is thinking/searching.
    /// Subtle ticking heartbeat — soft transient taps that build and fade.
    func startSearchPulse() {
        guard isEnabled, let engine = ensureEngine() else { return }
        guard !isSearchPulsing else { return }
        isSearchPulsing = true

        do {
            // Build a ~1.2s looping pattern: two-beat pulse like a heartbeat
            // Beat 1: stronger tap
            let beat1Intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45)
            let beat1Sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            let beat1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [beat1Intensity, beat1Sharpness],
                relativeTime: 0
            )

            // Beat 2: softer echo tap
            let beat2Intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25)
            let beat2Sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            let beat2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [beat2Intensity, beat2Sharpness],
                relativeTime: 0.18
            )

            // Subtle continuous hum between beats
            let humIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.08)
            let humSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            let hum = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [humIntensity, humSharpness],
                relativeTime: 0.3,
                duration: 0.5
            )

            // Third gentle tick before loop restarts
            let tick3Intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15)
            let tick3Sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
            let tick3 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [tick3Intensity, tick3Sharpness],
                relativeTime: 0.95
            )

            let pattern = try CHHapticPattern(events: [beat1, beat2, hum, tick3], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            self.searchPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptics] Search pulse failed: \(error)")
        }
    }

    /// Stop the rhythmic pulse and play a satisfying completion haptic
    func stopSearchPulse(success: Bool = true) {
        guard isEnabled else { return }
        isSearchPulsing = false

        // Stop the looping player
        try? searchPlayer?.stop(atTime: CHHapticTimeImmediate)
        searchPlayer = nil

        // Completion haptic — sharp double-tap for success, single muted for error
        if let engine = ensureEngine() {
            do {
                var events: [CHHapticEvent] = []
                if success {
                    // Crisp double-tap completion (like Cal.ai's "done" feel)
                    let tap1I = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
                    let tap1S = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    events.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [tap1I, tap1S],
                        relativeTime: 0
                    ))

                    let tap2I = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                    let tap2S = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    events.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [tap2I, tap2S],
                        relativeTime: 0.1
                    ))
                } else {
                    let tapI = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
                    let tapS = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    events.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [tapI, tapS],
                        relativeTime: 0
                    ))
                }

                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {
                if success {
                    notification.notificationOccurred(.success)
                } else {
                    notification.notificationOccurred(.error)
                }
                notification.prepare()
            }
        } else {
            if success {
                notification.notificationOccurred(.success)
                notification.prepare()
            }
        }
    }

    // MARK: - Compression Complete Haptic

    /// Satisfying "squeeze-and-release" haptic for when compression
    /// finishes. Now collapses to the unified commit pattern — the user
    /// asked for one consistent feel across every action surface, and
    /// the bespoke 4-phase pop/glow/tick was the loudest holdout.
    func compressionComplete() { quickAccessCommit() }

    // MARK: - Tap Sensation (Cal AI-style)
    //
    // The signature "addictive" button feel — same sensation for every
    // primary tap target (the + FAB, the nav tabs, anywhere we want that
    // crisp Cal AI-style touch). Built on CoreHaptics so it has a real
    // attack curve, not the muted UIImpact thump.
    //
    // Anatomy of the sensation:
    //   1. CLICK   (t=0, intensity 0.95, sharpness 1.0)
    //        A bright, very sharp transient — the "thock" front-edge.
    //        Sharpness pushed to the top of the range so it reads as
    //        precise rather than soft.
    //   2. RESONANT ECHO (t=0.018, intensity 0.55, sharpness 0.62)
    //        A close-coupled secondary transient that follows the click
    //        by ~18ms. This is the part the user feels as "weight" —
    //        without it the click reads thin / plasticky. Pitched lower
    //        and softer so it functions like the release of the click,
    //        not a second click.
    //
    // Now an alias for the unified commit pattern — every primary tap
    // target shares one feel.
    func tapSensation() { quickAccessCommit() }

    // MARK: - Quick Cleanup: Delete
    //
    // Three-event "decisive removal" pattern. Fires from
    // GuidedCleanupViewModel.swipeLeft when the user marks a card for
    // deletion (red ✗ button OR leftward swipe past threshold).
    //
    // Design — heavy and final, deliberately distinct from
    // `cleanupKeep()` (single bright tick). User should feel which
    // button they pressed without looking.
    //
    //   1. PUNCH      (t=0,        intensity 0.95, sharpness 0.85)
    //        Sharp decisive click — the commit.
    //   2. THUD       (t=0.030s,   intensity 0.70, sharpness 0.18)
    //        Low resonant landing — gives the haptic body / weight.
    //   3. AFTERGLOW  (t=0.040s,   intensity 0.22 → 0, sharpness 0.10,
    //                  duration 0.100s)
    //        Continuous warm fade — completes the "drop into trash"
    //        sensation. Without this the haptic ends abruptly and
    //        loses the "weight" half of the signature.
    //
    // Collapsed onto the unified commit pattern. The visual swipe + the
    // card flying off-screen carry the "delete vs keep" distinction;
    // the haptic stays consistent across every action surface.
    func cleanupDelete() { quickAccessCommit() }

    // MARK: - Quick Cleanup: Keep
    //
    // Two-event "yes, save it" pattern. Fires from
    // GuidedCleanupViewModel.swipeRight when the user keeps a card
    // (green ✓ button OR rightward swipe past threshold).
    //
    // Design — light and optimistic, deliberately distinct from
    // `cleanupDelete()` (heavy two-beat + afterglow). Reads like an
    // Apple Watch checkmark confirmation: a bright, instant "yes."
    //
    //   1. AFFIRM  (t=0,       intensity 0.60, sharpness 0.95)
    //        Crisp bright tick — the commit.
    //   2. ECHO    (t=0.025s,  intensity 0.30, sharpness 0.85)
    //        Faint micro-lift so the haptic doesn't feel flat. Half
    //        the intensity of affirm so it reads as a tail, not a
    //        second tap.
    //
    // Collapsed onto the unified commit pattern — same rationale as
    // cleanupDelete above.
    func cleanupKeep() { quickAccessCommit() }

    // MARK: - Chart Range Flip
    //
    // Two-beat click → land pattern for the Progress chart range
    // pill swap (1D / 7D / 30D / 1Y). Reads as the pill *launching*
    // on tap and *landing* in its new slot ~100ms later — matches
    // the matchedGeometry spring's response so the haptic and the
    // visual settle together. Distinct from `tapSensation()` (click
    // + echo, 18ms gap, full-intensity) — the range flip is softer
    // and has more lag, so it feels like "scoping a range" not
    // "committing an action".
    //
    // Range-pill swap routes through the unified commit pattern now —
    // throttled at the manager level so a fast 1D/7D/30D/1Y mash never
    // queues overlapping pill haptics.
    func chartRangeFlip() { quickAccessCommit() }

    // MARK: - Number Roll
    //
    // Quiet continuous hum that pairs with a digit-roll animation —
    // the Robinhood "numbers spinning up" feel under the Progress
    // tab's hero bytes counter when it animates from 0 to the period
    // total. Low intensity + medium sharpness so it reads as a
    // sustained tactile cause behind the moving digits, not a
    // discrete tap.
    //
    // Default 0.4s matches the high-amplitude portion of the 0.85s
    // ease-out spring on `heroBytesAnimated` — the haptic decays
    // while the digits are still moving, so it feels like the
    // "engine" of the animation rather than its punctuation.
    //
    // Silent fallback on devices without CoreHaptics: the digits
    // still tumble visually; missing the hum is a polish gap, not a
    // signal loss.
    func numberRoll(duration: TimeInterval = 0.4) {
        guard isEnabled else { return }
        guard let engine = ensureEngine() else { return }

        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.18)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptics] numberRoll failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Nav Tab Tap
    //
    // Crisp single transient for bottom-nav tab switches. Brighter than
    // `selection()` so the tab change reads as a deliberate "switched"
    // event, lighter than `tapSensation()` so dragging across all three
    // tabs doesn't fatigue the hand. Calibrated so a quick four-tab
    // sweep still feels musical, not buzzy.
    func navTabTap() { quickAccessCommit() }

    // MARK: - Quick Access Commit
    //
    // Two-beat "press → go" sensation for the 4 Quick Access tiles
    // (Photos / Videos / Emails / Compress). Reads as one event with
    // commitment, not a flat thump.
    //
    //   1. PRESS  (t=0,     intensity 0.40, sharpness 0.45)
    //        Soft initial touch — the finger landing.
    //   2. COMMIT (t=0.028, intensity 0.85, sharpness 0.78)
    //        Snappier follow-through — "go." Sharpness pitched high so
    //        the second beat reads as a confirmation, not an echo.
    //
    // The 28ms gap is what separates this from `tapSensation()`'s 18ms
    // echo: long enough to read as two distinct events glued into one
    // motion, short enough to feel like a single decisive tap.
    func quickAccessCommit() {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        if now - lastCommitFire < Self.commitMinInterval { return }
        lastCommitFire = now

        if let engine = ensureEngine(), let pattern = makeCommitPattern() {
            do {
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                // Engine probably died between `ensureEngine()` and
                // `makePlayer()`. Flag it for rebuild and let the UIKit
                // fallback carry this tap so the user still feels it.
                engineNeedsRebuild = true
                print("[Haptics] quickAccessCommit failed: \(error.localizedDescription)")
            }
        }
        mediumImpact.impactOccurred(intensity: 0.75)
        mediumImpact.prepare()
    }

    /// Build (or return the cached) two-beat press→commit pattern.
    /// Pattern construction is the expensive part of CoreHaptics —
    /// caching it makes every subsequent commit fire a single
    /// `makePlayer(with:)` + `start(atTime:)` round trip.
    private func makeCommitPattern() -> CHHapticPattern? {
        if let p = commitPattern { return p }
        do {
            let press = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.40),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
                ],
                relativeTime: 0
            )
            let commit = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.78)
                ],
                relativeTime: 0.028
            )
            let pattern = try CHHapticPattern(events: [press, commit], parameters: [])
            commitPattern = pattern
            return pattern
        } catch {
            print("[Haptics] commit pattern build failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Streak Reveal
    //
    // Signature celebratory haptic for opening the streak badge. Three
    // rapidly-rising transients build to a peak across ~110ms — reads
    // as a quick sparkle / firework crackle, the "we're showing you
    // something special" cue.
    //
    //   1. SPARK 1 (t=0.000, intensity 0.35, sharpness 0.55)
    //   2. SPARK 2 (t=0.045, intensity 0.55, sharpness 0.72)
    //   3. SPARK 3 (t=0.105, intensity 0.92, sharpness 0.92)
    //
    // The widening gap between beats (45ms → 60ms) is what makes it
    // feel like an ascent rather than a stutter: each tap lands slightly
    // later than the previous, the way a real spark crackles. Peak
    // sharpness 0.92 at the third tap gives the "pop" finish.
    func streakReveal() { quickAccessCommit() }

    // MARK: - Impact

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        guard isEnabled else { return }
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light:  generator = lightImpact
        case .medium: generator = mediumImpact
        case .heavy:  generator = heavyImpact
        case .soft:   generator = softImpact
        case .rigid:  generator = rigidImpact
        @unknown default: generator = mediumImpact
        }
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    // MARK: - Selection
    //
    // Light tick used for nav-bar tab taps and the Ask Bee FAB. Same
    // sensation iOS uses on segmented controls and picker rotors — a
    // subtle "you selected something" cue, intentionally lighter than
    // any of the impact styles.
    func selection() {
        guard isEnabled else { return }
        // Throttle: a SwiftUI drag gesture on a chart can fire
        // `onChange` 60+ times per second, and each call into the
        // selection generator costs a main-thread hop into UIKit. Cap
        // the fire rate to 30ms so a fast scrub stays buttery and the
        // CoreHaptics queue can't overflow.
        let now = CACurrentMediaTime()
        guard now - lastSelectionFire >= Self.selectionMinInterval else { return }
        lastSelectionFire = now
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    // MARK: - Notification

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }

    // MARK: - Semantic Wrappers
    //
    // Thin wrappers over `impact` / `selection` / `notify` so call sites
    // read as intent ("primaryCommit") instead of UIKit configuration
    // ("impact(.medium, intensity: 0.85)"). New call sites should reach
    // for these first; reserve the raw API for one-off cases that don't
    // fit a semantic name. Premium CoreHaptics methods (`tapSensation`,
    // `quickAccessCommit`, `streakReveal`, `compressionComplete`, the
    // search trio) are already semantic and stay as-is.

    // All semantic action wrappers now route through `quickAccessCommit`
    // so every named tap surface in the app feels identical. The named
    // entry points stay so call sites still read as intent, but no two
    // produce a different physical sensation. Only `actionError` keeps a
    // distinct treatment — a genuine error needs a notification-style
    // alert the user can identify by feel; pairing it to the regular
    // commit beat would erase the only "something went wrong" cue.
    func buttonTap()          { quickAccessCommit() }
    func primaryCommit()      { quickAccessCommit() }
    func filterChange()       { quickAccessCommit() }
    func toggleChange()       { quickAccessCommit() }
    func destructiveConfirm() { quickAccessCommit() }
    func actionSuccess()      { quickAccessCommit() }
    func undoAction()         { quickAccessCommit() }

    func actionError() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    // MARK: - Arrow Nudge
    //
    // Click-through navigation arrows — paginators (StreakDetailView's
    // prev/next month chevrons) and the back-chevrons that head every
    // detail screen. Deliberately a NEW sensation in the file's haptic
    // vocabulary, not a re-skin of `selection()` / `navTabTap()` /
    // `tapSensation()`, so the user can feel "I'm arrowing through
    // something" vs "I'm tapping a primary button".
    //
    // Direction carries through as a subtle sharpness delta (0.78 vs
    // 0.58 at matched intensity 0.42). Same family — both are short
    // single transients — but `.forward` reads as bright / stepping in
    // and `.backward` as dull / stepping back. Mashing through months
    // or popping back through a deep nav stack now feels distinct from
    // every other tap in the app.
    //
    // No-CoreHaptics fallback (older devices, simulator) drops to
    // `selectionGen.selectionChanged()` for both directions — UIKit's
    // selection generator can't vary sharpness per fire, so we sacrifice
    // the directional flavor rather than degrade to two unrelated UIKit
    // styles.
    enum ArrowDirection {
        case forward
        case backward
    }

    func arrowNudge(_ direction: ArrowDirection) {
        // Unified back-arrow / chevron haptic. Every back-arrow site in
        // the app routes through this method, and the user asked for the
        // same two-beat "press → go" sensation the Quick Access tiles use
        // so navigation chevrons feel continuous with the rest of the
        // app's primary entry-points. Direction is kept as a parameter
        // for call-site compatibility but no longer drives a sharpness
        // delta — both feel identical now.
        _ = direction
        quickAccessCommit()
    }

    // MARK: - AskBee Conversation Rhythm
    //
    // Three sensations that fill out the AskBee chat surface so the
    // whole interaction feels physically continuous: tap the input,
    // type the first character, get the reply. None of them are
    // attention-grabbing — they're tactile decoration that makes the
    // chat feel responsive without ever buzzing in the user's hand.
    //
    // Together with the existing `searchSendImpact()` (send) and
    // `startSearchPulse()` / `stopSearchPulse()` (thinking), the full
    // loop reads as:
    //
    //   inputFieldFocus → typingFirstKey → searchSendImpact →
    //   (pulsing while AI thinks) → stopSearchPulse → replyLanded.
    //
    // Six beats per exchange; only one (`replyLanded`) is the headline.

    /// Whisper-light single transient — the tactile equivalent of the
    /// chat field saying "I'm listening" when the keyboard opens.
    /// Lighter than `buttonTap()` so it doesn't feel like an action,
    /// just a presence cue.
    func inputFieldFocus() { quickAccessCommit() }

    /// Fired ONCE per message cycle when the user types the first
    /// character of a fresh message (empty → has-content transition).
    /// NOT per-keystroke — call sites must guard with a flag that
    /// resets on send. Reuses the system selection tick (universal
    /// "you just changed something" cue) but routes through this
    /// semantic alias so chat call sites read as intent.
    func typingFirstKey() { quickAccessCommit() }

    /// Warm soft landing for when the AI's reply bubble appears. This
    /// is the headline of the AskBee haptic rhythm — distinct from
    /// `tapSensation()` (action you took) because it's lower-sharpness
    /// and slightly softer, reading as something **arriving** rather
    /// than something you **did**.
    ///
    /// Anatomy: one rounded transient at intensity 0.38 / sharpness
    /// 0.38. Same energy as `quickAccessCommit`'s opening press but
    /// without the follow-through commit beat — one beat, not two.
    func replyLanded() { quickAccessCommit() }

    // MARK: - Chart scrub (Robinhood-style trading-terminal feel)

    /// Variable-intensity selection tick fired per bar as the user drags
    /// across the Progress chart. `normalizedValue` is the bucket's value
    /// relative to the chart max (0...1) — a peak bar fires a punchy
    /// tick, a low bar a quiet one, so the user can *feel* the shape of
    /// the chart through their finger like a Robinhood portfolio scrub.
    ///
    /// `normalizedValue == 0` is silent: empty buckets shouldn't tick at
    /// all (otherwise scrubbing across a zero-stretch reads as a
    /// uniform buzz that ignores the data).
    ///
    /// Throttled to ~30Hz so a fast scrub doesn't fire ticks faster than
    /// the hardware can distinguish — without the throttle, rapid drags
    /// read as a single continuous buzz instead of discrete per-point
    /// clicks. Pairs with `chartScrubCommit()` on release.
    func chartScrubTick(normalizedValue: Double = 1.0) {
        guard isEnabled else { return }
        // Empty buckets are silent. The visible node motion already
        // tells the user where there's no data; firing a tick on a
        // zero bucket would read as noise.
        guard normalizedValue > 0 else { return }

        // Throttle to ~30Hz — even a single thin selection tick fired
        // 60–120× per second during a fast drag stacks faster than the
        // hardware can play them as distinct events. Without this, a
        // scrub turned into a constant buzz.
        let now = CACurrentMediaTime()
        if now - lastScrubTick < 0.033 { return }
        lastScrubTick = now

        // Per-bucket finger feedback intentionally stays a single
        // selection tick rather than promoting to the full commit
        // pattern — a commit pattern fired per bucket during a drag
        // would feel like a jackhammer and flood the haptic engine
        // even with the throttle above. The unified commit fires on
        // gesture release via `chartScrubCommit()`.
        selectionGen.selectionChanged()
        selectionGen.prepare()
    }

    /// Tactile "wall" when the user drags past the first/last bucket.
    /// Distinct from the per-tick scrub feedback so the user feels the
    /// chart's edge instead of just running out of ticks silently. Same
    /// 30Hz throttle as the tick — at the edge the gesture stops moving
    /// the selection, so each call site should debounce its own
    /// edge-touch state to avoid a continuous buzz.
    func chartScrubEdgeBump() {
        // Edge bump is a discrete "you hit the wall" event — route it
        // through the unified commit pattern. The internal throttle on
        // `quickAccessCommit` handles the case where a finger held past
        // the edge would otherwise fire repeated bumps.
        quickAccessCommit()
    }

    /// Single, heavier lock-in fired on chart drag release. Only call
    /// when the user actually scrubbed during the gesture (the caller
    /// tracks this); a tap-and-release with no movement should not fire
    /// commit — the per-point tick already handled it.
    func chartScrubCommit() { quickAccessCommit() }

    /// Pre-warm everything `chartScrubTick`/`chartScrubCommit` need so
    /// the very first tick after the chart appears (or after the app
    /// returns from background) doesn't silently no-op.
    func prepareScrub() {
        guard isEnabled else { return }
        selectionGen.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        _ = ensureEngine()
    }

    // MARK: - Prepare

    func prepare(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:  lightImpact.prepare()
        case .medium: mediumImpact.prepare()
        case .heavy:  heavyImpact.prepare()
        case .soft:   softImpact.prepare()
        case .rigid:  rigidImpact.prepare()
        @unknown default: break
        }
    }
}
