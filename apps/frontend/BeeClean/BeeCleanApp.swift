import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleMobileAds
import BackgroundTasks
import UIKit
import ObjectiveC
import RevenueCat

@main
struct BeeCleanApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var themeService = ThemeService.shared
    @StateObject private var photoKit = PhotoKitService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var photosStore = SimilarPhotosStore()
    // Launch splash — shown for a brief moment on cold start so the scene
    // that follows (onboarding or home) gets a frame to lay itself out
    // instead of flashing in with a stutter.
    @State private var showingSplash = true

//    init() {
//        // Default user preferences. Registered before any feature reads
//        // them so a fresh install gets the intended behavior. Haptics
//        // were silently off for everyone until this landed because the
//        // gate reads `UserDefaults.standard.bool(forKey:)`, which is
//        // `false` for an unset key.
//        UserDefaults.standard.register(defaults: [
//            "hapticFeedback": true
//        ])
//
//        // Configure AVAudioSession before any sound player can be touched.
//        // Without this, AVAudioPlayer defaults to .soloAmbient and goes
//        // silent forever after the first interruption (call/Siri/music
//        // start) — the "sound stops working entirely" TestFlight bug.
//        AudioSessionManager.shared.configure()
//
//        // Force-enable the left-edge swipe-back gesture on every
//        // UINavigationController so pushed screens remain swipeable even
//        // when their nav bar is hidden (AppLayout, CollapsingHeaderLayout,
//        // etc.). Must run before the first window appears.
//        if !ProcessInfo.isRunningPreview {
//            SwipeBackEnabler.install()
//        }
//
//        // Register the background indexing task handler BEFORE the app
//        // finishes launching. iOS requires registration to happen synchronously
//        // at startup or the task will be rejected.
//        PhotoIndexingService.registerBackgroundTasks()
//
//        // Configure Google Sign-In with the client ID from Info.plist
//        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
//            let config = GIDConfiguration(clientID: clientID)
//            GIDSignIn.sharedInstance.configuration = config
//        }
//
//        // Initialize Google Mobile Ads SDK + register test device IDs
//        if !ProcessInfo.isRunningPreview {
//            GADMobileAds.sharedInstance().start(completionHandler: nil)
//        }
//        let testIDs = AdConfig.loadTestDeviceIDs()
//        if !testIDs.isEmpty {
//            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = testIDs
//            #if DEBUG
//            print("[AdMob] Registered \(testIDs.count) test device(s): \(testIDs)")
//            #endif
//        }
//
//        // Configure RevenueCat SDK
//        if !ProcessInfo.isRunningPreview {
//            SubscriptionService.shared.configure()
//        }
//
//        // Kill the UIKit navigation bar background & separator globally.
//        let appearance = UINavigationBarAppearance()
//        appearance.configureWithTransparentBackground()
//        appearance.backgroundColor = .clear
//        appearance.shadowColor = .clear
//        appearance.shadowImage = UIImage()
//        appearance.backgroundImage = UIImage()
//        appearance.backgroundEffect = nil
//
//        let navBar = UINavigationBar.appearance()
//        navBar.standardAppearance = appearance
//        navBar.scrollEdgeAppearance = appearance
//        navBar.compactAppearance = appearance
//        navBar.compactScrollEdgeAppearance = appearance
//        navBar.isTranslucent = true
//        navBar.setBackgroundImage(UIImage(), for: .default)
//        navBar.shadowImage = UIImage()
//    }
    
    init() {
        UserDefaults.standard.register(defaults: [
            "hapticFeedback": true,
            // First-launch theme = Light. The legacy "auto" schedule
            // was retired in favour of an explicit binary choice;
            // existing users persisted with "auto" continue to read
            // through `UserOverride.auto.colorScheme = .light`.
            ThemeService.userOverrideKey: ThemeService.UserOverride.light.rawValue
        ])

        guard !ProcessInfo.isRunningPreview else {
            return
        }
        
        AudioSessionManager.shared.configure()
        
        SwipeBackEnabler.install()
        
        PhotoIndexingService.registerBackgroundTasks()
        
        if let clientID = Bundle.main.object(
            forInfoDictionaryKey: "GIDClientID"
        ) as? String {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }
        
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        
        let testIDs = AdConfig.loadTestDeviceIDs()
        if !testIDs.isEmpty {
            GADMobileAds.sharedInstance()
                .requestConfiguration
                .testDeviceIdentifiers = testIDs
        }
        
        SubscriptionService.shared.configure()

        // Sweep any orphaned `compressed_*` files in temporaryDirectory
        // from prior force-killed compression sessions. The success /
        // cancel paths in CompressionEngine clean these up via `defer`,
        // but a force-kill bypasses that — over months these can quietly
        // pile up into GBs in /tmp. Runs detached so a slow filesystem
        // can't delay the first frame.
        CompressionEngine.sweepOrphanedTempFiles()

        // Kill the UIKit navigation bar background & separator globally.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        appearance.backgroundImage = UIImage()
        appearance.backgroundEffect = nil
        
        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.compactScrollEdgeAppearance = appearance
        navBar.isTranslucent = true
        navBar.setBackgroundImage(UIImage(), for: .default)
        navBar.shadowImage = UIImage()

        // Storage Runway wiring — touch the singletons at launch so
        // their NotificationCenter observers actually exist before the
        // first foreground transition fires. Without this, AppLifecycleManager
        // wouldn't init until AskAI opened, and StorageForecastManager
        // wouldn't init until HiveScoreCard mounted, so the very first
        // session could miss its snapshot. Also seeds the history with
        // one initial reading so the runway has a starting datapoint.
        _ = AppLifecycleManager.shared
        StorageForecastManager.shared.recordSnapshot()

        // DEBUG-only self-tests for the storage runway estimator.
        // Asserts via `precondition` so a regression trips the
        // debugger immediately during development.
        #if DEBUG
        StorageForecastEstimatorTests.runAll()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Onboarding flow temporarily removed pending a redesign.
                // The previous OnboardingView/OnboardingCarouselView stack
                // (painted Figma slides + native paywall) became too tangled
                // with the broader app and was driving repeated merge
                // conflicts; a new flow is being rebuilt from the Figma
                // ground-up. ContentView is shown unconditionally until the
                // new flow lands.
                ContentView()

                if showingSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    showingSplash = false
                }
            }
            // Window-level scheme — pinned to light. Dark mode was retired
            // app-wide. `ThemeService.mode` is still read for legacy call
            // sites but always resolves to `.light`.
            .preferredColorScheme(.light)
            .onOpenURL { url in
                // Handle Google Sign-In callback
                GIDSignIn.sharedInstance.handle(url)
            }
            .modelContainer(SimilarPersistence.container)
            .environment(photosStore)
            .task {
                guard !ProcessInfo.isRunningPreview else { return }

                themeService.start()

                IndexingService.shared.resumeFromCheckpoint()

                // Kick off the Apple-equivalent library walk EAGERLY at
                // launch so the dashboard's "Total Space to Clean"
                // headline has a real number ready by the time
                // ChargingView mounts — instead of waiting 5–10s after
                // the user lands on the home screen and watching the
                // figure inflate from "45.8 GB" to "50.67 GB".
                PhotoLibraryBytesService.shared.refreshIfStale(force: true)

                if let userID = authService.currentUser?.id {
                    SubscriptionService.shared.setUserIdentity(userID)
                }
            }
//            .task {
//                themeService.start()
//                // Resume any indexing work that was in progress when the app
//                // was last suspended or terminated by the system.
//                // CLIP indexing is 100% on-device — no backend auth needed.
//                // resumeFromCheckpoint() gates on photo permission internally.
//                IndexingService.shared.resumeFromCheckpoint()
//
//                // Sync RevenueCat identity if user is already authenticated
//                if let userID = authService.currentUser?.id {
//                    SubscriptionService.shared.setUserIdentity(userID)
//                }
//            }
            .onChange(of: authService.currentUser?.id) { _, newID in
                if let newID {
                    SubscriptionService.shared.setUserIdentity(newID)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard !ProcessInfo.isRunningPreview else { return }
                switch newPhase {
                case .active:
                    // Returning to foreground: refetch theme + resume any
                    // interrupted indexing checkpoint.
                    // Re-arm the audio session — backgrounding can leave it
                    // deactivated, which silently kills the next play().
                    AudioSessionManager.shared.ensureActive()
                    Task { await themeService.refresh() }
                    IndexingService.shared.resumeFromCheckpoint()
                    // Re-fetch the clean bar — applies daily decay and drives
                    // bee stage devolution for users returning after days away,
                    // so the devolve animation can fire on foreground.
                    Task { await ProgressManager.shared.loadProgress() }
                    // Roll the daily bucket if midnight crossed while we
                    // were backgrounded — otherwise a fresh cleanup
                    // backdates into yesterday's bar on the chart.
                    HiveStatsManager.shared.ensureDailyBucketFresh()
                    // Refresh hive stats cache asynchronously to avoid blocking scene update
                    Task { await HiveStatsManager.shared.refreshPendingItemCount() }
                    // Drain any activity logs that couldn't reach the
                    // backend while we were offline / backgrounded —
                    // otherwise the local streak runs ahead of the
                    // server forever.
                    Task { await StreakService.shared.flushPendingActivities() }
                case .background:
                    // Checkpoint immediately and schedule a BGProcessingTask
                    // so iOS can hand us more time later.
                    PhotoIndexingService.shared.handleAppBackgrounding()
                    // Make sure any in-flight Saved Finds disk writes
                    // actually land before iOS suspends us — a save tap
                    // right before backgrounding could otherwise lose
                    // its bytes if the detached persist task gets paused.
                    Task { await SavedFindsStore.shared.flushPendingWrites() }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onAppear {
                Task { await ProgressManager.shared.loadProgress() }
            }
        }
    }
}

// MARK: - Splash View
// Brief launch screen shown while the first real scene (onboarding or home)
// wires itself up. Displays the painted bee-face splash over a full-screen
// yellow background so the app never flashes white on cold start.
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.86, blue: 0.29)
                .ignoresSafeArea()

            // The splash asset is a tall yellow rectangle with rounded
            // corners and the face near the center. `scaledToFill` + a small
            // square frame with `.clipped()` crops away both the rounded
            // corners and the surrounding yellow padding, leaving only the
            // face visible on the full-screen yellow background.
            Image("OnboardingSplash")
                .resizable()
                .scaledToFill()
                .frame(width: 260, height: 260)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Swipe-Back Enabler
//
// Forces the iOS left-edge interactive pop gesture to stay active on every
// UINavigationController — including screens that hide their nav bar via
// `.toolbar(.hidden, for: .navigationBar)`, which normally kills the
// gesture. Installed once at app launch from `BeeCleanApp.init()` so every
// pushed screen stays swipeable whether or not it draws a back arrow.

final class SwipeBackEnabler: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackEnabler()

    static func install() {
        NavigationControllerSwipeSwizzler.swizzleOnce()
    }

    // Only allow the gesture when there's a view below to pop to — prevents
    // firing on root tab stacks where pop would do nothing.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = gestureRecognizer.view
        while let current = responder {
            if let nav = current as? UINavigationController {
                return nav.viewControllers.count > 1
            }
            responder = current.next
        }
        return false
    }
}

private enum NavigationControllerSwipeSwizzler {
    nonisolated(unsafe) static var didSwizzle = false

    static func swizzleOnce() {
        guard !didSwizzle else { return }
        didSwizzle = true

        let cls: AnyClass = UINavigationController.self
        let original = #selector(UINavigationController.viewDidLoad)
        let replacement = #selector(UINavigationController.beeclean_swipeBack_viewDidLoad)

        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let replacementMethod = class_getInstanceMethod(cls, replacement)
        else { return }

        // `viewDidLoad` is inherited from UIViewController — a blind
        // `method_exchangeImplementations` would swap the IMP at the base
        // class level, which makes every UIViewController subclass (e.g.
        // SwiftUI's UIHostingController) route `viewDidLoad` into our
        // trampoline and crash on the unrecognised selector. Add both
        // selectors to UINavigationController's own method table first so
        // the swap stays scoped to navigation controllers.
        let didAddMethod = class_addMethod(
            cls,
            original,
            method_getImplementation(replacementMethod),
            method_getTypeEncoding(replacementMethod)
        )

        if didAddMethod {
            class_replaceMethod(
                cls,
                replacement,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
}

private extension UINavigationController {
    // Swapped with the real `viewDidLoad` at launch — the recursive-looking
    // call hits the original implementation because the selectors have been
    // exchanged in the method table.
    @objc func beeclean_swipeBack_viewDidLoad() {
        self.beeclean_swipeBack_viewDidLoad()
        interactivePopGestureRecognizer?.delegate = SwipeBackEnabler.shared
        interactivePopGestureRecognizer?.isEnabled = true
    }
}

extension ProcessInfo {
    static var isRunningPreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        || processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}
