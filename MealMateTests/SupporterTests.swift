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

    @Test func espressoIsAThankYouOnly() {
        let espresso = SupporterStatus().merging(history: [.init(productID: "tip.espresso", purchaseDate: june, quantity: 3)],
                                                 isSubscribed: false)
        #expect(espresso.isSupporter)
        #expect(!espresso.hasFoodIcons)
        #expect(SupporterProduct.allCases.filter { !$0.unlocksFoodIcons } == [.tipEspresso])

        // Brunch and up, and any subscription (also retired, also lapsed), unlock the food icons for good.
        for id in ["tip.brunch", "tip.dinnerparty", "tip.feast", "headchef.monthly", "headchef.yearly", "souschef.monthly"] {
            #expect(espresso.merging(history: [.init(productID: id, purchaseDate: june)], isSubscribed: false).hasFoodIcons)
        }
        #expect(SupporterStatus().merging(history: [], isSubscribed: true).hasFoodIcons)
        // Refunded purchases don't unlock them, and once unlocked an empty read keeps them.
        #expect(!SupporterStatus().merging(history: [.init(productID: "tip.feast", purchaseDate: june, isRevoked: true)],
                                           isSubscribed: false).hasFoodIcons)
        let unlocked = SupporterStatus(isSupporter: true, supporterSince: june, tipCount: 1, hasFoodIcons: true)
        #expect(unlocked.merging(history: [], isSubscribed: false).hasFoodIcons)
    }

    @Test func cacheFromBeforeTheFoodIconFlagStillDecodes() throws {
        let old = #"{"isSupporter":true,"supporterSince":800000000,"tipCount":2}"#
        let status = try JSONDecoder().decode(SupporterStatus.self, from: Data(old.utf8))
        #expect(status.isSupporter)
        #expect(status.tipCount == 2)
        #expect(!status.hasFoodIcons)
        let roundTrip = try JSONDecoder().decode(SupporterStatus.self, from: JSONEncoder().encode(SupporterStatus(isSupporter: true, hasFoodIcons: true)))
        #expect(roundTrip.hasFoodIcons)
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
        #expect(status.hasFoodIcons)
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
        #expect(MealMateAppIcon.default.isAvailable(hasFoodIcons: false, isSubscribed: false))
        #expect(!MealMateAppIcon.ramen.isAvailable(hasFoodIcons: false, isSubscribed: false))
        // Food icons: a subscription or a tip from Brunch up.
        #expect(MealMateAppIcon.ramen.isAvailable(hasFoodIcons: true, isSubscribed: false))
        #expect(MealMateAppIcon.grainBowl.isAvailable(hasFoodIcons: false, isSubscribed: true))
        // Subscription icons: only while subscribed, tips don't unlock them.
        #expect(!MealMateAppIcon.enamelCocotte.isAvailable(hasFoodIcons: true, isSubscribed: false))
        #expect(MealMateAppIcon.sundayBrunch.isAvailable(hasFoodIcons: true, isSubscribed: true))
        #expect(MealMateAppIcon.foodIcons == [.grainBowl, .spaghetti, .shakshuka, .ramen, .margherita])
        #expect(MealMateAppIcon.subscriptionIcons == [.enamelCocotte, .candlelight, .sundayBrunch])
    }

    @Test func lapsedSubscriptionFallsBackToTheDefaultIcon() {
        #expect(MealMateAppIcon.fallback(for: .candlelight, hasFoodIcons: true, isSubscribed: false) == .default)
        #expect(MealMateAppIcon.fallback(for: .candlelight, hasFoodIcons: true, isSubscribed: true) == nil)
        // Food icons stay after a subscription ends: they're unlocked for good.
        #expect(MealMateAppIcon.fallback(for: .margherita, hasFoodIcons: true, isSubscribed: false) == nil)
        #expect(MealMateAppIcon.fallback(for: .default, hasFoodIcons: false, isSubscribed: false) == nil)
        // Without them (only an Espresso tip), a food icon goes back to the default.
        #expect(MealMateAppIcon.fallback(for: .ramen, hasFoodIcons: false, isSubscribed: false) == .default)
    }

    @Test func everyIconHasDistinctAssetNames() {
        let names = MealMateAppIcon.allCases.compactMap(\.alternateIconName)
        #expect(Set(names).count == MealMateAppIcon.allCases.count - 1)
        #expect(MealMateAppIcon.enamelCocotte.previewImageName == "IconPreviewEnamelCocotte")
        #expect(MealMateAppIcon.sundayBrunch.alternateIconName == "AppIconSundayBrunch")
        // Retired icons (also Copper Pot and Midnight Kitchen) are no case any more, so the guard
        // treats them as retired and puts the default back.
        for retired in ["AppIconCopperPot", "AppIconMidnightKitchen", "AppIconMono"] {
            #expect(!MealMateAppIcon.allCases.contains { $0.alternateIconName == retired })
        }
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
            #expect(store.isSupporter)
            // Espresso is a thank-you only; Brunch is the first tip with the food icons.
            #expect(store.hasFoodIcons == (tip != .tipEspresso))
        }
        // Finished consumables can be bought again and stay in the history.
        try await buy(.tipEspresso, store: store)
        #expect(store.status.tipCount == 5)
        #expect(store.isSupporter)
        #expect(!store.isSubscribed)
        #expect(store.status.supporterSince != nil)
        // Tips unlock the food icons, not the subscription icons.
        #expect(MealMateAppIcon.shakshuka.isAvailable(hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed))
        #expect(!MealMateAppIcon.candlelight.isAvailable(hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed))
    }

    @Test func anEspressoTipUnlocksNoIcons() async throws {
        let store = await makeStore()
        try await buy(.tipEspresso, store: store)
        #expect(store.isSupporter)
        #expect(!store.hasFoodIcons)
        for icon in MealMateAppIcon.allCases {
            #expect(icon.isAvailable(hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed) == (icon == .default))
        }
        // Also after a reinstall, from the history.
        defaults.removePersistentDomain(forName: defaultsName)
        let reinstalled = await makeStore()
        #expect(reinstalled.isSupporter)
        #expect(!reinstalled.hasFoodIcons)
    }

    @Test func subscribingUnlocksEveryIcon() async throws {
        let store = await makeStore()
        try await buy(.monthly, store: store)
        #expect(store.isSubscribed)
        #expect(store.activeSubscription == .monthly)
        #expect(store.isSupporter)
        for icon in MealMateAppIcon.allCases {
            #expect(icon.isAvailable(hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed))
        }
    }

    @Test func oldSousChefSubscribersKeepEveryPerk() async throws {
        let store = await makeStore()
        try await buy(.legacySousChefMonthly, store: store)
        #expect(store.isSubscribed)
        #expect(store.activeSubscription == .legacySousChefMonthly)
        #expect(MealMateAppIcon.fallback(for: .sundayBrunch, hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed) == nil)

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
        #expect(MealMateAppIcon.fallback(for: .sundayBrunch, hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed) == .default)
        #expect(MealMateAppIcon.fallback(for: .ramen, hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed) == nil)
    }

    @Test func historyRestoresStatusOnAFreshInstall() async throws {
        let store = await makeStore()
        try await buy(.tipBrunch, store: store)
        try await buy(.yearly, store: store)

        // A reinstall starts with an empty cache: status comes back from the history.
        defaults.removePersistentDomain(forName: defaultsName)
        let reinstalled = await makeStore()
        #expect(reinstalled.isSupporter)
        #expect(reinstalled.hasFoodIcons)
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
