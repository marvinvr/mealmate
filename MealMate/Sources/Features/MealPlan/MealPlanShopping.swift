import Foundation

/// Rules for "Add to Shopping List" from the meal plan (unit tested): which planned meals are
/// offered, which start ticked, and how the ticked ones become Mealie's request.
enum MealPlanShopping {
    /// A day with its planned recipes, in meal order.
    struct Day: Hashable, Identifiable {
        let day: MealieDay
        let entries: [MealPlanEntry]
        var id: MealieDay { day }
    }

    /// The recipe id an entry plans, `nil` for notes.
    static func recipeID(of entry: MealPlanEntry) -> String? {
        entry.recipeId ?? entry.recipe?.id
    }

    /// The week's planned recipes grouped by day (days without recipes are left out; notes
    /// are never offered), days in order, entries in meal order.
    static func days(_ entries: [MealPlanEntry], in week: MealPlanWeek) -> [Day] {
        let byDay = MealPlanLayout.entriesByDay(entries.filter { recipeID(of: $0) != nil }, in: week)
        return week.days.compactMap { day in
            guard let entries = byDay[day], !entries.isEmpty else { return nil }
            return Day(day: day, entries: entries)
        }
    }

    /// Entry ids that start ticked: only `day`'s meals when shopping for one day, otherwise
    /// today's and later ones (past meals are likely eaten already).
    static func defaultSelection(_ days: [Day], today: MealieDay, only day: MealieDay? = nil) -> Set<Int> {
        Set(days
            .filter { candidate in
                if let day { return candidate.day == day }
                return candidate.day >= today
            }
            .flatMap(\.entries)
            .map(\.id))
    }

    /// One request per recipe, in plan order. A recipe planned several times is added once
    /// with its count as the scale: Mealie would merge the items anyway, and the list then
    /// shows the recipe once ("×2") instead of twice.
    static func requests(for entries: [MealPlanEntry]) -> [ShoppingListAddRecipe] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let id = recipeID(of: entry) else { continue }
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        return order.map { ShoppingListAddRecipe(recipeId: $0, recipeIncrementQuantity: Double(counts[$0] ?? 1)) }
    }
}
