import Foundation
import Testing
@testable import MealMate

// MARK: - Fractions & scaling

struct QuantityFormattingTests {
    private let locale = Locale(identifier: "en_US")

    private static let fractionCases: [(Double, String)] = [
        (1.0, "1"), (2.0, "2"), (0.5, "½"), (1.5, "1½"), (0.25, "¼"), (0.75, "¾"),
        (1.0 / 3, "⅓"), (2.0 / 3, "⅔"), (2.0 + 1.0 / 3, "2⅓"), (0.125, "⅛"),
        (1.999, "2"), (3.01, "3"), (250, "250"), (1200, "1200"), (33.3333, "33"),
    ]

    @Test(arguments: fractionCases)
    func formatsCommonFractions(_ value: Double, _ expected: String) {
        #expect(IngredientFormatting.quantity(value, locale: locale) == expected)
    }

    @Test func decimalsWhenNotAFractionOrFractionsDisabled() {
        #expect(IngredientFormatting.quantity(0.15, locale: locale) == "0.15")
        #expect(IngredientFormatting.quantity(1.5, useFractions: false, locale: locale) == "1.5")
        #expect(IngredientFormatting.quantity(2.7, locale: locale) == "2.7")
    }

    @Test func zeroAndInvalidAreEmpty() {
        #expect(IngredientFormatting.quantity(0) == "")
        #expect(IngredientFormatting.quantity(-1) == "")
        #expect(IngredientFormatting.quantity(.nan) == "")
    }

    @Test func scaleFromServings() {
        #expect(IngredientFormatting.scale(servings: 8, baseServings: 4) == 2)
        #expect(IngredientFormatting.scale(servings: 2, baseServings: 4) == 0.5)
        #expect(IngredientFormatting.scale(servings: 3, baseServings: nil) == 1)
        #expect(IngredientFormatting.scale(servings: 3, baseServings: 0) == 1)
    }
}

// MARK: - Ingredient display

struct IngredientDisplayTests {
    private let cup = IngredientUnit(id: "u1", name: "cup", pluralName: "cups", abbreviation: "c", useAbbreviation: false, fraction: true)
    private let gram = IngredientUnit(id: "u2", name: "gram", pluralName: "grams", abbreviation: "g", useAbbreviation: true, fraction: true)
    private let flour = IngredientFood(id: "f1", name: "flour")
    private let egg = IngredientFood(id: "f2", name: "egg", pluralName: "eggs")

    @Test func parsedIngredientScalesAndPluralizes() {
        let ingredient = RecipeIngredient(quantity: 1, unit: cup, food: flour, note: "sifted", display: "1 cup flour sifted")
        #expect(IngredientFormatting.text(for: ingredient) == "1 cup flour sifted")
        #expect(IngredientFormatting.text(for: ingredient, scale: 1.5) == "1½ cups flour sifted")
        #expect(IngredientFormatting.text(for: ingredient, scale: 0.5) == "½ cup flour sifted")
        let parts = IngredientFormatting.parts(for: ingredient, scale: 2)
        #expect(parts.amount == "2 cups")
        #expect(parts.food == "flour")
        #expect(parts.note == "sifted")
        #expect(parts.isScaled)
    }

    @Test func abbreviationWhenConfigured() {
        let ingredient = RecipeIngredient(quantity: 250, unit: gram, food: flour)
        #expect(IngredientFormatting.text(for: ingredient, scale: 2) == "500 g flour")
    }

    @Test func countedFoodUsesPluralName() {
        let one = RecipeIngredient(quantity: 1, food: egg)
        #expect(IngredientFormatting.text(for: one) == "1 egg")
        #expect(IngredientFormatting.text(for: one, scale: 3) == "3 eggs")
    }

    @Test func foodWithoutQuantity() {
        let salt = RecipeIngredient(quantity: 0, food: IngredientFood(id: "f3", name: "salt"), note: "to taste")
        #expect(IngredientFormatting.text(for: salt, scale: 2) == "salt to taste")
        #expect(IngredientFormatting.parts(for: salt, scale: 2).isScaled == false)
    }

    @Test func unparsedIngredientIsShownAsIsAndNeverScaled() {
        let line = RecipeIngredient(quantity: 1, note: "2 tbsp olive oil", display: "1 2 tbsp olive oil")
        #expect(IngredientFormatting.isParsed(line) == false)
        #expect(IngredientFormatting.text(for: line, scale: 3) == "1 2 tbsp olive oil")

        let noteOnly = RecipeIngredient(note: "A handful of basil")
        #expect(IngredientFormatting.text(for: noteOnly, scale: 2) == "A handful of basil")

        let original = RecipeIngredient(originalText: "1 pinch nutmeg")
        #expect(IngredientFormatting.text(for: original) == "1 pinch nutmeg")
    }

    @Test func sectionsStartAtTitledItems() {
        let items = [
            RecipeIngredient(note: "a", title: "Dough"), RecipeIngredient(note: "b"),
            RecipeIngredient(note: "c", title: "Sauce"), RecipeIngredient(note: "d"),
        ]
        let sections = RecipeSections.ingredients(items)
        #expect(sections.map(\.title) == ["Dough", "Sauce"])
        #expect(sections.map { $0.items.map(\.index) } == [[0, 1], [2, 3]])

        let untitled = RecipeSections.ingredients([RecipeIngredient(note: "x"), RecipeIngredient(note: "y", title: "  ")])
        #expect(untitled.count == 1)
        #expect(untitled[0].title == nil)
    }
}

// MARK: - Durations

struct RecipeDurationTests {
    private static let durationCases: [(String, Int)] = [
        ("45", 45), ("45 minutes", 45), ("45 min", 45), ("1 hour 30 minutes", 90), ("1h 30m", 90),
        ("PT1H30M", 90), ("PT45M", 45), ("P0DT2H", 120), ("1:15", 75), ("1 Stunde 20 Minuten", 80), ("1.5 hours", 90),
    ]

    @Test(arguments: durationCases)
    func parsesCommonFormats(_ text: String, _ minutes: Int) {
        #expect(RecipeFormatting.minutes(from: text) == minutes)
    }

    @Test func unparseableIsKeptAsEntered() {
        #expect(RecipeFormatting.minutes(from: "overnight") == nil)
        #expect(RecipeFormatting.duration("overnight") == "overnight")
        #expect(RecipeFormatting.duration(nil) == nil)
        #expect(RecipeFormatting.duration("  ") == nil)
    }

    @Test func headlineTimeFallsBackToPrepPlusCook() {
        #expect(RecipeFormatting.headlineTime(total: nil, prep: "10 min", cook: "20 min", perform: nil)
            == RecipeFormatting.duration(minutes: 30))
        #expect(RecipeFormatting.headlineTime(total: nil, prep: nil, cook: nil, perform: nil) == nil)
    }
}

// MARK: - Query building

struct RecipeListQueryTests {
    private func items(_ query: RecipeQuery?) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for item in query?.queryItems ?? [] { result[item.name, default: []].append(item.value ?? "") }
        return result
    }

    @Test func defaultQuery() {
        let query = RecipeListQueryBuilder.query(preset: .all, search: "  ", sort: .recentlyAdded, filters: RecipeFilters(), favoriteIDs: [])
        let values = items(query)
        #expect(values["orderBy"] == ["created_at"])
        #expect(values["orderDirection"] == ["desc"])
        #expect(values["search"] == nil)
        #expect(values["page"] == ["1"])
        #expect(values["perPage"] == ["30"])
        #expect(values["paginationSeed"] == nil)
    }

    @Test func searchSortAndFilters() {
        var filters = RecipeFilters()
        filters.toggle(Organizer(id: "c1", name: "Dinner", slug: "dinner"), kind: .category)
        filters.toggle(Organizer(name: "Quick", slug: "quick"), kind: .tag)
        filters.toggle(FoodFilter(id: "f1", name: "Chicken"))
        let query = RecipeListQueryBuilder.query(preset: .all, search: " soup ", sort: .name, filters: filters, favoriteIDs: [], page: 3)
        let values = items(query)
        #expect(values["search"] == ["soup"])
        #expect(values["orderBy"] == ["name"])
        #expect(values["orderDirection"] == ["asc"])
        #expect(values["categories"] == ["c1"])
        #expect(values["tags"] == ["quick"])
        #expect(values["foods"] == ["f1"])
        #expect(values["page"] == ["3"])
        #expect(filters.count == 3)
    }

    @Test func toggleRemovesAgain() {
        var filters = RecipeFilters()
        let tag = Organizer(name: "Quick", slug: "quick")
        filters.toggle(tag, kind: .tag)
        filters.toggle(tag, kind: .tag)
        #expect(filters.isEmpty)
    }

    @Test func ratingAndLastMadeSortNullsLast() {
        let values = items(RecipeListQueryBuilder.query(preset: .all, search: "", sort: .lastMade, filters: RecipeFilters(), favoriteIDs: []))
        #expect(values["orderBy"] == ["last_made"])
        #expect(values["orderByNullPosition"] == ["last"])
    }

    @Test func randomSortUsesStableSeed() {
        let values = items(RecipeListQueryBuilder.query(preset: .all, search: "", sort: .random, filters: RecipeFilters(), favoriteIDs: [], seed: "abc"))
        #expect(values["orderBy"] == ["random"])
        #expect(values["paginationSeed"] == ["abc"])
    }

    @Test func favoritesBecomeAnIDFilter() {
        var filters = RecipeFilters()
        filters.favoritesOnly = true
        let values = items(RecipeListQueryBuilder.query(preset: .all, search: "", sort: .name, filters: filters, favoriteIDs: ["b", "a"]))
        #expect(values["queryFilter"] == [#"id IN ["a","b"]"#])

        #expect(RecipeListQueryBuilder.query(preset: .favorites, search: "", sort: .name, filters: RecipeFilters(), favoriteIDs: []) == nil)
    }

    @Test func presetsApply() {
        let cookbook = items(RecipeListQueryBuilder.query(preset: .cookbook(id: "cb1"), search: "", sort: .name, filters: RecipeFilters(), favoriteIDs: []))
        #expect(cookbook["cookbook"] == ["cb1"])

        var filters = RecipeFilters()
        filters.toggle(Organizer(id: "t2", name: "Vegan", slug: "vegan"), kind: .tag)
        let tag = items(RecipeListQueryBuilder.query(preset: .organizer(.tag, slug: "quick"), search: "", sort: .name, filters: filters, favoriteIDs: []))
        #expect(tag["tags"] == ["quick", "t2"])
        #expect(tag["requireAllTags"] == ["true"])

        let plain = items(RecipeListQueryBuilder.query(preset: .organizer(.tool, slug: "skillet"), search: "", sort: .name, filters: RecipeFilters(), favoriteIDs: []))
        #expect(plain["tools"] == ["skillet"])
        #expect(plain["requireAllTools"] == nil)
    }
}

// MARK: - Links

struct RecipeLinkTests {
    @Test func webURLUsesGroupSlug() {
        let server = URL(string: "https://mealie.example.com/")!
        #expect(RecipeLinks.webURL(server: server, groupSlug: "home", slug: "tomato-soup")?.absoluteString
            == "https://mealie.example.com/g/home/r/tomato-soup")
        #expect(RecipeLinks.webURL(server: server, groupSlug: nil, slug: "tomato-soup")?.absoluteString
            == "https://mealie.example.com/recipe/tomato-soup")
    }

    @Test func publicURLNeedsGroupSlug() {
        let server = URL(string: "https://mealie.example.com/")!
        #expect(RecipeLinks.publicURL(server: server, groupSlug: "home", tokenID: "abc-123")?.absoluteString
            == "https://mealie.example.com/g/home/shared/r/abc-123")
        #expect(RecipeLinks.publicURL(server: server, groupSlug: nil, tokenID: "abc-123") == nil)
    }

    @Test func publicLinkExpiry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(PublicLinkExpiry.day.date(from: now, calendar: calendar).timeIntervalSince(now) == 86_400)
        #expect(PublicLinkExpiry.month.date(from: now, calendar: calendar).timeIntervalSince(now) == 30 * 86_400)
        #expect(PublicLinkExpiry.year.date(from: now, calendar: calendar) > PublicLinkExpiry.month.date(from: now, calendar: calendar))
    }

    @Test func activePublicLinksDropExpiredAndSortByExpiry() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let tokens = [
            RecipeShareToken(id: "soon", recipeId: "r1", expiresAt: now.addingTimeInterval(3_600)),
            RecipeShareToken(id: "expired", recipeId: "r1", expiresAt: now.addingTimeInterval(-60)),
            RecipeShareToken(id: "later", recipeId: "r1", expiresAt: now.addingTimeInterval(86_400)),
        ]
        #expect(RecipePublicLinkModel.active(tokens, now: now).map(\.id) == ["later", "soon"])
    }

    @Test func linkActionPlaceholders() {
        let recipe = Recipe(id: "r1", slug: "tomato-soup", name: "Tomato Soup")
        let url = RecipeActionLink.url(template: "https://example.com/add?u=${url}&s=${slug}&x=${scale}",
                                       recipe: recipe, recipeURL: URL(string: "https://mealie.example.com/g/home/r/tomato-soup"),
                                       scale: 1.5, servings: 6)
        #expect(url?.absoluteString == "https://example.com/add?u=https://mealie.example.com/g/home/r/tomato-soup&s=tomato-soup&x=1.5")
    }

    @Test func plainTextListsScaledIngredientsAndSteps() {
        var recipe = Recipe(id: "r1", slug: "pancakes", name: "Pancakes", recipeServings: 2)
        recipe.recipeIngredient = [RecipeIngredient(quantity: 1, food: IngredientFood(id: "f", name: "egg", pluralName: "eggs"))]
        recipe.recipeInstructions = [RecipeStep(text: "Whisk."), RecipeStep(text: "Fry.")]
        let text = RecipeLinks.plainText(recipe, scale: 2, servings: 4)
        #expect(text.contains("• 2 eggs"))
        #expect(text.contains("1. Whisk."))
        #expect(text.contains("2. Fry."))
        #expect(text.contains("4 servings"))
    }
}

