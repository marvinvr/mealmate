import SwiftUI
import UIKit

/// What the prompt ladder remembers about this device (UserDefaults, `supporter.promptLedger`).
/// Existing installs have no install date: their clock starts with the first launch of the
/// version that ships this, on purpose.
struct SupporterPromptLedger: Codable, Equatable, Sendable {
    var firstLaunchDate: Date
    /// Distinct calendar days the signed-in app was opened.
    var usageDays = 0
    var lastUsageDay: Date?
    var promptCount = 0
    var lastPromptDate: Date?
    /// `usageDays` when the last prompt showed (the yearly prompt needs fresh usage).
    var usageDaysAtLastPrompt = 0

    init(firstLaunchDate: Date) {
        self.firstLaunchDate = firstLaunchDate
    }

    /// Counts `now` as a usage day unless the same calendar day was already counted.
    mutating func registerUsageDay(now: Date = .now, calendar: Calendar = .current) {
        if let lastUsageDay, calendar.isDate(lastUsageDay, inSameDayAs: now) { return }
        usageDays += 1
        lastUsageDay = now
    }

    /// Advances the ladder; called the moment a prompt is shown. "Maybe Later" changes nothing.
    mutating func registerPrompt(now: Date = .now) {
        promptCount += 1
        lastPromptDate = now
        usageDaysAtLastPrompt = usageDays
    }

    private static let key = "supporter.promptLedger"

    static func load(from defaults: UserDefaults = .standard, now: Date = .now) -> SupporterPromptLedger {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
            ?? SupporterPromptLedger(firstLaunchDate: now)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// When the supporter sheet may ask by itself. Deliberately conservative: three prompts with
/// escalating thresholds, so light users stop qualifying instead of being asked again, then
/// at most one a year for people who keep cooking with MealMate. Never for supporters (their
/// purchase history syncs across their devices, so none of them asks).
enum SupporterPromptGate {
    struct Milestone: Equatable, Sendable {
        let minDaysSinceFirstLaunch: Int
        let minUsageDays: Int
        /// Keeps a user who catches up with several milestones at once from seeing them close
        /// together.
        let minDaysSincePreviousPrompt: Int
    }

    static let initialMilestones: [Milestone] = [
        Milestone(minDaysSinceFirstLaunch: 7, minUsageDays: 3, minDaysSincePreviousPrompt: 0),
        Milestone(minDaysSinceFirstLaunch: 30, minUsageDays: 10, minDaysSincePreviousPrompt: 14),
        Milestone(minDaysSinceFirstLaunch: 90, minUsageDays: 25, minDaysSincePreviousPrompt: 30),
    ]

    /// Yearly prompts start a year after the first launch, the first one 180 days after the
    /// third prompt, later ones 365 days apart, each after 12 more usage days.
    static let yearlyStartDays = 365
    static let firstYearlyGapDays = 180
    static let yearlyGapDays = 365
    static let yearlyMinNewUsageDays = 12

    static func shouldShow(ledger: SupporterPromptLedger, isSupporter: Bool, now: Date = .now,
                           calendar: Calendar = .current) -> Bool {
        guard !isSupporter else { return false }
        let daysSinceFirstLaunch = days(from: ledger.firstLaunchDate, to: now, calendar: calendar)
        let daysSinceLastPrompt = ledger.lastPromptDate.map { days(from: $0, to: now, calendar: calendar) }

        guard ledger.promptCount < initialMilestones.count else {
            guard daysSinceFirstLaunch >= yearlyStartDays, let daysSinceLastPrompt else { return false }
            let gap = ledger.promptCount == initialMilestones.count ? firstYearlyGapDays : yearlyGapDays
            return daysSinceLastPrompt >= gap
                && ledger.usageDays - ledger.usageDaysAtLastPrompt >= yearlyMinNewUsageDays
        }

        let milestone = initialMilestones[ledger.promptCount]
        return daysSinceFirstLaunch >= milestone.minDaysSinceFirstLaunch
            && ledger.usageDays >= milestone.minUsageDays
            && (daysSinceLastPrompt ?? .max) >= milestone.minDaysSincePreviousPrompt
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// Presents the supporter prompt over the signed-in tab shell (`MainTabView`, so onboarding
/// never prompts and only signed-in days count). Checks when the app becomes active, after a
/// short grace period, and never while anything is presented on top of the tabs: cook mode,
/// Settings, any sheet, alert or dialog.
private struct SupporterPromptPresenter: ViewModifier {
    @Environment(SupporterStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt: Prompt?

    private struct Prompt: Identifiable {
        let number: Int
        var id: Int { number }
    }

    func body(content: Content) -> some View {
        content
            .task { await registerAndEvaluate() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await registerAndEvaluate() }
            }
            .onChange(of: router.pendingIntent, initial: true) {
                // DEBUG routes / screenshots: `supporter-prompt/<number>`.
                if let intent = router.consumeIntent("supporter-prompt/") {
                    prompt = Prompt(number: Int(intent.split(separator: "/").last ?? "") ?? 1)
                }
            }
            .sheet(item: $prompt) { prompt in
                SupporterView(context: .prompt(number: prompt.number))
            }
    }

    private func registerAndEvaluate() async {
        var ledger = SupporterPromptLedger.load()
        ledger.registerUsageDay()
        ledger.save()

        // Never pops up mid-launch; if the user starts cooking or opens a sheet meanwhile,
        // skip and try again on another activation.
        try? await Task.sleep(for: .seconds(2))
        // `hasResolvedEntitlements`: a supporter on a fresh install isn't known until StoreKit
        // has answered.
        guard !Task.isCancelled, scenePhase == .active, prompt == nil, store.hasResolvedEntitlements,
              router.presentedDestination == nil, !router.isSettingsPresented,
              !Self.isPresentingAnything,
              SupporterPromptGate.shouldShow(ledger: ledger, isSupporter: store.isSupporter) else { return }

        ledger.registerPrompt()
        ledger.save()
        prompt = Prompt(number: ledger.promptCount)
    }

    /// Anything presented over the root view controller: sheets, full-screen covers, alerts.
    private static var isPresentingAnything: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}

extension View {
    func supporterPromptPresenter() -> some View {
        modifier(SupporterPromptPresenter())
    }
}
