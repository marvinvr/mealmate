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
        let tip = SupporterStatus().merging(history: [.init(productID: "tip.espresso", purchaseDate: june)], activeTier: .none)
        #expect(tip.isSupporter)
        #expect(tip.tipCount == 1)
        #expect(tip.supporterSince == june)

        let subscription = SupporterStatus().merging(history: [.init(productID: "souschef.monthly", purchaseDate: march)],
                                                     activeTier: .none)
        #expect(subscription.isSupporter)
        #expect(subscription.tipCount == 0)
    }

    @Test func statusNeverDowngrades() {
        let supporter = SupporterStatus(isSupporter: true, supporterSince: march, tipCount: 3)
        // An empty history read (offline, sandbox hiccup) or a lapsed subscription keeps everything.
        #expect(supporter.merging(history: [], activeTier: .none) == supporter)
        // Fewer tips in a later read don't lower the count; an earlier purchase moves "since" back.
        let merged = supporter.merging(history: [.init(productID: "tip.brunch", purchaseDate: june)], activeTier: .none)
        #expect(merged.tipCount == 3)
        #expect(merged.supporterSince == march)
    }

    @Test func revokedAndUnknownTransactionsAreNoEvidence() {
        let history: [SupporterPurchaseRecord] = [
            .init(productID: "tip.feast", purchaseDate: march, isRevoked: true),
            .init(productID: "com.example.other", purchaseDate: march),
        ]
        #expect(SupporterStatus().merging(history: history, activeTier: .none) == SupporterStatus())
    }

    @Test func tipsCountQuantitiesAndEarliestDateWins() {
        let history: [SupporterPurchaseRecord] = [
            .init(productID: "tip.espresso", purchaseDate: june, quantity: 2),
            .init(productID: "tip.dinnerparty", purchaseDate: march),
            .init(productID: "headchef.yearly", purchaseDate: june),
        ]
        let status = SupporterStatus().merging(history: history, activeTier: .headChef)
        #expect(status.tipCount == 3)
        #expect(status.supporterSince == march)
    }

    @Test func activeTierIsTheHighestLiveSubscription() {
        let now = june
        let later = now.addingTimeInterval(86_400)
        let earlier = now.addingTimeInterval(-86_400)
        #expect(SupporterStatus.activeTier(entitlements: [], now: now) == .none)
        #expect(SupporterStatus.activeTier(entitlements: [.init(productID: "souschef.yearly", expirationDate: later)], now: now) == .sousChef)
        #expect(SupporterStatus.activeTier(entitlements: [
            .init(productID: "souschef.monthly", expirationDate: later, isUpgraded: true),
            .init(productID: "headchef.monthly", expirationDate: later),
        ], now: now) == .headChef)
        #expect(SupporterStatus.activeTier(entitlements: [.init(productID: "headchef.monthly", expirationDate: earlier)], now: now) == .none)
        #expect(SupporterStatus.activeTier(entitlements: [.init(productID: "headchef.yearly", expirationDate: later, isRevoked: true)], now: now) == .none)
        // Tips are never an active level.
        #expect(SupporterStatus.activeTier(entitlements: [.init(productID: "tip.feast")], now: now) == .none)
    }

    @Test func catalogMatchesTheStoreKitConfiguration() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "MealMate", withExtension: "storekit"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = (json["products"] as? [[String: Any]] ?? []).compactMap { $0["productID"] as? String }
        let groups = json["subscriptionGroups"] as? [[String: Any]] ?? []
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        #expect(groups.map { $0["name"] as? String } == ["MealMate Supporter"])
        #expect(Set(products + subscriptions.compactMap { $0["productID"] as? String }) == Set(SupporterProduct.allIDs))
        // Head Chef is the higher level (1 = highest) and subscriptions are family-shareable.
        for subscription in subscriptions {
            let id = try #require(subscription["productID"] as? String)
            #expect(subscription["groupNumber"] as? Int == (id.hasPrefix("headchef") ? 1 : 2))
            #expect(subscription["familyShareable"] as? Bool == true)
        }
    }
}

private final class BundleToken {}

// MARK: - App icons

struct AppIconEntitlementTests {
    @Test func iconsUnlockByLevel() {
        #expect(MealMateAppIcon.default.isAvailable(isSupporter: false, tier: .none))
        #expect(!MealMateAppIcon.wood.isAvailable(isSupporter: false, tier: .none))
        #expect(MealMateAppIcon.wood.isAvailable(isSupporter: true, tier: .none))
        #expect(!MealMateAppIcon.copperPot.isAvailable(isSupporter: true, tier: .sousChef))
        #expect(MealMateAppIcon.midnightKitchen.isAvailable(isSupporter: true, tier: .headChef))
        #expect(MealMateAppIcon.supporterIcons.count == 7) // default + six
        #expect(MealMateAppIcon.headChefIcons == [.copperPot, .midnightKitchen])
    }

    @Test func lapsedHeadChefFallsBackToTheDefaultIcon() {
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: true, tier: .none) == .default)
        #expect(MealMateAppIcon.fallback(for: .midnightKitchen, isSupporter: true, tier: .sousChef) == .default)
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: true, tier: .headChef) == nil)
        // Supporter icons stay after a subscription ends: supporter status is for good.
        #expect(MealMateAppIcon.fallback(for: .tomato, isSupporter: true, tier: .none) == nil)
        #expect(MealMateAppIcon.fallback(for: .default, isSupporter: false, tier: .none) == nil)
    }

    @Test func everyIconHasDistinctAssetNames() {
        let names = MealMateAppIcon.allCases.compactMap(\.alternateIconName)
        #expect(Set(names).count == MealMateAppIcon.allCases.count - 1)
        #expect(MealMateAppIcon.copperPot.previewImageName == "IconPreviewCopperPot")
        #expect(MealMateAppIcon.default.previewImageName == "IconPreviewDefault")
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

/// Buys every product, switches levels, lets Head Chef lapse and refunds against the local
/// StoreKit configuration, then checks what `SupporterStore` makes of the transactions.
/// Purchases go through `SKTestSession.buyProduct` (an in-app `Product.purchase()` from a unit
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
        #expect(store.sousChefProducts.map(\.id) == ["souschef.monthly", "souschef.yearly"])
        #expect(store.headChefProducts.map(\.id) == ["headchef.monthly", "headchef.yearly"])
        #expect(store.tipProducts.map(\.id) == ["tip.espresso", "tip.brunch", "tip.dinnerparty", "tip.feast"])
        #expect(store.tipProducts.map(\.displayPrice) == ["$2.99", "$9.99", "$19.99", "$49.99"])
        #expect(store.headChefProducts.map(\.displayPrice) == ["$4.99", "$39.99"])
        #expect(store.sousChefProducts.map(\.displayPrice) == ["$1.99", "$14.99"])
        let groups = Set((store.sousChefProducts + store.headChefProducts).compactMap { $0.subscription?.subscriptionGroupID })
        #expect(groups.count == 1)
        #expect((store.sousChefProducts + store.headChefProducts).allSatisfy { $0.isFamilyShareable })
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
        #expect(store.activeTier == .none)
        #expect(store.status.supporterSince != nil)
    }

    @Test func sousChefUpgradesToHeadChefAndDowngradesAtRenewal() async throws {
        let store = await makeStore()
        try await buy(.sousChefMonthly, store: store)
        #expect(store.activeTier == .sousChef)
        #expect(store.activeSubscriptionID == "souschef.monthly")
        #expect(store.isSupporter)
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: store.isSupporter, tier: store.activeTier) == .default)

        // Upgrade: Head Chef starts right away.
        try await buy(.headChefYearly, store: store)
        #expect(store.activeTier == .headChef)
        #expect(store.activeSubscriptionID == "headchef.yearly")
        #expect(MealMateAppIcon.fallback(for: .copperPot, isSupporter: store.isSupporter, tier: store.activeTier) == nil)

        // Downgrade: Head Chef stays until the period ends.
        try await buy(.sousChefYearly, store: store)
        #expect(store.activeTier == .headChef)
    }

    @Test func lapsedHeadChefKeepsSupporterStatusButNotTheExclusiveIcons() async throws {
        // A real lapse: renewals every two seconds, auto-renew turned off, period runs out.
        // (`expireSubscription` only changes the session's record, not the app's entitlements.)
        session.timeRate = .oneRenewalEveryTwoSeconds
        defer { session.timeRate = .realTime }
        let store = await makeStore()
        try await buy(.headChefMonthly, store: store)
        #expect(store.isHeadChef)
        let transaction = try #require(session.allTransactions().last { $0.productIdentifier == SupporterProduct.headChefMonthly.rawValue })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)

        for _ in 0..<40 where store.activeTier != .none {
            try await Task.sleep(for: .milliseconds(250))
            await store.refreshEntitlements()
        }
        #expect(store.activeTier == .none)
        #expect(store.isSupporter)
        #expect(MealMateAppIcon.fallback(for: .midnightKitchen, isSupporter: store.isSupporter, tier: store.activeTier) == .default)
        #expect(MealMateAppIcon.fallback(for: .wood, isSupporter: store.isSupporter, tier: store.activeTier) == nil)
    }

    @Test func historyRestoresStatusOnAFreshInstall() async throws {
        let store = await makeStore()
        try await buy(.tipBrunch, store: store)
        try await buy(.sousChefYearly, store: store)

        // A reinstall starts with an empty cache: status comes back from the history.
        defaults.removePersistentDomain(forName: defaultsName)
        let reinstalled = await makeStore()
        #expect(reinstalled.isSupporter)
        #expect(reinstalled.status.tipCount == 1)
        #expect(reinstalled.activeTier == .sousChef)
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
