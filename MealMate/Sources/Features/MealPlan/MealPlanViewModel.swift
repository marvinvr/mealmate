import SwiftUI

/// The meal plan for one week: cached-first loading, add/move/delete with rollback and
/// "Suggest a recipe" (Mealie's random endpoint, which creates a real entry; undo deletes it).
@MainActor
@Observable
final class MealPlanViewModel {
    private(set) var week: MealPlanWeek
    private(set) var entries: [MealPlanEntry] = []
    private(set) var phase: Phase = .loading
    private(set) var refreshError: String?
    var actionError: MealieError?
    /// Confirmation for the last change (with "Undo" for suggestions).
    var toast: ActionToast?
    @ObservationIgnored private(set) var undoableEntry: MealPlanEntry?
    private(set) var successFeedback = 0
    private(set) var errorFeedback = 0
    /// Entry ids whose request is in flight.
    private(set) var busyEntries: Set<Int> = []
    /// Days with a pending "suggest" request.
    private(set) var suggestingDays: Set<MealieDay> = []

    /// Today's meals for the card at the top of the current week (also widget-ready).
    let today = TodayMealsProvider()

    enum Phase: Equatable {
        case loading, loaded
        case failed(MealieError)
    }

    @ObservationIgnored private var mealie: MealieService = .unconfigured
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let calendar: Calendar

    init(week: MealPlanWeek = .current(), calendar: Calendar = .autoupdatingCurrent) {
        self.week = week
        self.calendar = calendar
    }

    var isCurrentWeek: Bool { week.contains(MealieDay(Date(), calendar: calendar)) }
    var isEmpty: Bool { entries.isEmpty }

    var entriesByDay: [MealieDay: [MealPlanEntry]] {
        MealPlanLayout.entriesByDay(entries, in: week)
    }

    private func cacheKey(for week: MealPlanWeek) -> String { "mealplan.week.\(week.start)" }

    // MARK: Loading

    func load(using mealie: MealieService) async {
        self.mealie = mealie
        await today.load(using: mealie)
        await show(week)
    }

    func show(_ week: MealPlanWeek) async {
        loadGeneration += 1
        let generation = loadGeneration
        let changed = week != self.week
        self.week = week
        if changed || entries.isEmpty {
            if let cached = await mealie.cached([MealPlanEntry].self, key: cacheKey(for: week)) {
                guard generation == loadGeneration else { return }
                entries = cached
                phase = .loaded
            } else if changed {
                entries = []
                phase = .loading
            }
        }
        await refresh(generation: generation)
    }

    func showWeek(offset: Int) async {
        await show(week.offset(by: offset, calendar: calendar))
    }

    func showToday() async {
        await show(.current(calendar: calendar))
    }

    func refresh() async {
        await refresh(generation: loadGeneration)
        await today.refresh()
    }

    private func refresh(generation: Int) async {
        let week = week
        do {
            let fresh = try await mealie.mealPlan(from: week.start, to: week.end)
            guard generation == loadGeneration, busyEntries.isEmpty else { return }
            withAnimation(.snappy) { entries = fresh }
            phase = .loaded
            refreshError = nil
            await mealie.storeInCache(fresh, key: cacheKey(for: week))
            if isCurrentWeek { today.update(fromWeek: fresh) }
        } catch {
            let error = MealieError.wrap(error)
            guard error != .cancelled, generation == loadGeneration else { return }
            if phase == .loaded {
                refreshError = error.errorDescription
            } else {
                phase = .failed(error)
            }
        }
    }

    private func persist() {
        let entries = entries
        let key = cacheKey(for: week)
        let mealie = mealie
        Task { await mealie.storeInCache(entries, key: key) }
        if isCurrentWeek { today.update(fromWeek: entries) }
    }

    // MARK: Mutations

    @discardableResult
    func add(_ create: MealPlanEntryCreate) async -> MealPlanEntry? {
        do {
            let entry = try await mealie.createMealPlanEntry(create)
            insert(entry)
            return entry
        } catch {
            fail(error)
            return nil
        }
    }

    /// Inserts an entry created elsewhere (e.g. the add sheet).
    func insert(_ entry: MealPlanEntry) {
        if week.contains(entry.date) {
            withAnimation(.snappy) {
                entries.removeAll { $0.id == entry.id }
                entries.append(entry)
            }
        }
        if entry.date == MealieDay(Date(), calendar: calendar) { today.insert(entry) }
        persist()
    }

    func delete(_ entry: MealPlanEntry) async {
        withAnimation(.snappy) { entries.removeAll { $0.id == entry.id } }
        today.remove(id: entry.id)
        busyEntries.insert(entry.id)
        defer { busyEntries.remove(entry.id) }
        do {
            try await mealie.deleteMealPlanEntry(id: entry.id)
            persist()
        } catch {
            withAnimation(.snappy) { entries.append(entry) }
            if entry.date == MealieDay(Date(), calendar: calendar) { today.insert(entry) }
            fail(error)
        }
    }

    /// Moves an entry to another day and/or meal type.
    func move(_ entry: MealPlanEntry, to day: MealieDay, type: PlanEntryType? = nil) async {
        var updated = entry
        updated.date = day
        if let type { updated.entryType = type }
        await save(updated, original: entry)
    }

    /// Saves an edited entry (date, type, note text, recipe).
    func save(_ updated: MealPlanEntry, original: MealPlanEntry) async {
        guard updated != original, let body = MealPlanEntryUpdate(updated) else { return }
        replaceLocally(updated)
        busyEntries.insert(updated.id)
        defer { busyEntries.remove(updated.id) }
        do {
            var saved = try await mealie.updateMealPlanEntry(body)
            if saved.recipe == nil { saved.recipe = updated.recipe }
            replaceLocally(saved)
            persist()
            if original.date != saved.date {
                toast = ActionToast(message: "Moved to \(saved.date.relativeName(calendar: calendar)), \(saved.date.shortDate)",
                                    systemImage: "calendar")
            }
        } catch {
            replaceLocally(original)
            fail(error)
        }
    }

    private func replaceLocally(_ entry: MealPlanEntry) {
        withAnimation(.snappy) {
            entries.removeAll { $0.id == entry.id }
            if week.contains(entry.date) { entries.append(entry) }
        }
        today.remove(id: entry.id)
        if entry.date == MealieDay(Date(), calendar: calendar) { today.insert(entry) }
    }

    /// "Suggest a recipe": Mealie picks a random recipe (respecting the household's meal
    /// plan rules) and **creates** the entry. The toast offers Undo, which deletes it.
    func suggest(on day: MealieDay, type: PlanEntryType) async {
        suggestingDays.insert(day)
        defer { suggestingDays.remove(day) }
        do {
            let entry = try await mealie.createRandomMealPlanEntry(date: day, entryType: type)
            insert(entry)
            undoableEntry = entry
            successFeedback += 1
            toast = ActionToast(message: "Added \(entry.displayTitle) for \(type.title.lowercased())",
                                systemImage: "sparkles", actionTitle: "Undo", duration: .seconds(6))
        } catch {
            fail(error)
        }
    }

    func undoSuggestion() async {
        guard let entry = undoableEntry else { return }
        undoableEntry = nil
        await delete(entry)
    }

    private func fail(_ error: Error) {
        let error = MealieError.wrap(error)
        guard error != .cancelled else { return }
        actionError = error
        errorFeedback += 1
    }
}
