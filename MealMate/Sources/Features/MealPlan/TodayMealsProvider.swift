import SwiftUI

/// Today's meal plan entries, cached-first. Small and self-contained so a future widget
/// (or any other screen) can reuse it: `await provider.load(using: mealie)`.
///
/// "Today" is the device's local day (the request asks for that date range rather than
/// `/mealplans/today`, which uses the server's time zone).
@MainActor
@Observable
final class TodayMealsProvider {
    private(set) var day: MealieDay
    private(set) var entries: [MealPlanEntry] = []
    private(set) var isLoaded = false

    @ObservationIgnored private var mealie: MealieService = .unconfigured
    @ObservationIgnored private let calendar: Calendar

    static let cacheKey = "mealplan.today"

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        day = MealieDay(Date(), calendar: calendar)
    }

    func load(using mealie: MealieService) async {
        self.mealie = mealie
        if !isLoaded, let cached = await mealie.cached(Snapshot.self, key: Self.cacheKey), cached.day == currentDay {
            entries = cached.entries
            isLoaded = true
        }
        await refresh()
    }

    func refresh() async {
        day = currentDay
        do {
            let fresh = try await mealie.mealPlan(from: day, to: day)
            set(fresh)
        } catch {
            // Keep what's shown; the meal plan screen reports errors.
        }
    }

    /// Feed from an already loaded week (saves a request).
    func update(fromWeek weekEntries: [MealPlanEntry]) {
        day = currentDay
        set(weekEntries.filter { $0.date == day })
    }

    func insert(_ entry: MealPlanEntry) {
        guard entry.date == day else { return }
        set(entries.filter { $0.id != entry.id } + [entry])
    }

    func remove(id: Int) {
        guard entries.contains(where: { $0.id == id }) else { return }
        set(entries.filter { $0.id != id })
    }

    private func set(_ new: [MealPlanEntry]) {
        let sorted = MealPlanLayout.sorted(new)
        if sorted != entries {
            withAnimation(.snappy) { entries = sorted }
        }
        isLoaded = true
        let snapshot = Snapshot(day: day, entries: sorted)
        let mealie = mealie
        Task { await mealie.storeInCache(snapshot, key: Self.cacheKey) }
    }

    private var currentDay: MealieDay { MealieDay(Date(), calendar: calendar) }

    private struct Snapshot: Codable, Sendable {
        var day: MealieDay
        var entries: [MealPlanEntry]
    }
}
