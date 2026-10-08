import XCTest

/// Shopping: create "MealMate Test UI List", add items through the add bar (parsed),
/// check/uncheck by tap and swipe, clear checked, delete the list.
final class ShoppingUITests: MealMateUITestCase {
    private let listName = "MealMate Test UI List"

    override func setUpWithError() throws {
        try super.setUpWithError()
        api.deleteShoppingLists(named: listName)
    }

    override func tearDownWithError() throws {
        if let api { api.deleteShoppingLists(named: listName) }
        try super.tearDownWithError()
    }

    func testListItemsCheckClearAndDelete() throws {
        try launchSignedIn()
        tab("Shopping").tap()
        try wait(app.navigationBars["Shopping"])
        app.navigationBars["Shopping"].buttons["New List"].tap()
        let nameField = try wait(app.alerts["New List"].textFields.firstMatch)
        nameField.typeText(listName)
        app.alerts["New List"].buttons["Create"].tap()

        // Creating pushes the new (empty) list.
        try wait(app.navigationBars[listName], timeout: 15)
        let addBar = try wait(app.textFields["Add an item"])
        addBar.tap()
        addBar.typeText("2 lemons\n")
        app.typeText("500 g flour\n")
        app.typeText("MealMate test napkins\n")
        let lemons = try wait(itemRow("lemon"), timeout: 15)
        let flour = try wait(itemRow("500 "), timeout: 15)
        let napkins = try wait(itemRow("napkins"), timeout: 15)
        try waitFor("items saved (not pending)", timeout: 15) { lemons.isEnabled && flour.isEnabled && napkins.isEnabled }
        // Parsed: quantity kept as an amount (the food may be matched to a server food with
        // another name, so the flour row is found by its amount).
        XCTAssertTrue(lemons.label.hasPrefix("2"), "lemons row: \(lemons.label)")
        XCTAssertTrue(flour.label.hasPrefix("500"), "flour row: \(flour.label)")
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        snapshot("shopping-list-items")

        // Tap to check, tap again to uncheck.
        lemons.tap()
        try waitFor("lemons checked") { self.itemRow("lemon").label.contains("checked") }
        itemRow("lemon").tap()
        try waitFor("lemons unchecked") { !self.itemRow("lemon").label.contains("checked") }

        // Swipe (leading full swipe) to check.
        itemRow("500 ").swipeRight()
        let check = app.buttons["Check"]
        if check.waitForExistence(timeout: 2) { check.tap() }
        try waitFor("flour checked") { self.itemRow("500 ").label.contains("checked") }
        itemRow("napkins").tap()
        try waitFor("napkins checked") { self.itemRow("napkins").label.contains("checked") }
        snapshot("shopping-list-checked")

        let lists = try api.shoppingLists(named: listName)
        let id = try XCTUnwrap(lists.first?["id"] as? String)
        try expectItems(listID: id) { items in items.filter { $0["checked"] as? Bool == true }.count == 2 }

        // Clear checked.
        app.buttons["Clear"].firstMatch.tap()
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove 2'")).firstMatch
        try wait(remove).tap()
        try waitUntilGone(itemRow("500 "))
        try waitUntilGone(itemRow("napkins"))
        try wait(itemRow("lemon"))
        try expectItems(listID: id) { $0.count == 1 }
        snapshot("shopping-list-cleared")

        // Back to the overview, swipe to delete the list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = try wait(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", listName)).firstMatch, timeout: 10)
        row.swipeLeft()
        try wait(app.buttons["Delete"]).tap()
        try wait(app.buttons["Delete List"]).tap()
        try waitUntilGone(row)
        let remaining = try api.shoppingLists(named: listName)
        XCTAssertTrue(remaining.isEmpty, "List still on the server")
    }

    private func itemRow(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND NOT (label CONTAINS 'MealMate Test UI List')", text)).firstMatch
    }

    private func expectItems(listID: String, _ check: ([[String: Any]]) -> Bool) throws {
        for _ in 0..<20 {
            let items = try api.shoppingList(listID)["listItems"] as? [[String: Any]] ?? []
            if check(items) { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("Server items didn't reach the expected state")
    }
}
