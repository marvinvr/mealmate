import Foundation
import Testing
@testable import MealMate

/// Decodes the recorded (anonymized) responses in Fixtures/.
struct DecodingTests {
    @Test func appAbout() throws {
        let info = try Fixture.decode(AppInfo.self, from: "app-about")
        #expect(info.version == "v3.28.0")
        #expect(info.displayVersion == "3.28.0")
        #expect(info.isOIDCEnabled)
        #expect(info.isPasswordLoginAllowed)
        #expect(info.oidcButtonTitle == "Sign in with Example SSO")
    }

    @Test func oidcNativeConfig() throws {
        let config = try Fixture.decode(OIDCNativeConfig.self, from: "oidc-native-config")
        #expect(config.authorizationEndpoint.absoluteString == "https://idp.example.com/authorize")
        #expect(config.clientId == "mealmate-example-client")
        #expect(config.scope == "openid email profile")
    }

    @Test func userSelf() throws {
        let user = try Fixture.decode(User.self, from: "user-self")
        #expect(user.displayName == "Jane Doe")
        #expect(user.initials == "JD")
        #expect(user.authMethod == .mealie)
        #expect(user.householdSlug == "demo-household")
        #expect(user.tokens?.isEmpty == false)
    }

    @Test func apiTokenCreated() throws {
        let token = try Fixture.decode(APITokenCreated.self, from: "api-token-create")
        #expect(token.id == 4)
        #expect(token.token == "redacted-example-token")
        #expect(token.createdAt == nil)
    }

    @Test func recipeSummaryPage() throws {
        let page = try Fixture.decode(Page<RecipeSummary>.self, from: "recipes-page")
        #expect(page.items.count == 3)
        #expect(page.total == 5)
        #expect(page.totalPages == 2)
        #expect(page.hasMore)
        let first = try #require(page.items.first)
        #expect(first.name == "Lemon Herb Chicken")
        #expect(first.slug == "lemon-herb-chicken")
        #expect(first.imageKey == "aB3x")
        #expect(first.hasImage)
        #expect(first.recipeServings == 4)
        #expect(first.dateAdded == MealieDay(year: 2026, month: 10, day: 8))
        // List endpoints use "+00:00" offsets.
        #expect(first.createdAt != nil)
        #expect(first.updatedAt != nil)
        #expect(first.lastMade == nil)
    }

    @Test func fullRecipe() throws {
        let recipe = try Fixture.decode(Recipe.self, from: "recipe-full")
        #expect(recipe.name == "Lemon Herb Chicken")
        #expect(recipe.ingredients.count == 4)
        let first = try #require(recipe.ingredients.first)
        #expect(first.quantity == 500)
        #expect(first.unit?.name == "gram")
        #expect(first.food?.name == "Flour")
        #expect(first.food?.label?.name == "Baking")
        #expect(first.title == "Marinade")
        #expect(first.referenceId != nil)
        #expect(first.displayText == "500 grams Flour")
        #expect(recipe.ingredients[1].unit == nil)
        #expect(recipe.instructions.isEmpty == false)
        #expect(recipe.instructions[0].text.hasPrefix("Whisk"))
        #expect(recipe.settings?.locked == false)
        #expect(recipe.nutrition?.isEmpty == true)
        #expect(recipe.comments?.isEmpty == true)
        #expect(recipe.summary.slug == recipe.slug)
    }

    @Test func recipeRoundTripsThroughEncoder() throws {
        let recipe = try Fixture.decode(Recipe.self, from: "recipe-full")
        // Encoding keeps milliseconds only, so compare the second round trip.
        let once = try MealieJSON.decoder.decode(Recipe.self, from: MealieJSON.encoder.encode(recipe))
        let twice = try MealieJSON.decoder.decode(Recipe.self, from: MealieJSON.encoder.encode(once))
        #expect(twice == once)
        #expect(once.ingredients.map(\.displayText) == recipe.ingredients.map(\.displayText))
        #expect(once.instructions == recipe.instructions)
    }

    @Test func shoppingList() throws {
        let list = try Fixture.decode(ShoppingList.self, from: "shopping-list")
        #expect(list.displayName == "Groceries")
        #expect(list.items.count == 4)
        #expect(list.items[0].checked)
        #expect(list.items[0].displayText == "Paper towels")
        #expect(list.items[1].label?.name == "Baking")
        #expect(list.items[2].recipeReferences?.count == 1)
        #expect(list.recipeReferences?.first?.recipe?.name == "Lemon Herb Chicken")
        #expect(list.labelSettings?.isEmpty == false)
    }

    @Test func shoppingListsPageHasNoItems() throws {
        let page = try Fixture.decode(Page<ShoppingList>.self, from: "shopping-lists-page")
        #expect(page.items.count == 1)
        #expect(page.items[0].listItems == nil)
    }

    @Test func shoppingItemsCollection() throws {
        let collection = try Fixture.decode(ShoppingListItemsCollection.self, from: "shopping-items-collection")
        #expect(collection.updatedItems.count == 1)
        #expect(collection.createdItems.isEmpty)
        #expect(collection.updatedItems[0].checked)
    }

    @Test func mealPlanPage() throws {
        let page = try Fixture.decode(Page<MealPlanEntry>.self, from: "mealplans-page")
        #expect(page.items.count == 3)
        let note = try #require(page.items.first { $0.isNote })
        #expect(note.entryType == .lunch)
        #expect(note.displayTitle == "Leftovers night")
        #expect(note.date == MealieDay(year: 2030, month: 1, day: 7))
        let dinner = try #require(page.items.first { $0.entryType == .dinner && !$0.isNote })
        #expect(dinner.recipe?.slug.isEmpty == false)
    }

    @Test func unknownEnumValuesDecode() throws {
        let json = #"{"id": 9, "date": "2030-01-01", "entryType": "brunch", "title": "x", "text": ""}"#
        let entry = try MealieJSON.decoder.decode(MealPlanEntry.self, from: Data(json.utf8))
        #expect(entry.entryType.rawValue == "brunch")
        #expect(entry.entryType.title == "Brunch")
        #expect(PlanEntryType.breakfast < entry.entryType)
    }

    @Test func recipeActions() throws {
        let page = try Fixture.decode(Page<RecipeAction>.self, from: "recipe-actions-page")
        let action = try #require(page.items.first)
        #expect(action.title == "Send to Bring")
        #expect(action.actionType == .post)
        #expect(!action.isLink)
    }

    @Test func shareTokens() throws {
        let tokens = try Fixture.decode(LossyArray<RecipeShareToken>.self, from: "shared-recipes").elements
        #expect(tokens.count == 2)
        #expect(tokens[0].id == "00000000-0000-4000-8000-0000000000b1")
        #expect(tokens[0].expiresAt != nil)
        #expect(tokens[0].createdAt != nil)
        let now = try #require(tokens[0].createdAt)
        #expect(!tokens[0].isExpired(now: now))
        #expect(tokens[1].isExpired(now: now))
    }

    @Test func timeline() throws {
        let page = try Fixture.decode(Page<TimelineEvent>.self, from: "timeline-page")
        let event = try #require(page.items.first)
        #expect(event.eventType == .system)
        #expect(event.hasImage == false)
        #expect(event.timestamp != nil)
    }

    @Test func organizersAndCookbooks() throws {
        #expect(try Fixture.decode(Page<Organizer>.self, from: "categories-page").items.first?.slug == "weeknight")
        #expect(try Fixture.decode(Page<Organizer>.self, from: "tags-page").items.first?.name == "Vegetarian")
        let tool = try #require(try Fixture.decode(Page<Organizer>.self, from: "tools-page").items.first)
        #expect(tool.householdsWithTool == [])
        let cookbook = try #require(try Fixture.decode(Page<Cookbook>.self, from: "cookbooks-page").items.first)
        #expect(cookbook.name == "Quick Dinners")
        #expect(cookbook.household?.name == "Demo Household")
    }

    @Test func foodsUnitsLabels() throws {
        #expect(try Fixture.decode(Page<IngredientFood>.self, from: "foods-page").items.count == 3)
        #expect(try Fixture.decode(Page<IngredientUnit>.self, from: "units-page").items.count == 3)
        #expect(try Fixture.decode(Page<MultiPurposeLabel>.self, from: "labels-page").items.first?.color == "#959595")
    }

    @Test func parsedIngredient() throws {
        let parsed = try Fixture.decode(ParsedIngredient.self, from: "parsed-ingredient")
        #expect(parsed.input == "2 cups flour")
        #expect(parsed.ingredient.quantity == 2)
        #expect(parsed.ingredient.unit?.name == "cup")
        #expect((parsed.confidence?.average ?? 0) > 0.9)
    }

    @Test func aiSettingsAndRatings() throws {
        #expect(try Fixture.decode(AIProviderSettings.self, from: "ai-settings").isAIAvailable == false)
        #expect(try Fixture.decode(UserRatings.self, from: "user-ratings").ratings.isEmpty)
    }

    @Test func lossyPageDropsBrokenItems() throws {
        let json = #"{"page":1,"per_page":2,"total":2,"total_pages":1,"items":[{"id":"a","slug":"ok"},{"name":"missing id and slug"}],"next":null,"previous":null}"#
        let page = try MealieJSON.decoder.decode(Page<RecipeSummary>.self, from: Data(json.utf8))
        #expect(page.items.map(\.slug) == ["ok"])
    }

    @Test func recipeSuggestions() throws {
        let response = try Fixture.decode(RecipeSuggestionResponse.self, from: "recipe-suggestions")
        // The entry without id/slug is dropped, the rest survive.
        #expect(response.items.map(\.recipe.slug) == ["lemon-herb-chicken", "tomato-soup"])
        let complete = try #require(response.items.first)
        #expect(complete.missingFoods.isEmpty && complete.substitutedFoods.isEmpty && complete.missingTools.isEmpty)
        let soup = response.items[1]
        // A food without a name is dropped; the summary-shaped one decodes.
        #expect(soup.missingFoods.map(\.name) == ["Parmesan", "basil"])
        #expect(soup.substitutedFoods.first?.food.name == "butter")
        #expect(soup.substitutedFoods.first?.substituteFood.name == "olive oil")
        #expect(soup.missingTools.map(\.name) == ["Blender"])
    }

    @Test func flexibleImageKey() throws {
        let json = #"[{"id":"a","slug":"a","image":12},{"id":"b","slug":"b","image":false},{"id":"c","slug":"c","image":null}]"#
        let recipes = try MealieJSON.decoder.decode([RecipeSummary].self, from: Data(json.utf8))
        #expect(recipes.map(\.imageKey) == ["12", nil, nil])
    }

    @Test(arguments: [
        ("error-detail-string", "Could not validate credentials"),
        ("error-detail-object", "No Entry Found"),
        ("error-detail-validation", "ingredient: Field required"),
    ])
    func errorDetailMessages(_ fixture: String, _ expected: String) throws {
        #expect(MealieError.detailMessage(from: try Fixture.data(fixture)) == expected)
    }

    @Test func statusMapping() throws {
        #expect(MealieError(status: 401, body: try Fixture.data("error-detail-string")) == .unauthorized)
        #expect(MealieError(status: 404, body: try Fixture.data("error-detail-object")) == .notFound("No Entry Found"))
        #expect(MealieError(status: 500, body: Data()) == .server(status: 500, message: nil))
    }
}
