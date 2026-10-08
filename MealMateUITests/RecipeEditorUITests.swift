import XCTest

/// Recipe editor through the Recipes "+" menu: create "MealMate Test UI Recipe" with
/// ingredients and steps, save, check the detail, edit, save again. Deleted via the API.
final class RecipeEditorUITests: MealMateUITestCase {
    private let recipeName = "MealMate Test UI Recipe"

    override func setUpWithError() throws {
        try super.setUpWithError()
        api.deleteRecipes(named: recipeName)
    }

    override func tearDownWithError() throws {
        if let api { api.deleteRecipes(named: recipeName) }
        try super.tearDownWithError()
    }

    func testCreateEditAndVerifyOnDetail() throws {
        try launchSignedIn()
        app.buttons["Add Recipe"].tap()
        try wait(app.buttons["New Recipe"]).tap()
        try wait(app.navigationBars["New Recipe"])
        let save = app.navigationBars["New Recipe"].buttons["Save"]

        let name = try wait(app.textViews["Recipe name"].exists ? app.textViews["Recipe name"] : app.textFields["Recipe name"])
        name.tap()
        name.typeText(recipeName)

        // Ingredients: return after a line adds the next one.
        let addIngredient = try scrollTo(app.buttons["Add Ingredient"])
        addIngredient.tap()
        app.typeText("2 cups flour\n")
        app.typeText("3 eggs")

        let addStep = try scrollTo(app.buttons["Add Step"])
        addStep.tap()
        app.typeText("Whisk the eggs into the flour.")
        snapshot("editor-new-filled")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Saved → detail is pushed.
        try wait(element(containing: "Whisk the eggs"), timeout: 25, "Detail after save")
        try wait(element(containing: "flour"))
        try wait(element(containing: "eggs"))
        snapshot("editor-saved-detail")
        let recipes = try api.recipes(named: recipeName)
        XCTAssertEqual(recipes.count, 1)
        let slug = try XCTUnwrap(recipes.first?["slug"] as? String)
        let saved = try api.recipe(slug)
        XCTAssertEqual((saved["recipeIngredient"] as? [Any])?.count, 2)
        XCTAssertEqual((saved["recipeInstructions"] as? [Any])?.count, 1)

        // Edit: add a description and a second step.
        app.buttons["More"].firstMatch.tap()
        try wait(app.buttons["Edit"]).tap()
        try wait(app.navigationBars["Edit Recipe"])
        let description = app.textViews["Short description"].exists ? app.textViews["Short description"] : app.textFields["Short description"]
        description.tap()
        description.typeText("Edited by the UI test.")
        try scrollTo(app.buttons["Add Step"]).tap()
        app.typeText("Rest for ten minutes.")
        snapshot("editor-edit-filled")
        app.navigationBars["Edit Recipe"].buttons["Save"].tap()
        try waitUntilGone(app.navigationBars["Edit Recipe"], timeout: 25)
        try wait(element(containing: "Edited by the UI test."), timeout: 15)
        try wait(element(containing: "Rest for ten minutes"), timeout: 5)
        snapshot("editor-edited-detail")
        let edited = try api.recipe(slug)
        XCTAssertEqual(edited["description"] as? String, "Edited by the UI test.")
        XCTAssertEqual((edited["recipeInstructions"] as? [Any])?.count, 2)
    }

    /// Swipes up until `element` is hittable (editor form).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) throws -> XCUIElement {
        dismissKeyboard()
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        if !(element.exists && element.isHittable) { try fail("Not reachable: \(element)") }
        return element
    }

    /// The editor's keyboard toolbar has a "Done" button.
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { app.navigationBars.firstMatch.tap() }
    }
}
