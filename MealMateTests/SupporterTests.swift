import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import MealMate

// MARK: - Status

struct SupporterStatusTests {
    private let march = Date(timeIntervalSince1970: 1_772_323_200) // 2026-03-01
    private let june = Date(timeIntervalSince1970: 1_780_272_000) // 2026-06-01

    @Test func anyPurchaseMakesASupporter() {
        let tip = SupporterStatus().merging(history: [.init(productID: "tip.espresso", purchaseDate: june)], isSubscribed: false)
        #expect(tip.isSupporter)
        #expect(tip.tipCount == 1)
        #expect(tip.supporterSince == june)

        let subscription = SupporterStatus().merging(history: [.init(productID: "headchef.monthly", purchaseDate: march)],
                                                     isSubscribed: false)
        #expect(subscription.isSupporter)
        #expect(subscription.tipCount == 0)

        // A retired Sous Chef purchase is still evidence.
        let legacy = SupporterStatus().merging(history: [.init(productID: "souschef.yearly", purchaseDate: march)],
                                               isSubscribed: false)
        #expect(legacy.isSupporter)
    }

    @Test func statusNeverDowngrades() {
        let supporter = SupporterStatus(isSupporter: true, supporterSince: march, tipCount: 3)
        // An empty history read (offline, sandbox hiccup) or a lapsed subscription keeps everything.
        #expect(supporter.merging(history: [], isSubscribed: false) == supporter)
        // Fewer tips in a later read don't lower the count; an earlier purchase moves "since" back.
        let merged = supporter.merging(history: [.init(productID: "tip.brunch", purchaseDate: june)], isSubscribed: false)
        #expect(merged.tipCount == 3)
        #expect(merged.supporterSince == march)
    }

    @Test func revokedAndUnknownTransactionsAreNoEvidence() {
        let history: [SupporterPurchaseRecord] = [
            .init(productID: "tip.feast", purchaseDate: march, isRevoked: true),
            .init(productID: "com.example.other", purchaseDate: march),
        ]
        #expect(SupporterStatus().merging(history: history, isSubscribed: false) == SupporterStatus())
    }

    @Test func tipsCountQuantitiesAndEarliestDateWins() {
        let history: [SupporterPurchaseRecord] = [
            .init(productID: "tip.espresso", purchaseDate: june, quantity: 2),
            .init(productID: "tip.dinnerparty", purchaseDate: march),
            .init(productID: "headchef.yearly", purchaseDate: june),
        ]
        let status = SupporterStatus().merging(history: history, isSubscribed: true)
        #expect(status.tipCount == 3)
        #expect(status.supporterSince == march)
    }

    @Test func activeSubscriptionIsTheLiveOneIncludingRetiredLevels() {
        let now = june
        let later = now.addingTimeInterval(86_400)
        let earlier = now.addingTimeInterval(-86_400)
        #expect(SupporterStatus.activeSubscription(entitlements: [], now: now) == nil)
        #expect(SupporterStatus.activeSubscription(entitlements: [.init(productID: "headchef.yearly", expirationDate: later)], now: now) == .yearly)
        // An old Sous Chef subscription keeps every subscription perk.
        #expect(SupporterStatus.activeSubscription(entitlements: [.init(productID: "souschef.monthly", expirationDate: later)], now: now) == .legacySousChefMonthly)
        // Moving from Sous Chef to the current subscription: the current one wins.
        #expect(SupporterStatus.activeSubscription(entitlements: [
            .init(productID: "souschef.monthly", expirationDate: later, isUpgraded: true),
            .init(productID: "headchef.monthly", expirationDate: later),
        ], now: now) == .monthly)
        #expect(SupporterStatus.activeSubscription(entitlements: [
            .init(productID: "souschef.yearly", expirationDate: later),
            .init(productID: "headchef.monthly", expirationDate: later),
        ], now: now) == .monthly)
        #expect(SupporterStatus.activeSubscription(entitlements: [.init(productID: "headchef.monthly", expirationDate: earlier)], now: now) == nil)
        #expect(SupporterStatus.activeSubscription(entitlements: [.init(productID: "headchef.yearly", expirationDate: later, isRevoked: true)], now: now) == nil)
        // Tips are never a subscription.
        #expect(SupporterStatus.activeSubscription(entitlements: [.init(productID: "tip.feast")], now: now) == nil)
    }

    @Test func offeredProductsLeaveOutTheRetiredLevel() {
        #expect(SupporterProduct.offeredIDs == ["headchef.monthly", "headchef.yearly", "tip.espresso", "tip.brunch",
                                                "tip.dinnerparty", "tip.feast"])
        #expect(SupporterProduct.allCases.filter(\.isLegacy) == [.legacySousChefMonthly, .legacySousChefYearly])
    }

    @Test func catalogMatchesTheStoreKitConfiguration() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "MealMate", withExtension: "storekit"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = (json["products"] as? [[String: Any]] ?? []).compactMap { $0["productID"] as? String }
        let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        #expect(groups.map { $0["name"] as? String } == ["MealMate Supporter"])
        #expect(Set(products + subscriptions.compactMap { $0["productID"] as? String }) == Set(SupporterProduct.allIDs))
        // The current subscription is the top level (1), the retired Sous Chef below it; all
        // subscriptions are family-shareable.
        for subscription in subscriptions {
            let id = try #require(subscription["productID"] as? String)
            #expect(subscription["groupNumber"] as? Int == (SupporterProduct(rawValue: id)?.isLegacy == true ? 2 : 1))
            #expect(subscription["familyShareable"] as? Bool == true)
        }
    }
}

private final class BundleToken {}

// MARK: - App icons

struct AppIconEntitlementTests {
    @Test func iconsUnlockBySupportAndSubscription() {
        #expect(MealMateAppIcon.default.isAvailable(isSupporter: false, isSubscribed: false))
        #expect(!MealMateAppIcon.ramen.isAvailable(isSupporter: false, isSubscribed: false))
        // Food icons: any tip or subscription.
        #expect(MealMateAppIcon.ramen.isAvailable(isSupporter: true, isSubscribed: false))
        #expect(MealMateAppIcon.grainBowl.isAvailable(isSupporter: false, isSubscribed: true))
        // Subscription icons: only while subscribed, tips don't unlock them.
        #expect(!MealMateAppIcon.copperPot.isAvailable(isSupporter: true, isSubscribed: false))
        #expect(MealMateAppIcon.midnightKitchen.isAvailable(isSupporter: true, isSubscribed: true))
        #expect(MealMateAppIcon.foodIcons == [.grainBowl, .spaghetti, .shakshuka, .ramen, .margherita])
        #expect(MealMateAppIcon.subscriptionIcons == [.copperPot, .midnightKitchen])
    }

    @Test func lapsedSubscriptionFallsBackToTheDefaultIcon() {
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: true, isSubscribed: false) == .default)
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: true, isSubscribed: true) == nil)
        // Food icons stay after a subscription ends: supporter status is for good.
        #expect(MealMateAppIcon.fallback(for: .margherita, isSupporter: true, isSubscribed: false) == nil)
        #expect(MealMateAppIcon.fallback(for: .default, isSupporter: false, isSubscribed: false) == nil)
    }

    @Test func everyIconHasDistinctAssetNames() {
        let names = MealMateAppIcon.allCases.compactMap(\.alternateIconName)
        #expect(Set(names).count == MealMateAppIcon.allCases.count - 1)
        #expect(MealMateAppIcon.copperPot.previewImageName == "IconPreviewCopperPot")
        #expect(MealMateAppIcon.grainBowl.previewImageName == "IconPreviewGrainBowl")
        #expect(MealMateAppIcon.default.previewImageName == "IconPreviewDefault")
    }
}

// MARK: - Cache migration

@MainActor
struct SupporterCacheTests {
    @Test func oldTierCacheCountsAsSubscribed() throws {
        let name = "SupporterCacheTests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for (tier, subscribed) in [(0, false), (1, true), (2, true)] {
            defaults.removePersistentDomain(forName: name)
            defaults.set(tier, forKey: "supporter.activeTier")
            #expect(SupporterStore(defaults: defaults).isSubscribed == subscribed)
        }
        // The new key wins once written.
        defaults.set(false, forKey: "supporter.isSubscribed")
        #expect(!SupporterStore(defaults: defaults).isSubscribed)
    }
}

// MARK: - Prompt gate

struct SupporterPromptGateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }()
    private let start = Date(timeIntervalSince1970: 1_767_261_600) // 2026-01-01 10:00 CET

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: start)! }

    private func ledger(usageDays: Int, prompts: Int = 0, lastPrompt: Int? = nil, usageAtLastPrompt: Int = 0) -> SupporterPromptLedger {
        var ledger = SupporterPromptLedger(firstLaunchDate: start)
        ledger.usageDays = usageDays
        ledger.promptCount = prompts
        ledger.lastPromptDate = lastPrompt.map(day)
        ledger.usageDaysAtLastPrompt = usageAtLastPrompt
        return ledger
    }

    private func shows(_ ledger: SupporterPromptLedger, on offset: Int, supporter: Bool = false) -> Bool {
        SupporterPromptGate.shouldShow(ledger: ledger, isSupporter: supporter, now: day(offset), calendar: calendar)
    }

    @Test func firstPromptNeedsAWeekAndThreeUsageDays() {
        #expect(!shows(ledger(usageDays: 10), on: 6))
        #expect(!shows(ledger(usageDays: 2), on: 30))
        #expect(shows(ledger(usageDays: 3), on: 7))
    }

    @Test func secondAndThirdPromptsEscalate() {
        // Prompt 2: ≥ 30 days, ≥ 10 usage days, ≥ 14 days since prompt 1.
        #expect(!shows(ledger(usageDays: 9, prompts: 1, lastPrompt: 7), on: 40))
        #expect(!shows(ledger(usageDays: 12, prompts: 1, lastPrompt: 20), on: 30))
        #expect(shows(ledger(usageDays: 10, prompts: 1, lastPrompt: 10), on: 30))
        // Prompt 3: ≥ 90 days, ≥ 25 usage days, ≥ 30 days since prompt 2.
        #expect(!shows(ledger(usageDays: 24, prompts: 2, lastPrompt: 30), on: 120))
        #expect(!shows(ledger(usageDays: 30, prompts: 2, lastPrompt: 70), on: 90))
        #expect(shows(ledger(usageDays: 25, prompts: 2, lastPrompt: 60), on: 90))
    }

    @Test func thenAtMostYearly() {
        // First yearly prompt: a year after the first launch, 180 days after prompt 3, 12 new usage days.
        let afterThird = ledger(usageDays: 60, prompts: 3, lastPrompt: 200, usageAtLastPrompt: 40)
        #expect(!shows(afterThird, on: 364))
        #expect(!shows(afterThird, on: 379)) // only 179 days since prompt 3
        #expect(shows(afterThird, on: 380))
        #expect(!shows(ledger(usageDays: 51, prompts: 3, lastPrompt: 200, usageAtLastPrompt: 40), on: 400))
        // Later ones: 365 days apart.
        let yearly = ledger(usageDays: 100, prompts: 4, lastPrompt: 400, usageAtLastPrompt: 60)
        #expect(!shows(yearly, on: 764))
        #expect(shows(yearly, on: 765))
    }

    @Test func neverForSupporters() {
        #expect(!shows(ledger(usageDays: 100), on: 100, supporter: true))
        #expect(!shows(ledger(usageDays: 200, prompts: 5, lastPrompt: 10, usageAtLastPrompt: 0), on: 2000, supporter: true))
    }

    @Test func usageDaysCountDistinctCalendarDays() {
        var ledger = SupporterPromptLedger(firstLaunchDate: start)
        ledger.registerUsageDay(now: start, calendar: calendar)
        ledger.registerUsageDay(now: start.addingTimeInterval(3600), calendar: calendar)
        #expect(ledger.usageDays == 1)
        ledger.registerUsageDay(now: day(1), calendar: calendar)
        ledger.registerUsageDay(now: day(5), calendar: calendar)
        #expect(ledger.usageDays == 3)

        ledger.registerPrompt(now: day(7))
        #expect(ledger.promptCount == 1)
        #expect(ledger.lastPromptDate == day(7))
        #expect(ledger.usageDaysAtLastPrompt == 3)
    }

    @Test func ledgerRoundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "SupporterPromptGateTests"))
        defaults.removePersistentDomain(forName: "SupporterPromptGateTests")
        let fresh = SupporterPromptLedger.load(from: defaults, now: start)
        #expect(fresh.firstLaunchDate == start)
        var ledger = fresh
        ledger.registerUsageDay(now: day(2), calendar: calendar)
        ledger.save(to: defaults)
        #expect(SupporterPromptLedger.load(from: defaults, now: day(9)) == ledger)
        defaults.removePersistentDomain(forName: "SupporterPromptGateTests")
    }
}

// MARK: - StoreKit flows (local MealMate.storekit via StoreKitTest)

/// Buys every product, moves a retired Sous Chef plan over, lets the subscription lapse and
/// refunds against the local StoreKit configuration, then checks what `SupporterStore` makes of
/// the transactions. Purchases go through `SKTestSession.buyProduct` (an in-app `Product.purchase()` from a unit
/// test asks for a sandbox Apple Account in the simulator). Serialized: the session is global.
@MainActor
@Suite(.serialized)
final class SupporterStoreKitTests {
    private let session: SKTestSession
    private let defaultsName = "SupporterStoreKitTests"
    private let defaults: UserDefaults

    init() throws {
        session = try SKTestSession(configurationFileNamed: "MealMate")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
    }

    deinit {
        session.clearTransactions()
        UserDefaults(suiteName: "SupporterStoreKitTests")?.removePersistentDomain(forName: "SupporterStoreKitTests")
    }

    private func makeStore() async -> SupporterStore {
        let store = SupporterStore(defaults: defaults)
        await store.refreshEntitlements()
        await store.loadProducts()
        return store
    }

    /// Buys like the App Store would, finishes the transaction (as the store's listener does)
    /// and lets the store re-read its entitlements.
    private func buy(_ product: SupporterProduct, store: SupporterStore) async throws {
        let transaction = try await session.buyProduct(identifier: product.rawValue, options: [])
        await transaction.finish()
        await store.refreshEntitlements()
    }

    @Test func loadsTheCatalogInDisplayOrder() async {
        let store = await makeStore()
        #expect(store.subscriptionProducts.map(\.id) == ["headchef.monthly", "headchef.yearly"])
        #expect(store.subscriptionProducts.map(\.displayPrice) == ["$2.99", "$24.99"])
        #expect(store.tipProducts.map(\.id) == ["tip.espresso", "tip.brunch", "tip.dinnerparty", "tip.feast"])
        #expect(store.tipProducts.map(\.displayPrice) == ["$2.99", "$9.99", "$19.99", "$49.99"])
        #expect(store.subscriptionProducts.allSatisfy { $0.isFamilyShareable && $0.subscription != nil })
        #expect(!store.productsUnavailable)
        #expect(!store.isSupporter)
    }

    @Test func everyTipMakesASupporterAndCanBeGivenAgain() async throws {
        let store = await makeStore()
        for (index, tip) in [SupporterProduct.tipEspresso, .tipBrunch, .tipDinnerParty, .tipFeast].enumerated() {
            try await buy(tip, store: store)
            #expect(store.status.tipCount == index + 1)
        }
        // Finished consumables can be bought again and stay in the history.
        try await buy(.tipEspresso, store: store)
        #expect(store.status.tipCount == 5)
        #expect(store.isSupporter)
        #expect(!store.isSubscribed)
        #expect(store.status.supporterSince != nil)
        // Tips unlock the food icons, not the subscription icons.
        #expect(MealMateAppIcon.shakshuka.isAvailable(isSupporter: store.isSupporter, isSubscribed: store.isSubscribed))
        #expect(!MealMateAppIcon.copperPot.isAvailable(isSupporter: store.isSupporter, isSubscribed: store.isSubscribed))
    }

    @Test func subscribingUnlocksEveryIcon() async throws {
        let store = await makeStore()
        try await buy(.monthly, store: store)
        #expect(store.isSubscribed)
        #expect(store.activeSubscription == .monthly)
        #expect(store.isSupporter)
        for icon in MealMateAppIcon.allCases {
            #expect(icon.isAvailable(isSupporter: store.isSupporter, isSubscribed: store.isSubscribed))
        }
    }

    @Test func oldSousChefSubscribersKeepEveryPerk() async throws {
        let store = await makeStore()
        try await buy(.legacySousChefMonthly, store: store)
        #expect(store.isSubscribed)
        #expect(store.activeSubscription == .legacySousChefMonthly)
        #expect(MealMateAppIcon.fallback(for: .midnightKitchen, isSupporter: store.isSupporter, isSubscribed: store.isSubscribed) == nil)

        // Moving to the current subscription (the higher level) starts right away.
        try await buy(.yearly, store: store)
        #expect(store.isSubscribed)
        #expect(store.activeSubscription == .yearly)
    }

    @Test func lapsedSubscriptionKeepsSupporterStatusButNotTheSubscriptionIcons() async throws {
        // A real lapse: renewals every two seconds, auto-renew turned off, period runs out.
        // (`expireSubscription` only changes the session's record, not the app's entitlements.)
        session.timeRate = .oneRenewalEveryTwoSeconds
        defer { session.timeRate = .realTime }
        let store = await makeStore()
        try await buy(.monthly, store: store)
        #expect(store.isSubscribed)
        let transaction = try #require(session.allTransactions().last { $0.productIdentifier == SupporterProduct.monthly.rawValue })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)

        for _ in 0..<40 where store.isSubscribed {
            try await Task.sleep(for: .milliseconds(250))
            await store.refreshEntitlements()
        }
        #expect(!store.isSubscribed)
        #expect(store.activeSubscription == nil)
        #expect(store.isSupporter)
        #expect(MealMateAppIcon.fallback(for: .midnightKitchen, isSupporter: store.isSupporter, isSubscribed: store.isSubscribed) == .default)
        #expect(MealMateAppIcon.fallback(for: .ramen, isSupporter: store.isSupporter, isSubscribed: store.isSubscribed) == nil)
    }

    @Test func historyRestoresStatusOnAFreshInstall() async throws {
        let store = await makeStore()
        try await buy(.tipBrunch, store: store)
        try await buy(.yearly, store: store)

        // A reinstall starts with an empty cache: status comes back from the history.
        defaults.removePersistentDomain(forName: defaultsName)
        let reinstalled = await makeStore()
        #expect(reinstalled.isSupporter)
        #expect(reinstalled.status.tipCount == 1)
        #expect(reinstalled.isSubscribed)
        #expect(reinstalled.activeSubscription == .yearly)
    }

    @Test func refundKeepsTheCachedStatus() async throws {
        let store = await makeStore()
        try await buy(.tipFeast, store: store)
        let transaction = try #require(session.allTransactions().first { $0.productIdentifier == SupporterProduct.tipFeast.rawValue })
        try session.refundTransaction(identifier: transaction.identifier)
        try await Task.sleep(for: .milliseconds(500))
        await store.refreshEntitlements()
        // Once a supporter, always a supporter on this device.
        #expect(store.isSupporter)
        #expect(SupporterStore(defaults: defaults).isSupporter)
    }
}
