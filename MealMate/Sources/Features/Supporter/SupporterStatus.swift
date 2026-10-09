import Foundation

/// Subscription levels of the "MealMate Supporter" group. Tips have no level; any purchase
/// makes someone a supporter, a level only matters while its subscription is active.
enum SupporterTier: Int, Comparable, Sendable, Codable {
    case none = 0
    case sousChef = 1
    case headChef = 2

    static func < (lhs: SupporterTier, rhs: SupporterTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .none: "Supporter"
        case .sousChef: "Sous Chef"
        case .headChef: "Head Chef"
        }
    }
}

/// The supporter product catalog. Everything in MealMate stays free; these exist so people can
/// chip in. Tips are consumables so they can be given again; both subscription levels live in
/// one App Store group, so switching between them is an upgrade / downgrade, not a second
/// subscription. IDs must match App Store Connect and `MealMate.storekit` (docs/supporter.md).
enum SupporterProduct: String, CaseIterable, Sendable {
    case sousChefMonthly = "souschef.monthly"
    case sousChefYearly = "souschef.yearly"
    case headChefMonthly = "headchef.monthly"
    case headChefYearly = "headchef.yearly"
    case tipEspresso = "tip.espresso"
    case tipBrunch = "tip.brunch"
    case tipDinnerParty = "tip.dinnerparty"
    case tipFeast = "tip.feast"

    static var allIDs: [String] { allCases.map(\.rawValue) }

    /// The subscription level, `nil` for tips.
    var tier: SupporterTier? {
        switch self {
        case .sousChefMonthly, .sousChefYearly: .sousChef
        case .headChefMonthly, .headChefYearly: .headChef
        case .tipEspresso, .tipBrunch, .tipDinnerParty, .tipFeast: nil
        }
    }

    var isSubscription: Bool { tier != nil }
    var isYearly: Bool { self == .sousChefYearly || self == .headChefYearly }

    /// Display order in the sheet: subscriptions monthly before yearly, tips by price.
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Name in the sheet. The app's own copy (English like the rest of the UI), not StoreKit's
    /// localized metadata; prices do come from StoreKit.
    var displayName: String {
        switch self {
        case .sousChefMonthly: "Sous Chef Monthly"
        case .sousChefYearly: "Sous Chef Yearly"
        case .headChefMonthly: "Head Chef Monthly"
        case .headChefYearly: "Head Chef Yearly"
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
    func merging(history: [SupporterPurchaseRecord], activeTier: SupporterTier) -> SupporterStatus {
        var result = self
        var tips = 0
        for record in history where !record.isRevoked {
            guard let product = SupporterProduct(rawValue: record.productID) else { continue }
            result.isSupporter = true
            result.supporterSince = min(result.supporterSince ?? record.purchaseDate, record.purchaseDate)
            if !product.isSubscription { tips += max(record.quantity, 1) }
        }
        if activeTier > .none { result.isSupporter = true }
        result.tipCount = max(tipCount, tips)
        return result
    }

    /// The highest subscription level that is active right now. Upgraded-away, revoked and
    /// expired subscriptions don't count.
    static func activeTier(entitlements: [SupporterEntitlementRecord], now: Date = .now) -> SupporterTier {
        entitlements.reduce(.none) { tier, record in
            guard !record.isRevoked, !record.isUpgraded,
                  record.expirationDate.map({ $0 > now }) ?? true,
                  let level = SupporterProduct(rawValue: record.productID)?.tier else { return tier }
            return max(tier, level)
        }
    }
}
