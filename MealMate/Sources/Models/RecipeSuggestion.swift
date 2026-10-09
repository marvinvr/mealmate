import Foundation

// MARK: - Response

/// `RecipeSuggestionResponse`: `GET /api/recipes/suggestions`.
struct RecipeSuggestionResponse: Codable, Hashable, Sendable {
    var items: [RecipeSuggestion]

    init(items: [RecipeSuggestion]) { self.items = items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.decodeLossyArrayIfPresent([RecipeSuggestion].self, forKey: .items) ?? []
    }
}

/// One suggested recipe with what the user still needs for it (`RecipeSuggestionResponseItem`).
/// Foods/tools the household marked as on hand are never reported missing (when included).
struct RecipeSuggestion: Codable, Hashable, Identifiable, Sendable {
    var recipe: RecipeSummary
    var missingFoods: [IngredientFood]
    /// Foods the recipe calls for that are covered by a substitute the user has.
    var substitutedFoods: [SubstitutedFood]
    var missingTools: [RecipeTool]

    var id: String { recipe.id }

    /// `RecipeSuggestionSubstitutedFood`: `substituteFood` (which the user has) stands in for `food`.
    struct SubstitutedFood: Codable, Hashable, Sendable {
        var food: IngredientFood
        /// `IngredientFoodSummary` (id, name, pluralName) on the server; decodes as a food.
        var substituteFood: IngredientFood
    }

    init(recipe: RecipeSummary, missingFoods: [IngredientFood] = [], substitutedFoods: [SubstitutedFood] = [], missingTools: [RecipeTool] = []) {
        self.recipe = recipe
        self.missingFoods = missingFoods
        self.substitutedFoods = substitutedFoods
        self.missingTools = missingTools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipe = try container.decode(RecipeSummary.self, forKey: .recipe)
        missingFoods = container.decodeLossyArrayIfPresent([IngredientFood].self, forKey: .missingFoods) ?? []
        substitutedFoods = container.decodeLossyArrayIfPresent([SubstitutedFood].self, forKey: .substitutedFoods) ?? []
        missingTools = container.decodeLossyArrayIfPresent([RecipeTool].self, forKey: .missingTools) ?? []
    }
}

// MARK: - Request

/// Query for `GET /api/recipes/suggestions`. Mealie matches recipes by their ingredients'
/// linked foods (parsed ingredients only), fewest missing first.
///
/// Quirk: with no foods and no tools the server applies no matching at all and returns
/// every recipe with empty missing lists, so only send a query with a selection.
struct RecipeSuggestionQuery: Sendable, Hashable {
    /// Food IDs the user has.
    var foods: [String] = []
    /// Tool IDs the user has.
    var tools: [String] = []
    var limit = 10
    var maxMissingFoods = 5
    var maxMissingTools = 5
    /// Also count foods/tools the household marked as on hand in Mealie.
    var includeFoodsOnHand = true
    var includeToolsOnHand = true
    var includeSubstitutions = true

    var queryItems: [URLQueryItem] {
        var items = foods.map { URLQueryItem(name: "foods", value: $0) }
        items += tools.map { URLQueryItem(name: "tools", value: $0) }
        items += [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "maxMissingFoods", value: String(maxMissingFoods)),
            URLQueryItem(name: "maxMissingTools", value: String(maxMissingTools)),
            URLQueryItem(name: "includeFoodsOnHand", value: includeFoodsOnHand ? "true" : "false"),
            URLQueryItem(name: "includeToolsOnHand", value: includeToolsOnHand ? "true" : "false"),
            URLQueryItem(name: "includeSubstitutions", value: includeSubstitutions ? "true" : "false"),
        ]
        return items
    }
}
