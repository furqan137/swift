import Foundation
import RevenueCat

// MARK: - SubscriptionService
//
// Single source of truth for subscriptions, powered by RevenueCat.
// Replaces `StoreManager` with RevenueCat's Purchases SDK as the
// backend for entitlements, purchases, and identity management.
//
// USAGE:
//   - Read entitlement: `SubscriptionService.shared.isPro`
//   - Trigger a purchase: `await SubscriptionService.shared.purchase(package:)`
//   - Restore: `await SubscriptionService.shared.restorePurchases()`
//   - Offerings: `SubscriptionService.shared.currentOffering`

@MainActor
final class SubscriptionService: NSObject, ObservableObject {

    static let shared = SubscriptionService()

    // MARK: - Published state

    @Published private(set) var isPro: Bool = false
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

    /// Cache of the last-known entitlement state, persisted to disk so
    /// cold launches show "Pro" immediately instead of flashing "Free"
    /// while RevenueCat fetches `customerInfo`. RevenueCat's first
    /// callback then reconciles with the source of truth.
    private static let cachedIsProKey = "subscription.isPro.cached.v1"

    enum PurchaseOutcome {
        case success
        case cancelled
        case pending
    }

    // MARK: - Configuration

    private static let apiKey: String = {
        #if DEBUG
        return "test_tpXzkMcJmAQPmnIrImjxMhEkuFX"   // RevenueCat Test Store — Debug only, never ship
        #else
        return "appl_JfYdUZTyXVKBQZJYhilLXRmyCsa"   // App Store production key
        #endif
    }()
    private static let entitlementID = "BeeClean Pro"

    // MARK: - Init

    private override init() {
        super.init()
        // Seed from the cached entitlement so the very first view that
        // reads `isPro` (e.g. paywall gating on the home screen) sees
        // the last-known value instead of `false`. Reconciled with
        // RevenueCat the moment `refreshEntitlement()` returns.
        self.isPro = UserDefaults.standard.bool(forKey: Self.cachedIsProKey)
    }

    /// Call once from `BeeCleanApp.init()` after AdMob setup.
    func configure() {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: Self.apiKey)
        Purchases.shared.delegate = self

        Task {
            await refreshEntitlement()
            await loadOfferings()
        }
    }

    // MARK: - Identity

    /// In-flight identity mutation. A rapid sign-out → sign-in pair
    /// used to fire two unawaited Tasks; the slower one's completion
    /// could land *after* the faster one and clobber `customerInfo`
    /// with the wrong identity, leaving `isPro` flapping. Now each new
    /// call cancels the previous one so only the latest sequence wins.
    private var identityTask: Task<Void, Never>?

    /// Link the RevenueCat anonymous user to your backend user ID.
    /// Call after sign-in or when a stored user is detected at launch.
    func setUserIdentity(_ appUserID: String) {
        identityTask?.cancel()
        identityTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (customerInfo, _) = try await Purchases.shared.logIn(appUserID)
                if Task.isCancelled { return }
                self.updateEntitlement(from: customerInfo)
                await self.loadOfferings()
            } catch {
                print("[SubscriptionService] logIn failed: \(error.localizedDescription)")
            }
        }
    }

    /// Reset to anonymous user. Call on sign-out.
    func resetIdentity() {
        identityTask?.cancel()
        identityTask = Task { [weak self] in
            guard let self else { return }
            do {
                let customerInfo = try await Purchases.shared.logOut()
                if Task.isCancelled { return }
                self.updateEntitlement(from: customerInfo)
            } catch {
                print("[SubscriptionService] logOut failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(package: Package) async -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)

            if userCancelled {
                return .cancelled
            }

            updateEntitlement(from: customerInfo)
            return isPro ? .success : .pending
        } catch {
            lastError = error.localizedDescription
            print("[SubscriptionService] Purchase failed: \(error.localizedDescription)")
            return .cancelled
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateEntitlement(from: customerInfo)
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Offerings

    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            print("[SubscriptionService] Failed to load offerings: \(error.localizedDescription)")
        }
    }

    // MARK: - Entitlement

    private func refreshEntitlement() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateEntitlement(from: customerInfo)
        } catch {
            print("[SubscriptionService] Failed to refresh entitlement: \(error.localizedDescription)")
        }
    }

    private func updateEntitlement(from customerInfo: CustomerInfo) {
        // Pro if the named entitlement is active, or — resilient fallback for a
        // single-entitlement project — if any entitlement is active. Guards
        // against a dashboard identifier that doesn't exactly match the literal.
        let active = customerInfo.entitlements[Self.entitlementID]?.isActive == true
            || !customerInfo.entitlements.active.isEmpty
        isPro = active
        // Persist for next cold start. Only writes when the value
        // actually changes — UserDefaults dedup is cheap but explicit
        // is cheaper.
        if UserDefaults.standard.bool(forKey: Self.cachedIsProKey) != active {
            UserDefaults.standard.set(active, forKey: Self.cachedIsProKey)
        }
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            updateEntitlement(from: customerInfo)
        }
    }
}
