import Foundation
import Testing
@testable import MealMate

struct CookSuggestionsTests {
    private let eggs = FoodFilter(id: "a0000001-0000-4000-8000-000000000001", name: "eggs")
    private let flour = FoodFilter(id: "a0000002-0000-4000-8000-000000000002", name: "flour")

    private func value(_ items: [URLQueryItem], _ name: String) -> [String] {
        items.filter { $0.name == name }.compactMap(\.value)
    }

    @Test func noSelectionMeansNoQuery() {
        // Mealie would return every recipe with nothing missing.
        #expect(CookSuggestions.query(for: CookPantry()) == nil)
    }

    @Test func queryCarriesFoodsAndOptions() throws {
        let pantry = CookPantry(foods: [eggs, flour], maxMissing: 2, includeOnHand: false)
        let items = try #require(CookSuggestions.query(for: pantry)).queryItems
        #expect(value(items, "foods") == [eggs.id, flour.id])
        #expect(value(items, "tools").isEmpty)
        #expect(value(items, "limit") == ["30"])
        #expect(value(items, "maxMissingFoods") == ["2"])
        #expect(value(items, "maxMissingTools") == ["2"])
        #expect(value(items, "includeFoodsOnHand") == ["false"])
        #expect(value(items, "includeToolsOnHand") == ["false"])
        #expect(value(items, "includeSubstitutions") == ["true"])
    }

    @Test func defaultsCountOnHandFoods() throws {
        let items = try #require(CookSuggestions.query(for: CookPantry(foods: [eggs]))).queryItems
        #expect(value(items, "includeFoodsOnHand") == ["true"])
        #expect(value(items, "maxMissingFoods") == [String(CookSuggestions.defaultAllowance)])
    }

    @Test func keyIgnoresSelectionOrder() {
        let a = CookSuggestions.Key(CookPantry(foods: [eggs, flour]))
        let b = CookSuggestions.Key(CookPantry(foods: [flour, eggs]))
        #expect(a == b)
        #expect(a != CookSuggestions.Key(CookPantry(foods: [eggs, flour], maxMissing: 0)))
    }

    @Test func missingText() {
        #expect(CookSuggestions.missingText([]) == nil)
        #expect(CookSuggestions.missingText(["", " "]) == nil)
        #expect(CookSuggestions.missingText(["flour"]) == "Missing: flour")
        // One more name is listed instead of "+ 1 more".
        #expect(CookSuggestions.missingText(["a", "b", "c", "d"]) == "Missing: a, b, c, d")
        #expect(CookSuggestions.missingText(["a", "b", "c", "d", "e"]) == "Missing: a, b, c + 2 more")
    }

    @Test func missingAndSubstitutionTextForSuggestion() {
        let recipe = RecipeSummary(id: "r", slug: "tomato-soup", name: "Tomato Soup")
        let suggestion = RecipeSuggestion(
            recipe: recipe,
            missingFoods: [IngredientFood(id: "f1", name: "basil")],
            substitutedFoods: [.init(food: IngredientFood(id: "f2", name: "butter"),
                                     substituteFood: IngredientFood(id: "f3", name: "olive oil"))],
            missingTools: [Organizer(id: "t1", name: "Blender", slug: "blender")]
        )
        #expect(CookSuggestions.missingText(for: suggestion) == "Missing: basil, Blender")
        #expect(CookSuggestions.substitutionText(for: suggestion) == "olive oil instead of butter")
        #expect(CookSuggestions.missingText(for: RecipeSuggestion(recipe: recipe)) == nil)
        #expect(CookSuggestions.substitutionText(for: RecipeSuggestion(recipe: recipe)) == nil)
    }

    @Test func allowanceSteps() {
        #expect(CookSuggestions.nextAllowance(after: 0) == 1)
        #expect(CookSuggestions.nextAllowance(after: 3) == 5)
        #expect(CookSuggestions.nextAllowance(after: 5) == nil)
        #expect(CookSuggestions.allowanceTitle(0) == "None")
        #expect(CookSuggestions.allowanceTitle(2) == "Up to 2")
    }

    @Test func preselectionParsingAndMatching() {
        #expect(CookSuggestions.foodNames(from: " eggs, Flour,,") == ["eggs", "Flour"])
        #expect(CookSuggestions.exactMatch(for: "FLOUR", in: [FoodFilter(id: "x", name: "flour tortilla"), flour]) == flour)
        #expect(CookSuggestions.exactMatch(for: "-", in: [eggs, flour]) == nil)
    }

    @Test func pantryPersistsPerKey() throws {
        let suiteName = "CookSuggestionsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = CookPantry.storageKey(scope: "https://mealie.example.com")
        #expect(CookPantry.load(from: defaults, key: key) == CookPantry())
        let pantry = CookPantry(foods: [eggs], maxMissing: 1, includeOnHand: false)
        pantry.save(to: defaults, key: key)
        #expect(CookPantry.load(from: defaults, key: key) == pantry)
        #expect(CookPantry.load(from: defaults, key: CookPantry.storageKey(scope: "http://mealie.local")) == CookPantry())
    }

    @Test func routes() {
        #expect(AppRoute(string: "library-cook") == .intent("library-cook", tab: .library))
        #expect(AppRoute(string: "library-cook/eggs,flour") == .intent("library-cook/eggs,flour", tab: .library))
    }
}
