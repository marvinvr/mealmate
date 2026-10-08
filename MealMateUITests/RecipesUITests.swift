import XCTest

/// Recipes tab and recipe detail against a "MealMate Test UI Detail" recipe created via the
/// API (deleted in tearDown): search, open, servings scaling, check-off, cook mode, filter
/// sheet, favorite and rating (restored before the recipe is deleted).
final class RecipesUITests: MealMateUITestCase {
    private let recipeName = "MealMate Test UI Detail"
    private var slug = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        api.deleteRecipes(named: recipeName)
        let units = try api.items("/api/units")
        let gram = units.first { ($0["name"] as? String) == "gram" } ?? units.first ?? [:]
        func line(_ quantity: Double, _ note: String) -> [String: Any] {
            ["quantity": quantity, "unit": gram, "food": NSNull(), "note": note, "display": "",
             "title": NSNull(), "originalText": NSNull(), "referenceId": UUID().uuidString.lowercased()]
        }
        func step(_ text: String) -> [String: Any] {
            ["id": UUID().uuidString.lowercased(), "title": "", "summary": "", "text": text, "ingredientReferences": []]
        }
        slug = try api.createRecipe(named: recipeName, fields: [
            "description": "Created by the MealMate UI tests.",
            "recipeServings": 2,
            "recipeIngredient": [line(100, "flour"), line(40, "sugar"), line(10, "butter")],
            "recipeInstructions": [step("Mix the flour and sugar."), step("Rub in the butter."), step("Bake until golden.")],
        ])
    }

    override func tearDownWithError() throws {
        if let api { api.deleteRecipes(named: recipeName) }
        try super.tearDownWithError()
    }

    func testSearchOpenScaleCheckAndCook() throws {
        try launchSignedIn()
        // The search field sits in the collapsed navigation-bar drawer: pull down to reveal it.
        if !app.searchFields.firstMatch.waitForExistence(timeout: 3) {
            app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch.swipeDown() : app.swipeDown()
        }
        let search = try wait(app.searchFields.firstMatch)
        search.tap()
        search.typeText(recipeName)
        let result = try wait(element(containing: recipeName).firstMatch, timeout: 15, "Search result")
        snapshot("recipes-search")
        result.tap()

        // Detail: amounts for 2 servings.
        let flour = try wait(button("label BEGINSWITH '100 ' AND label CONTAINS 'flour'"), timeout: 15)
        let servings = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Servings'")).firstMatch
        try wait(servings)
        XCTAssertEqual(servings.value as? String, "2 servings")
        snapshot("recipe-detail")

        // Servings 2 → 3 scales 100 g → 150 g.
        servings.buttons["Increment"].tap()
        try wait(button("label BEGINSWITH '150 ' AND label CONTAINS 'flour'"), timeout: 5, "Scaled amount")
        XCTAssertFalse(flour.exists)
        snapshot("recipe-scaled")

        // Check off an ingredient.
        let scaledFlour = button("label BEGINSWITH '150 ' AND label CONTAINS 'flour'")
        scaledFlour.tap()
        try waitFor("ingredient checked") { scaledFlour.isSelected }
        snapshot("recipe-ingredient-checked")
        scaledFlour.tap()
        try waitFor("ingredient unchecked") { !scaledFlour.isSelected }

        // Cook mode: swipe through the steps, then close.
        let startCooking = button("label CONTAINS[c] 'Start Cooking'")
        if !startCooking.isHittable { app.swipeUp() }
        startCooking.tap()
        try wait(element(containing: "Mix the flour"), timeout: 10)
        try wait(element(containing: "Step 1 of 3"))
        snapshot("cook-step-1")
        app.swipeLeft()
        try wait(element(containing: "Step 2 of 3"))
        try wait(element(containing: "Rub in the butter"))
        app.swipeLeft()
        try wait(element(containing: "Step 3 of 3"))
        snapshot("cook-step-3")
        app.swipeRight()
        try wait(element(containing: "Step 2 of 3"))
        app.buttons["Close"].firstMatch.tap()
        try waitUntilGone(element(containing: "Step 2 of 3"))
        try wait(button("label BEGINSWITH '150 ' AND label CONTAINS 'flour'"), timeout: 5, "Back on the detail, still scaled")
    }

    func testFilterSheetApplyAndClear() throws {
        try launchSignedIn()
        try openFilterSheet()
        let favorites = app.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Favorites'")).firstMatch
        try wait(favorites)
        toggle(favorites)
        try waitFor("favorites switch on") { (favorites.value as? String) == "1" }
        snapshot("recipes-filter-sheet")
        app.navigationBars["Filter"].buttons["Done"].tap()
        let chip = try wait(button("label == 'Remove filter Favorites'"), timeout: 5, "Active filter chip")
        snapshot("recipes-filtered")

        // Clear via the sheet's Reset.
        try openFilterSheet()
        app.navigationBars["Filter"].buttons["Reset"].tap()
        app.navigationBars["Filter"].buttons["Done"].tap()
        try waitUntilGone(chip)

        // Apply again and clear via the chip.
        try openFilterSheet()
        toggle(favorites)
        app.navigationBars["Filter"].buttons["Done"].tap()
        try wait(chip).tap()
        try waitUntilGone(chip)
    }

    func testFavoriteAndRatingOnTestRecipe() throws {
        let userID = try api.currentUser()["id"] as! String
        try launchSignedIn(route: "recipe/\(slug)")
        try wait(button("label BEGINSWITH '100 ' AND label CONTAINS 'flour'"), timeout: 15)

        // Favorite on → server → off.
        let add = try wait(app.buttons["Add to Favorites"])
        add.tap()
        try wait(app.buttons["Remove from Favorites"], timeout: 5)
        try expectRating(userID: userID) { $0?["isFavorite"] as? Bool == true }
        snapshot("recipe-favorited")
        app.buttons["Remove from Favorites"].tap()
        try wait(app.buttons["Add to Favorites"], timeout: 5)
        try expectRating(userID: userID) { ($0?["isFavorite"] as? Bool ?? false) == false }

        // Rating: 4 stars → server → cleared.
        let rating = app.descendants(matching: .any).matching(identifier: "Rating").firstMatch
        if !rating.isHittable { app.swipeUp() }
        try wait(rating)
        tapStar(4, in: rating)
        try waitFor("rated 4") { (rating.value as? String)?.contains("4 of 5") == true }
        try expectRating(userID: userID) { ($0?["rating"] as? Double) == 4 }
        snapshot("recipe-rated")
        tapStar(4, in: rating)
        try waitFor("rating cleared") { (rating.value as? String)?.contains("Your rating") == false }
        try expectRating(userID: userID) { ($0?["rating"] as? Double ?? 0) == 0 }
    }

    // MARK: Helpers

    /// Taps the switch itself (a tap on the row's center lands on the label and does nothing).
    private func toggle(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func openFilterSheet() throws {
        app.buttons["View Options"].tap()
        let filter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filter'")).firstMatch
        try wait(filter).tap()
        try wait(app.navigationBars["Filter"])
    }

    /// Stars are 32 pt wide with 2 pt spacing, leading-aligned in the rating control.
    private func tapStar(_ star: Int, in rating: XCUIElement) {
        let x = CGFloat(star - 1) * 34 + 16
        rating.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: rating.frame.height / 2)).tap()
    }

    /// Polls the user's rating entry for the test recipe until `check` passes.
    private func expectRating(userID: String, _ check: ([String: Any]?) -> Bool) throws {
        let recipeID = try api.recipe(slug)["id"] as? String
        for _ in 0..<20 {
            let ratings = try api.object("/api/users/\(userID)/ratings")["ratings"] as? [[String: Any]] ?? []
            if check(ratings.first { ($0["recipeId"] as? String) == recipeID }) { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("Server rating/favorite didn't reach the expected state")
    }
}
