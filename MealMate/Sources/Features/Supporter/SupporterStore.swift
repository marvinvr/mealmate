import Foundation
import StoreKit

/// Owns all StoreKit 2 state for the supporter tier (created once in `MealMateApp`).
///
/// - Lifetime status (`status`: supporter, since when, tip count) comes from `Transaction.all`
///   and is monotonic (`SupporterStatus.merging`). Finished consumables only show up there
///   because `SKIncludeConsumableInAppPurchaseHistory` is true in Info.plist; reinstall and
///   second-device recognition of tippers depend on it.
/// - The active subscription level (`activeTier`) comes from `Transaction.currentEntitlements`.
///   It gates the Head Chef icons and can go down again (lapse, refund).
/// - Every verified transaction is finished (listener + launch sweep); an unfinished consumable
///   would block buying the same tip again.
/// - `AppStore.sync()` can ask for the Apple Account password: only `restorePurchases()` calls
///   it, from an explicit tap.
@MainActor
@Observable
final class SupporterStore {
    private enum Keys {
        static let status = "supporter.status"
        static let activeTier = "supporter.activeTier"
    }

    /// Subscription products by level, monthly before yearly. Empty until loaded.
    private(set) var sousChefProducts: [Product] = []
    private(set) var headChefProducts: [Product] = []
    /// Tips in ascending price order. Empty until loaded.
    private(set) var tipProducts: [Product] = []
    /// Product loading finished and returned nothing usable.
    private(set) var productsUnavailable = false

    private(set) var status: SupporterStatus
    /// Last known active subscription level; cached so the UI is right before the first refresh.
    private(set) var activeTier: SupporterTier
    /// Product ID of the active subscription, if any.
    private(set) var activeSubscriptionID: String?
    /// True once `currentEntitlements` was read this launch: only then is `activeTier` fresh
    /// enough to take a Head Chef icon away.
    private(set) var hasResolvedEntitlements = false

    /// Product ID of an in-flight purchase, for the row spinner.
    private(set) var purchasingProductID: String?
    private(set) var isRestoring = false
    /// Increments after every completed purchase so views can say thanks.
    private(set) var completedPurchaseCount = 0
    private(set) var lastErrorMessage: String?

    var isSupporter: Bool { status.isSupporter }
    var isHeadChef: Bool { activeTier == .headChef }
    var hasActiveSubscription: Bool { activeTier > .none }
    var hasProducts: Bool { !(sousChefProducts.isEmpty && headChefProducts.isEmpty && tipProducts.isEmpty) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        status = defaults.data(forKey: Keys.status)
            .flatMap { try? JSONDecoder().decode(SupporterStatus.self, from: $0) } ?? SupporterStatus()
        activeTier = SupporterTier(rawValue: defaults.integer(forKey: Keys.activeTier)) ?? .none
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
            let products = try await Product.products(for: SupporterProduct.allIDs)
                .sorted { order(of: $0) < order(of: $1) }
            sousChefProducts = products.filter { SupporterProduct(rawValue: $0.id)?.tier == .sousChef }
            headChefProducts = products.filter { SupporterProduct(rawValue: $0.id)?.tier == .headChef }
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

    /// Recomputes the active level and folds the purchase history into the cached status.
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

        let tier = SupporterStatus.activeTier(entitlements: entitlements)
        activeTier = tier
        activeSubscriptionID = entitlements
            .filter { !$0.isRevoked && !$0.isUpgraded && SupporterProduct(rawValue: $0.productID)?.tier == tier }
            .first?.productID
        status = status.merging(history: history, activeTier: tier)
        hasResolvedEntitlements = true
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: Keys.status)
        }
        defaults.set(activeTier.rawValue, forKey: Keys.activeTier)
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
