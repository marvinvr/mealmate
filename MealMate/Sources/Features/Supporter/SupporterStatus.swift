import Foundation

/// The supporter product catalog. Everything in MealMate stays free; these exist so people can
/// chip in: one subscription (monthly or yearly) and one-time tips. Tips are consumables so they
/// can be given again. IDs must match App Store Connect and `MealMate.storekit`
/// (docs/supporter.md).
///
/// The subscription reuses the `headchef.*` IDs from the earlier two-level setup. The old
/// `souschef.*` level is retired: no longer offered, but an active one still counts as
/// subscribed (same perks), and any purchase of it still makes someone a supporter.
enum SupporterProduct: String, CaseIterable, Sendable {
    case monthly = "headchef.monthly"
    case yearly = "headchef.yearly"
    case legacySousChefMonthly = "souschef.monthly"
    case legacySousChefYearly = "souschef.yearly"
    case tipEspresso = "tip.espresso"
    case tipBrunch = "tip.brunch"
    case tipDinnerParty = "tip.dinnerparty"
    case tipFeast = "tip.feast"

    /// Every ID the app recognizes in transactions, retired ones included.
    static var allIDs: [String] { allCases.map(\.rawValue) }
    /// The IDs the sheet offers.
    static var offeredIDs: [String] { allCases.filter { !$0.isLegacy }.map(\.rawValue) }

    var isSubscription: Bool {
        switch self {
        case .monthly, .yearly, .legacySousChefMonthly, .legacySousChefYearly: true
        case .tipEspresso, .tipBrunch, .tipDinnerParty, .tipFeast: false
        }
    }

    /// A retired subscription: honoured, no longer sold.
    var isLegacy: Bool { self == .legacySousChefMonthly || self == .legacySousChefYearly }
    var isYearly: Bool { self == .yearly || self == .legacySousChefYearly }

    /// Display order in the sheet: monthly before yearly, tips by price.
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Name in the sheet. The app's own copy (English like the rest of the UI), not StoreKit's
    /// localized metadata; prices do come from StoreKit.
    var displayName: String {
        switch self {
        case .monthly, .legacySousChefMonthly: "Monthly"
        case .yearly, .legacySousChefYearly: "Yearly"
        case .tipEspresso: "Espresso"
        case .tipBrunch: "Brunch"
        case .tipDinnerParty: "Dinner Party"
        case .tipFeast: "Feast"
        }
    }
}

/// One verified transaction from `Transaction.all`, reduced to what supporter status needs.
struct SupporterPurchaseRecord: Equatable, Sendable {
    var productID: String
    var purchaseDate: Date
    var quantity: Int = 1
    var isRevoked = false
}

/// One verified transaction from `Transaction.currentEntitlements`.
struct SupporterEntitlementRecord: Equatable, Sendable {
    var productID: String
    var expirationDate: Date?
    var isRevoked = false
    /// The subscription was replaced by a higher level in the same group.
    var isUpgraded = false
}

/// Lifetime supporter status, cached in UserDefaults so Settings renders correctly offline.
///
/// Monotonic: any verified purchase ever makes someone a supporter for good, and a history read
/// can only add evidence, never take it away (an empty read offline or in a sandbox hiccup must
/// not downgrade a supporter).
struct SupporterStatus: Equatable, Sendable, Codable {
    var isSupporter = false
    var supporterSince: Date?
    var tipCount = 0

    /// Folds a `Transaction.all` read (plus whether a subscription is active right now) into the
    /// cached status. Revoked (refunded) transactions don't add evidence.
    func merging(history: [SupporterPurchaseRecord], isSubscribed: Bool) -> SupporterStatus {
        var result = self
        var tips = 0
        for record in history where !record.isRevoked {
            guard let product = SupporterProduct(rawValue: record.productID) else { continue }
            result.isSupporter = true
            result.supporterSince = min(result.supporterSince ?? record.purchaseDate, record.purchaseDate)
            if !product.isSubscription { tips += max(record.quantity, 1) }
        }
        if isSubscribed { result.isSupporter = true }
        result.tipCount = max(tipCount, tips)
        return result
    }

    /// The subscription that is active right now, retired levels included (they keep every
    /// subscription perk). Upgraded-away, revoked and expired subscriptions don't count; with
    /// more than one live, the current offering wins.
    static func activeSubscription(entitlements: [SupporterEntitlementRecord], now: Date = .now) -> SupporterProduct? {
        entitlements
            .filter { !$0.isRevoked && !$0.isUpgraded && $0.expirationDate.map { $0 > now } ?? true }
            .compactMap { SupporterProduct(rawValue: $0.productID) }
            .filter(\.isSubscription)
            .min { !$0.isLegacy && $1.isLegacy }
    }
}
