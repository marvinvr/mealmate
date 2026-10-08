import Foundation

/// A calendar week of `MealieDay`s starting on the locale's first weekday (unit tested).
///
/// Built on whole days (`MealieDay`), never on "start date + 7 × 24 h", so daylight
/// saving changes can't shift or drop a day.
struct MealPlanWeek: Hashable, Sendable {
    let days: [MealieDay]

    var start: MealieDay { days[0] }
    var end: MealieDay { days[days.count - 1] }

    /// The week containing `day`, starting on `calendar.firstWeekday`.
    init(containing day: MealieDay, calendar: Calendar = .autoupdatingCurrent) {
        let date = day.date(calendar: calendar)
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = day.adding(days: -offset, calendar: calendar)
        days = (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    static func current(calendar: Calendar = .autoupdatingCurrent) -> MealPlanWeek {
        MealPlanWeek(containing: MealieDay(Date(), calendar: calendar), calendar: calendar)
    }

    func offset(by weeks: Int, calendar: Calendar = .autoupdatingCurrent) -> MealPlanWeek {
        MealPlanWeek(containing: start.adding(days: 7 * weeks, calendar: calendar), calendar: calendar)
    }

    func contains(_ day: MealieDay) -> Bool {
        start <= day && day <= end
    }

    /// "Oct 5 – 11", "Sep 28 – Oct 4", "Dec 28, 2026 – Jan 3, 2027" (year only when it isn't
    /// the current one or the week spans two years).
    func title(calendar: Calendar = .autoupdatingCurrent, today: MealieDay = .today) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        let showsYear = start.year != end.year || start.year != today.year
        formatter.dateTemplate = showsYear ? "MMMdy" : "MMMd"
        return formatter.string(from: start.date(calendar: calendar), to: end.date(calendar: calendar))
    }
}

/// Meal plan presentation rules (unit tested).
enum MealPlanLayout {
    /// A day's entries in meal order (breakfast → dessert, unknown types last), then by
    /// creation (`id`).
    static func sorted(_ entries: [MealPlanEntry]) -> [MealPlanEntry] {
        entries.sorted { lhs, rhs in
            if lhs.entryType != rhs.entryType { return lhs.entryType < rhs.entryType }
            return lhs.id < rhs.id
        }
    }

    /// Entries grouped by day for every day of `week` (days without entries map to `[]`).
    static func entriesByDay(_ entries: [MealPlanEntry], in week: MealPlanWeek) -> [MealieDay: [MealPlanEntry]] {
        var result = Dictionary(uniqueKeysWithValues: week.days.map { ($0, [MealPlanEntry]()) })
        for entry in entries where week.contains(entry.date) {
            result[entry.date, default: []].append(entry)
        }
        return result.mapValues(sorted)
    }

    /// Meal types offered when adding: the ones Mealie knows, in day order.
    static let mealTypes: [PlanEntryType] = PlanEntryType.allKnown

    /// Best default meal type for a new entry at `date` (the next meal of the day for today).
    static func suggestedMealType(for day: MealieDay, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> PlanEntryType {
        guard day == MealieDay(now, calendar: calendar) else { return .dinner }
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case ..<10: return .breakfast
        case ..<14: return .lunch
        default: return .dinner
        }
    }
}

extension MealieDay {
    /// "Monday", "Today", "Tomorrow" style relative name plus "Oct 5".
    func relativeName(today: MealieDay = .today, calendar: Calendar = .autoupdatingCurrent) -> String {
        if self == today { return "Today" }
        if self == today.adding(days: 1, calendar: calendar) { return "Tomorrow" }
        if self == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        return date(calendar: calendar).formatted(.dateTime.weekday(.wide))
    }

    var shortDate: String {
        date().formatted(.dateTime.month(.abbreviated).day())
    }
}
