import Foundation

/// A meal plan entry (`ReadPlanEntry`): either a recipe or a free-text note.
struct MealPlanEntry: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var date: MealieDay
    var entryType: PlanEntryType
    var title: String?
    var text: String?
    var recipeId: String?
    var recipe: RecipeSummary?
    var groupId: String?
    var userId: String?
    var householdId: String?

    var isNote: Bool { recipeId == nil && recipe == nil }
    var displayTitle: String {
        if let recipe { return recipe.displayName }
        if let title, !title.isEmpty { return title }
        return text ?? ""
    }
}

/// Meal slot. Open enum: unknown values from newer servers decode fine.
struct PlanEntryType: OpenStringEnum, Comparable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let breakfast: Self = "breakfast"
    static let lunch: Self = "lunch"
    static let dinner: Self = "dinner"
    static let side: Self = "side"
    static let snack: Self = "snack"
    static let drink: Self = "drink"
    static let dessert: Self = "dessert"

    static let allKnown: [PlanEntryType] = [.breakfast, .lunch, .dinner, .side, .snack, .drink, .dessert]

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .side: "Side"
        case .snack: "Snack"
        case .drink: "Drink"
        case .dessert: "Dessert"
        default: rawValue.capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .side: "carrot"
        case .snack: "takeoutbag.and.cup.and.straw"
        case .drink: "cup.and.saucer"
        case .dessert: "birthday.cake"
        default: "fork.knife"
        }
    }

    /// Day order: breakfast → dessert, unknown values last.
    static func < (lhs: PlanEntryType, rhs: PlanEntryType) -> Bool {
        let order = { (type: PlanEntryType) in allKnown.firstIndex(of: type) ?? allKnown.count }
        return order(lhs) < order(rhs)
    }
}

/// Body of `POST /api/households/mealplans`. Set `recipeId` for a recipe, or `title`/`text` for a note.
struct MealPlanEntryCreate: Codable, Hashable, Sendable {
    var date: MealieDay
    var entryType: PlanEntryType = .dinner
    var title: String = ""
    var text: String = ""
    var recipeId: String?
}

/// Body of `PUT /api/households/mealplans/{id}`.
struct MealPlanEntryUpdate: Codable, Hashable, Sendable {
    var id: Int
    var date: MealieDay
    var entryType: PlanEntryType
    var title: String
    var text: String
    var recipeId: String?
    var groupId: String
    var userId: String

    init?(_ entry: MealPlanEntry) {
        guard let groupId = entry.groupId, let userId = entry.userId else { return nil }
        id = entry.id
        date = entry.date
        entryType = entry.entryType
        title = entry.title ?? ""
        text = entry.text ?? ""
        recipeId = entry.recipeId
        self.groupId = groupId
        self.userId = userId
    }
}

/// Body of `POST /api/households/mealplans/random` (creates an entry with a random recipe).
struct MealPlanRandomRequest: Codable, Hashable, Sendable {
    var date: MealieDay
    var entryType: PlanEntryType = .dinner
}
