import Foundation
import Testing
@testable import MealMate

/// Editor ↔ recipe mapping: editing must never drop data the editor doesn't show.
struct RecipeDraftMappingTests {
    /// The recorded fixture plus the fields that are easy to lose on a round trip.
    private func recipe() throws -> Recipe {
        var recipe = try Fixture.decode(Recipe.self, from: "recipe-full")
        recipe.recipeInstructions?[1].ingredientReferences = [.init(referenceId: "a0000014-0000-4000-8000-000000000014")]
        recipe.nutrition = Nutrition(calories: "420", proteinContent: "31 g")
        recipe.extras = ["source": .string("cookbook")]
        recipe.settings?.showNutrition = true
        recipe.tags = [Organizer(id: "t1", name: "Weeknight", slug: "weeknight")]
        recipe.recipeCategory = [Organizer(id: "c1", name: "Dinner", slug: "dinner")]
        recipe.notes = [RecipeNote(title: "Tip", text: "Marinate overnight.", referenceId: "n1")]
        recipe.prepTime = "15 minutes"
        recipe.orgURL = "https://example.com/lemon-herb-chicken"
        return recipe
    }

    private func encodedKeys(_ patch: RecipePatch) throws -> Set<String> {
        let data = try MealieJSON.encoder.encode(patch)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    @Test func unchangedDraftProducesEmptyPatch() throws {
        let recipe = try recipe()
        let patch = RecipeDraft(recipe: recipe).patch(against: recipe)
        #expect(patch.isEmpty, "unexpected fields: \(patch.fieldNames)")
        #expect(try encodedKeys(patch).isEmpty)
    }

    @Test func editingDescriptionSendsOnlyDescription() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.description = "  Bright and quick.  "
        let patch = draft.patch(against: recipe)
        #expect(patch.fieldNames == ["description"])
        #expect(try encodedKeys(patch) == ["description"])
        #expect(patch.description == .some("Bright and quick."))

        let merged = patch.applied(to: recipe)
        #expect(merged.nutrition == recipe.nutrition)
        #expect(merged.settings == recipe.settings)
        #expect(merged.extras == recipe.extras)
        #expect(merged.recipeIngredient == recipe.recipeIngredient)
        #expect(merged.recipeInstructions == recipe.recipeInstructions)
        #expect(merged.tools == recipe.tools)
        #expect(merged.assets == recipe.assets)
    }

    @Test func clearingATimeSendsExplicitNull() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.prepTime = "   "
        let patch = draft.patch(against: recipe)
        #expect(patch.fieldNames == ["prepTime"])
        let json = String(decoding: try MealieJSON.encoder.encode(patch), as: UTF8.self)
        #expect(json.contains("\"prepTime\":null"))
    }

    @Test func editingOneIngredientKeepsTheOthersVerbatim() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.ingredients[2].text = "2 cans crushed tomatoes"
        let patch = draft.patch(against: recipe)
        #expect(patch.fieldNames == ["recipeIngredient"])

        let output = try #require(patch.recipeIngredient)
        let original = recipe.ingredients
        #expect(output.count == original.count)
        #expect(output[0] == original[0])
        #expect(output[1] == original[1])
        #expect(output[3] == original[3])
        // The edited line keeps its identity and section header.
        #expect(output[2].referenceId == original[2].referenceId)
        #expect(output[2].title == "Sauce")
        #expect(output[2].note == "2 cans crushed tomatoes")
        #expect(output[2].food == nil)
    }

    @Test func reorderingIngredientsKeepsTheirObjects() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.ingredients.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let output = try #require(draft.patch(against: recipe).recipeIngredient)
        #expect(Set(output.compactMap(\.referenceId)) == Set(recipe.ingredients.compactMap(\.referenceId)))
        #expect(output[0].food == recipe.ingredients[3].food)
    }

    @Test func parsedIngredientIsUsedForEditedLines() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        #expect(draft.parsesIngredients, "recipes with structured ingredients parse edits by default")
        draft.ingredients[3].text = "400 g chicken thighs"
        #expect(draft.ingredientTextsToParse == ["400 g chicken thighs"])

        let gram = IngredientUnit(id: "u-gram", name: "gram")
        let chicken = IngredientFood(id: "f-chicken", name: "Chicken thighs")
        let parsed = RecipeIngredient(quantity: 400, unit: gram, food: chicken, note: "", display: "400 gram Chicken thighs")
        let output = try #require(draft.patch(against: recipe, parsedIngredients: ["400 g chicken thighs": parsed]).recipeIngredient)
        #expect(output[3].quantity == 400)
        #expect(output[3].food?.id == "f-chicken")
        #expect(output[3].referenceId == recipe.ingredients[3].referenceId)
        #expect(output[3].originalText == "400 g chicken thighs")
    }

    @Test func editingAStepKeepsItsReferences() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.steps[1].text = "Sear the chicken, then add the sauce."
        let patch = draft.patch(against: recipe)
        #expect(patch.fieldNames == ["recipeInstructions"])
        let step = try #require(patch.recipeInstructions?[1])
        #expect(step.id == recipe.instructions[1].id)
        #expect(step.ingredientReferences == recipe.instructions[1].ingredientReferences)
        #expect(step.text == "Sear the chicken, then add the sauce.")
        #expect(patch.recipeInstructions?[0] == recipe.instructions[0])
    }

    @Test func emptyLinesAreDropped() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.ingredients.append(.init(text: "   "))
        draft.steps.append(.init(text: ""))
        draft.notes.append(.init())
        #expect(draft.patch(against: recipe).isEmpty)
    }

    @Test func organizersAndSourceRoundTrip() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        draft.tags.append(Organizer(id: "t2", name: "Grill", slug: "grill"))
        draft.sourceURL = ""
        let patch = draft.patch(against: recipe)
        #expect(Set(patch.fieldNames) == ["tags", "orgURL"])
        #expect(patch.tags?.map(\.slug) == ["weeknight", "grill"])
        #expect(patch.orgURL == .some(nil))
    }

    @Test func cookTimeMapsToPerformTime() throws {
        var recipe = try recipe()
        recipe.performTime = "1 hour"
        var draft = RecipeDraft(recipe: recipe)
        #expect(draft.cookTime == "1 hour")
        draft.cookTime = "45 minutes"
        let patch = draft.patch(against: recipe)
        #expect(patch.fieldNames == ["performTime"])
        #expect(patch.performTime == .some("45 minutes"))
    }

    @Test func newRecipeReplacesServerDefaults() {
        var draft = RecipeDraft()
        draft.name = "MealMate Test Soup"
        draft.ingredients = [.init(text: "1 onion"), .init(text: "")]
        draft.steps = [.init(text: "Chop the onion.")]
        let patch = draft.patch(against: nil)
        // Mealie seeds new recipes with a sample ingredient and step: always overwrite them.
        #expect(patch.recipeIngredient?.map(\.note) == ["1 onion"])
        #expect(patch.recipeIngredient?.first?.referenceId != nil)
        #expect(patch.recipeInstructions?.map(\.text) == ["Chop the onion."])
        #expect(patch.notes == [])
        #expect(patch.tags == [])
    }

    @Test func servingsRoundTrip() throws {
        let recipe = try recipe()
        var draft = RecipeDraft(recipe: recipe)
        #expect(draft.servings == 4)
        #expect(draft.yieldQuantity == nil, "0 means not set")
        draft.servings = 6
        #expect(draft.patch(against: recipe).fieldNames == ["recipeServings"])
    }
}

/// Free-text line → `RecipeIngredient` (what gets saved for typed lines).
struct IngredientLineMappingTests {
    @Test func unknownFoodIsFoldedIntoTheNote() {
        let parsed = RecipeIngredient(quantity: 1, unit: IngredientUnit(id: "u-tsp", name: "teaspoon"),
                                      food: IngredientFood(id: nil, name: "sumac"), note: "ground")
        let result = RecipeDraft.savableIngredient(fromParsed: parsed, text: "1 tsp ground sumac")
        #expect(result.food == nil, "never create foods as a side effect")
        #expect(result.unit?.id == "u-tsp")
        #expect(result.quantity == 1)
        #expect(result.note == "sumac ground")
        #expect(result.display == "1 tsp ground sumac")
    }

    @Test func knownFoodAndUnitAreKept() {
        let parsed = RecipeIngredient(quantity: 2, unit: IngredientUnit(id: "u-cup", name: "cup"),
                                      food: IngredientFood(id: "f-flour", name: "flour"), note: "sifted")
        let result = RecipeDraft.savableIngredient(fromParsed: parsed, text: "2 cups flour, sifted")
        #expect(result.food?.id == "f-flour")
        #expect(result.unit?.id == "u-cup")
        #expect(result.note == "sifted")
        #expect(result.originalText == "2 cups flour, sifted")
    }

    @Test func nothingRecognisedStaysPlainText() {
        let parsed = RecipeIngredient(quantity: 0, unit: nil, food: IngredientFood(id: nil, name: "salt to taste"), note: "")
        let result = RecipeDraft.savableIngredient(fromParsed: parsed, text: "Salt to taste")
        #expect(result == RecipeDraft.freeTextIngredient("Salt to taste"))
    }

    @Test func freeTextLineUsesTheNote() {
        let ingredient = RecipeDraft.freeTextIngredient("A pinch of salt")
        #expect(ingredient.note == "A pinch of salt")
        #expect(ingredient.display == "A pinch of salt")
        #expect(ingredient.quantity == 0)
        #expect(ingredient.food == nil && ingredient.unit == nil)
    }

    @Test func pastedListsLoseTheirMarkers() {
        let text = "- 2 eggs\n• 100 g sugar\n\n* 1 lemon, zested\n▢ salt"
        #expect(RecipeEditorViewModel.pastedLines(text, stripNumbers: false) == ["2 eggs", "100 g sugar", "1 lemon, zested", "salt"])
        let steps = "1. Preheat the oven.\nStep 2: Mix.\n3) Bake 20 min."
        #expect(RecipeEditorViewModel.pastedLines(steps, stripNumbers: true) == ["Preheat the oven.", "Mix.", "Bake 20 min."])
    }
}

/// Finding the recipe link in shared or pasted text.
struct RecipeURLExtractionTests {
    @Test(arguments: [
        ("https://example.com/recipes/soup", "https://example.com/recipes/soup"),
        ("Try this! https://www.example.com/r/lemon-chicken?ref=share so good", "https://www.example.com/r/lemon-chicken?ref=share"),
        ("Lemon Herb Chicken\nhttps://example.com/a\nhttps://example.com/b", "https://example.com/a"),
        ("(see https://example.com/pasta).", "https://example.com/pasta"),
        ("http://mealie.local.example.org/recipe", "http://mealie.local.example.org/recipe"),
    ])
    func findsFirstWebLink(_ text: String, _ expected: String) {
        #expect(RecipeURLExtractor.firstWebURL(in: text)?.absoluteString == expected)
    }

    @Test func acceptsBareWWWHosts() throws {
        let url = try #require(RecipeURLExtractor.firstWebURL(in: "www.example.com/recipes/stew"))
        #expect(url.host() == "www.example.com")
        #expect(url.path() == "/recipes/stew")
    }

    @Test(arguments: ["", "no link here", "mail jane@example.com", "call +41 44 000 00 00", "ftp://example.com/file"])
    func ignoresNonWebText(_ text: String) {
        #expect(RecipeURLExtractor.firstWebURL(in: text) == nil)
    }

    @Test(arguments: [
        ("example.com/soup", "https://example.com/soup"),
        ("  https://example.com/soup  ", "https://example.com/soup"),
        ("HTTP://example.com/soup", "HTTP://example.com/soup"),
        ("Look: https://example.com/soup", "https://example.com/soup"),
    ])
    func normalizesTypedAddresses(_ input: String, _ expected: String) {
        #expect(RecipeURLExtractor.normalizedURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["soup", "localhost", "https://", "mailto:jane@example.com", "file:///tmp/x.html"])
    func rejectsNonAddresses(_ input: String) {
        #expect(RecipeURLExtractor.normalizedURL(from: input) == nil)
    }
}

struct RecipeImportProblemTests {
    @Test func badRecipeDataMeansNoRecipeFound() {
        #expect(RecipeImportProblem(.server(status: 400, message: "BAD_RECIPE_DATA")).kind == .noRecipeFound)
    }

    @Test func otherBadRequestsMeanThePageCouldNotBeLoaded() {
        let problem = RecipeImportProblem(.server(status: 400, message: "Something went wrong while creating the recipe. Please try again"))
        #expect(problem.kind == .pageUnavailable)
    }

    @Test func connectivity() {
        #expect(RecipeImportProblem(.timedOut).kind == .timedOut)
        #expect(RecipeImportProblem(.unreachable("offline")).kind == .serverUnreachable)
    }
}

struct CreateFlowRouteTests {
    @Test func routesBecomeSheets() throws {
        #expect(AppRoute(string: "editor-new") == .intent("create:editor-new", tab: .recipes))
        #expect(CreateFlowSheet(intent: "create:editor-new") == .newRecipe())
        #expect(CreateFlowSheet(intent: "create:editor-edit/lemon-herb-chicken") == .editRecipe(slug: "lemon-herb-chicken"))
        #expect(CreateFlowSheet(intent: "create:import") == .importRecipe(url: nil))
        #expect(CreateFlowSheet(intent: "recipes-new") == nil)
    }

    @Test func importRouteCarriesAnEncodedURL() throws {
        let route = try #require(AppRoute(string: "import/https%3A%2F%2Fexample.com%2Fsoup"))
        guard case .intent(let intent, _, _, _) = route else {
            Issue.record("expected an intent, got \(route)")
            return
        }
        #expect(CreateFlowSheet(intent: intent) == .importRecipe(url: "https://example.com/soup"))
    }

    @Test func recipeDeepLinkForTheShareExtension() throws {
        let url = try #require(ShareImportModel.appURL(forRecipe: "lemon-herb-chicken"))
        #expect(AppRoute(url: url) == .push(.recipe(slug: "lemon-herb-chicken"), tab: .recipes))
    }
}
