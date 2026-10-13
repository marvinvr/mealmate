import Foundation
import StoreKit

/// Owns all StoreKit 2 state for the supporter tier (created once in `MealMateApp`).
///
/// - Lifetime status (`status`: supporter, since when, tip count) comes from `Transaction.all`
///   and is monotonic (`SupporterStatus.merging`). Finished consumables only show up there
///   because `SKIncludeConsumableInAppPurchaseHistory` is true in Info.plist; reinstall and
///   second-device recognition of tippers depend on it.
/// - Whether a subscription is active (`isSubscribed`) comes from `Transaction.currentEntitlements`.
///   It gates the subscription icons and can go away again (lapse, refund). Retired `souschef.*`
///   subscriptions count too.
/// - Every verified transaction is finished (listener + launch sweep); an unfinished consumable
///   would block buying the same tip again.
/// - `AppStore.sync()` can ask for the Apple Account password: only `restorePurchases()` calls
///   it, from an explicit tap.
@MainActor
@Observable
final class SupporterStore {
    private enum Keys {
        static let status = "supporter.status"
        static let isSubscribed = "supporter.isSubscribed"
        /// Cache of the two-level setup (0 none, 1 Sous Chef, 2 Head Chef), read once as a fallback.
        static let legacyActiveTier = "supporter.activeTier"
    }

    /// The subscription's billing periods, monthly before yearly. Empty until loaded.
    private(set) var subscriptionProducts: [Product] = []
    /// Tips in ascending price order. Empty until loaded.
    private(set) var tipProducts: [Product] = []
    /// Product loading finished and returned nothing usable.
    private(set) var productsUnavailable = false

    private(set) var status: SupporterStatus
    /// Last known subscription state; cached so the UI is right before the first refresh.
    private(set) var isSubscribed: Bool
    /// The active subscription, if any (also a retired one).
    private(set) var activeSubscription: SupporterProduct?
    /// True once `currentEntitlements` was read this launch: only then is `isSubscribed` fresh
    /// enough to take a subscription icon away.
    private(set) var hasResolvedEntitlements = false

    /// Product ID of an in-flight purchase, for the row spinner.
    private(set) var purchasingProductID: String?
    private(set) var isRestoring = false
    /// Increments after every completed purchase so views can say thanks.
    private(set) var completedPurchaseCount = 0
    private(set) var lastErrorMessage: String?

    var isSupporter: Bool { status.isSupporter }
    /// The five food icons: a subscription or a tip from Brunch up, ever (not the Espresso tip).
    var hasFoodIcons: Bool { status.hasFoodIcons || isSubscribed }
    var hasProducts: Bool { !(subscriptionProducts.isEmpty && tipProducts.isEmpty) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        status = defaults.data(forKey: Keys.status)
            .flatMap { try? JSONDecoder().decode(SupporterStatus.self, from: $0) } ?? SupporterStatus()
        isSubscribed = defaults.object(forKey: Keys.isSubscribed) != nil
            ? defaults.bool(forKey: Keys.isSubscribed)
            : defaults.integer(forKey: Keys.legacyActiveTier) > 0
        #if DEBUG
        // `-supporter.debugBusy <productID|restore>`: show that purchase (or Restore Purchases) as
        // in flight, for screenshots of the busy buttons (SupporterScreenshotTests).
        if let busy = defaults.string(forKey: "supporter.debugBusy") {
            if busy == "restore" { isRestoring = true } else { purchasingProductID = busy }
        }
        #endif
    }

    /// Starts the transaction listener, finishes leftovers, reconciles entitlements and loads
    /// products. Safe to call more than once; only the first call does anything.
    func start() async {
        guard !started else { return }
        started = true
        startTransactionListener()
        await finishUnfinishedTransactions()
        await refreshEntitlements()
        await loadProducts()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: SupporterProduct.offeredIDs)
                .sorted { order(of: $0) < order(of: $1) }
            subscriptionProducts = products.filter { SupporterProduct(rawValue: $0.id)?.isSubscription == true }
            tipProducts = products.filter { SupporterProduct(rawValue: $0.id)?.isSubscription == false }
            productsUnavailable = products.isEmpty
        } catch {
            productsUnavailable = !hasProducts
        }
    }

    private func order(of product: Product) -> Int {
        SupporterProduct(rawValue: product.id)?.sortOrder ?? .max
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        lastErrorMessage = nil
        defer { purchasingProductID = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                completedPurchaseCount += 1
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = "The purchase couldn’t be completed. You weren’t charged unless the App Store says otherwise."
        }
    }

    /// Restore Purchases. Can prompt for the Apple Account password: explicit user action only.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    /// Recomputes the active subscription and folds the purchase history into the cached status.
    func refreshEntitlements() async {
        var entitlements: [SupporterEntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            entitlements.append(SupporterEntitlementRecord(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate,
                isRevoked: transaction.revocationDate != nil,
                isUpgraded: transaction.isUpgraded))
        }

        var history: [SupporterPurchaseRecord] = []
        for await result in Transaction.all {
            guard let transaction = try? verified(result) else { continue }
            history.append(SupporterPurchaseRecord(
                productID: transaction.productID,
                purchaseDate: transaction.originalPurchaseDate,
                quantity: transaction.purchasedQuantity,
                isRevoked: transaction.revocationDate != nil))
        }

        activeSubscription = SupporterStatus.activeSubscription(entitlements: entitlements)
        isSubscribed = activeSubscription != nil
        status = status.merging(history: history, isSubscribed: isSubscribed)
        hasResolvedEntitlements = true
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: Keys.status)
        }
        defaults.set(isSubscribed, forKey: Keys.isSubscribed)
        defaults.removeObject(forKey: Keys.legacyActiveTier)
    }

    // MARK: - Transaction plumbing

    private func startTransactionListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    /// Finishes whatever a previous run left behind (e.g. a crash mid-purchase).
    private func finishUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw StoreKitError.notEntitled
        }
    }
}
