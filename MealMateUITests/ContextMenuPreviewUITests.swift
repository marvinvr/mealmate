import XCTest

/// Long-presses a recipe card on every screen that shows recipe cards and saves a screenshot
/// with the context menu open, so the lifted preview can be checked: only the pressed card,
/// never its whole grid row. Only writes two "MealMate Test Ctx" meal plan notes for today
/// (deleted in tearDown).
final class ContextMenuPreviewUITests: MealMateUITestCase {
    private let noteTitle = "MealMate Test Ctx"
    private var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    override func tearDownWithError() throws {
        if let api { api.deleteMealPlanEntries(named: noteTitle, from: today, to: today) }
        try super.tearDownWithError()
    }

    func testRecipesGrid() throws {
        try launchSignedIn(route: "recipes-grid")
        try longPressCard(at: CGVector(dx: 0.27, dy: 0.5), name: "recipes-grid")
        // The right-hand card of a row as well.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75)).tap()
        try longPressCard(at: CGVector(dx: 0.73, dy: 0.5), name: "recipes-grid-right")
    }

    /// Release builds have no DEBUG harness or routes: signs in through the UI (grid is the
    /// default layout) and signs out at the end.
    func testRecipesGridSignedInThroughUI() throws {
        try signInWithTokenThroughUI()
        try longPressCard(at: CGVector(dx: 0.27, dy: 0.5), name: "ui-recipes-grid")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75)).tap()
        try longPressCard(at: CGVector(dx: 0.73, dy: 0.5), name: "ui-recipes-grid-right")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75)).tap()
        try signOutFromSettings()
    }

    func testRecipesList() throws {
        try launchSignedIn(route: "recipes-list")
        try longPressCard(at: CGVector(dx: 0.5, dy: 0.45), name: "recipes-list")
    }

    func testRecipesSearch() throws {
        try launchSignedIn(route: "recipes-search/a")
        try longPressCard(at: CGVector(dx: 0.5, dy: 0.45), name: "recipes-search")
    }

    func testLibraryFavorites() throws {
        try launchSignedIn(route: "library-all/favorites")
        try longPressCard(at: CGVector(dx: 0.27, dy: 0.45), name: "library-favorites")
    }

    func testLibraryTag() throws {
        let tags = try api.items("/api/organizers/tags")
        guard let slug = tags.first?["slug"] as? String else { throw XCTSkip("No tags on the server") }
        try launchSignedIn(route: "tag/\(slug)")
        try longPressCard(at: CGVector(dx: 0.27, dy: 0.4), name: "library-tag")
    }

    func testMealPlan() throws {
        for (index, type) in ["lunch", "dinner"].enumerated() {
            _ = try api.send("POST", "/api/households/mealplans", json: [
                "date": today, "entryType": type, "title": "\(noteTitle) \(index + 1)", "text": "",
            ])
        }
        try launchSignedIn(route: "mealplan-week/\(today)")
        let entry = try wait(element(containing: "\(noteTitle) 1").firstMatch, timeout: 15, "Meal plan note")
        Thread.sleep(forTimeInterval: 2)
        snapshot("ctx-mealplan-before")
        entry.press(forDuration: 1.5)
        Thread.sleep(forTimeInterval: 1)
        snapshot("ctx-mealplan-menu")
    }

    private func longPressCard(at offset: CGVector, name: String) throws {
        // Let cards and photos load.
        Thread.sleep(forTimeInterval: 4)
        snapshot("ctx-\(name)-before")
        app.coordinate(withNormalizedOffset: offset).press(forDuration: 1.5)
        Thread.sleep(forTimeInterval: 1)
        snapshot("ctx-\(name)-menu")
    }
}
