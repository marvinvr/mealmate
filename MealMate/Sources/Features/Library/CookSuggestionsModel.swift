import Foundation
import Observation

/// "What Can I Cook?": the foods the user has (a small per-server pantry kept on this
/// device), options, and Mealie's recipe suggestions for them.
@MainActor
@Observable
final class CookSuggestionsModel {
    /// Saved selection and options (persisted per server in UserDefaults).
    var pantry: CookPantry {
        didSet { if pantry != oldValue { save() } }
    }

    /// Text in the food search field.
    var foodSearch = ""
    /// Server results for `foodSearch` (search-first: empty until the user types).
    private(set) var foodResults: [FoodFilter] = []
    private(set) var isSearchingFoods = false

    private(set) var suggestions: [RecipeSuggestion] = []
    /// The selection `suggestions` belong to (differs from `key` while a change loads).
    private(set) var resultsKey: CookSuggestions.Key?
    private(set) var isLoading = false
    /// Set once results (or cache) for the current selection arrived.
    private(set) var hasLoaded = false
    /// Loading failed and there is nothing to show.
    private(set) var loadError: String?
    /// A refresh failed while earlier results are shown.
    private(set) var refreshError: String?

    @ObservationIgnored private let mealie: MealieService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastKey: CookSuggestions.Key?
    private static let cacheKey = "recipes.suggestions"

    init(mealie: MealieService, defaults: UserDefaults = .standard) {
        self.mealie = mealie
        self.defaults = defaults
        storageKey = CookPantry.storageKey(scope: mealie.cacheScope)
        pantry = CookPantry.load(from: defaults, key: storageKey)
    }

    /// Everything that changes the results; drive `.task(id:)` with it.
    var key: CookSuggestions.Key { CookSuggestions.Key(pantry) }

    var hasSelection: Bool { !pantry.foods.isEmpty }

    /// Results are being fetched for a new selection and there is nothing to show yet.
    var isWaitingForResults: Bool {
        hasSelection && suggestions.isEmpty && loadError == nil && (isLoading || resultsKey != key)
    }

    /// Selected foods first (they stay visible while searching), then search results.
    var shownFoods: [FoodFilter] {
        let ids = Set(pantry.foods.map(\.id))
        return pantry.foods + foodResults.filter { !ids.contains($0.id) }
    }

    func isSelected(_ food: FoodFilter) -> Bool { pantry.foods.contains { $0.id == food.id } }

    func toggle(_ food: FoodFilter) {
        if let index = pantry.foods.firstIndex(where: { $0.id == food.id }) {
            pantry.foods.remove(at: index)
        } else {
            pantry.foods.append(food)
        }
    }

    func clearFoods() { pantry.foods = [] }

    /// The "allow more missing" step after the current one (`nil` at the maximum).
    var nextMissingAllowance: Int? { CookSuggestions.nextAllowance(after: pantry.maxMissing) }

    func allowMoreMissing() {
        if let next = nextMissingAllowance { pantry.maxMissing = next }
    }

    // MARK: Loading

    /// Reloads for the current key; debounces quick successive changes (tapping chips).
    func keyChanged() async {
        let key = self.key
        if lastKey != nil, lastKey != key {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
        }
        lastKey = key
        await reload()
    }

    func reload() async {
        generation += 1
        let generation = self.generation
        let key = self.key
        loadError = nil

        guard let query = CookSuggestions.query(for: pantry) else {
            suggestions = []
            resultsKey = key
            refreshError = nil
            hasLoaded = true
            return
        }

        if !hasLoaded, suggestions.isEmpty,
           let cached = await mealie.cached(CookSuggestions.Cached.self, key: Self.cacheKey), cached.key == key {
            suggestions = cached.items
            resultsKey = key
            hasLoaded = true
        }

        isLoading = true
        defer { if generation == self.generation { isLoading = false } }
        do {
            let items = try await mealie.recipeSuggestions(query)
            guard generation == self.generation else { return }
            suggestions = items
            resultsKey = key
            hasLoaded = true
            refreshError = nil
            await mealie.storeInCache(CookSuggestions.Cached(key: key, items: items), key: Self.cacheKey)
        } catch {
            let error = MealieError.wrap(error)
            guard !error.isCancelled, generation == self.generation else { return }
            if suggestions.isEmpty || resultsKey != key {
                // Don't leave results for another selection on screen.
                suggestions = []
                resultsKey = key
                loadError = error.errorDescription
            } else {
                refreshError = error.errorDescription
            }
            hasLoaded = true
        }
    }

    /// Food search with a 250 ms debounce; call from `.task(id: foodSearch)`.
    func searchFoods() async {
        let text = foodSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            foodResults = []
            isSearchingFoods = false
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        isSearchingFoods = true
        defer { isSearchingFoods = false }
        guard let page = try? await mealie.foods(search: text, perPage: 24), !Task.isCancelled else { return }
        foodResults = page.items.compactMap(FoodFilter.init)
    }

    /// Debug route / deep link `library-cook/<names>`: replaces the selection with the foods
    /// named exactly (comma separated), looked up on the server; unknown names are skipped
    /// (so `library-cook/-` starts empty).
    func preselect(_ list: String) async {
        var selected: [FoodFilter] = []
        for name in CookSuggestions.foodNames(from: list) {
            guard let page = try? await mealie.foods(search: name, perPage: 24) else { continue }
            let candidates = page.items.compactMap(FoodFilter.init)
            if let food = CookSuggestions.exactMatch(for: name, in: candidates), !selected.contains(food) {
                selected.append(food)
            }
        }
        pantry.foods = selected
    }

    private func save() {
        pantry.save(to: defaults, key: storageKey)
    }
}

// MARK: - Pantry

/// What the user has and how strict the matching is. Stored per server on this device.
struct CookPantry: Codable, Hashable, Sendable {
    var foods: [FoodFilter] = []
    /// How many ingredients a suggested recipe may still be missing.
    var maxMissing = CookSuggestions.defaultAllowance
    /// Count foods (and tools) the household marked as on hand in Mealie.
    var includeOnHand = true

    static func storageKey(scope: String) -> String { "cook.pantry.\(scope)" }

    static func load(from defaults: UserDefaults, key: String) -> CookPantry {
        guard let data = defaults.data(forKey: key),
              let pantry = try? JSONDecoder().decode(CookPantry.self, from: data) else { return CookPantry() }
        return pantry
    }

    func save(to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension FoodFilter {
    init?(_ food: IngredientFood) {
        guard let id = food.id else { return nil }
        self.init(id: id, name: food.name)
    }
}

// MARK: - Pure logic (unit tested)

enum CookSuggestions {
    /// Choices for "missing ingredients allowed".
    static let allowances = [0, 1, 2, 3, 5]
    static let defaultAllowance = 3
    static let limit = 30

    struct Key: Hashable, Codable, Sendable {
        var foodIDs: [String]
        var maxMissing: Int
        var includeOnHand: Bool

        init(_ pantry: CookPantry) {
            foodIDs = pantry.foods.map(\.id).sorted()
            maxMissing = pantry.maxMissing
            includeOnHand = pantry.includeOnHand
        }
    }

    /// Last results, shown instantly when the screen opens with the same selection.
    struct Cached: Codable, Sendable {
        var key: Key
        var items: [RecipeSuggestion]
    }

    /// `nil` without a selection: Mealie would return every recipe as "nothing missing".
    static func query(for pantry: CookPantry, limit: Int = limit) -> RecipeSuggestionQuery? {
        guard !pantry.foods.isEmpty else { return nil }
        var query = RecipeSuggestionQuery()
        query.foods = pantry.foods.map(\.id)
        query.limit = limit
        query.maxMissingFoods = max(0, pantry.maxMissing)
        query.maxMissingTools = max(0, pantry.maxMissing)
        query.includeFoodsOnHand = pantry.includeOnHand
        query.includeToolsOnHand = pantry.includeOnHand
        query.includeSubstitutions = true
        return query
    }

    static func nextAllowance(after current: Int) -> Int? {
        allowances.first { $0 > current }
    }

    static func allowanceTitle(_ value: Int) -> String {
        value == 0 ? "None" : "Up to \(value)"
    }

    /// "Missing: Parmesan, basil, Blender" or "Missing: A, B, C + 2 more" (`nil` = nothing missing).
    static func missingText(_ names: [String], shown: Int = 3) -> String? {
        let names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        // Listing one more name is shorter than "+ 1 more".
        guard names.count > shown + 1 else { return "Missing: " + names.joined(separator: ", ") }
        return "Missing: " + names.prefix(shown).joined(separator: ", ") + " + \(names.count - shown) more"
    }

    static func missingText(for suggestion: RecipeSuggestion) -> String? {
        missingText(suggestion.missingFoods.map(\.name) + suggestion.missingTools.map(\.name))
    }

    /// "olive oil instead of butter" (several joined with commas).
    static func substitutionText(for suggestion: RecipeSuggestion) -> String? {
        let parts = suggestion.substitutedFoods.map { "\($0.substituteFood.name) instead of \($0.food.name)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// `"Ei, Mehl,,Pecorino"` → `["Ei", "Mehl", "Pecorino"]`.
    static func foodNames(from list: String) -> [String] {
        list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The food named exactly `name` (ignoring case and diacritics), so a route is predictable.
    static func exactMatch(for name: String, in foods: [FoodFilter]) -> FoodFilter? {
        foods.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
}
