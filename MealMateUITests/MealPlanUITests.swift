import XCTest

/// Meal plan: page to a far-future week, add a "MealMate Test UI Note" entry, delete it.
final class MealPlanUITests: MealMateUITestCase {
    private let noteTitle = "MealMate Test UI Note"
    private let weeksAhead = 12

    private var range: (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: (weeksAhead + 2) * 7, to: Date())!
        return (formatter.string(from: start), formatter.string(from: end))
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        api.deleteMealPlanEntries(named: noteTitle, from: range.0, to: range.1)
    }

    override func tearDownWithError() throws {
        if let api { api.deleteMealPlanEntries(named: noteTitle, from: range.0, to: range.1) }
        try super.tearDownWithError()
    }

    func testAddAndDeleteNoteInAFutureWeek() throws {
        try launchSignedIn()
        tab("Meal Plan").tap()
        let next = try wait(app.buttons["Next Week"], timeout: 10)
        let weekTitle = app.staticTexts.matching(NSPredicate(format: "label MATCHES '.*[0-9]+ ?[–-] ?.*[0-9]+.*'")).firstMatch
        let currentWeek = try wait(weekTitle).label
        for _ in 0..<weeksAhead { next.tap() }
        // Off the current week the toolbar offers "Today".
        try wait(app.buttons["Today"], timeout: 5, "Week didn't change after tapping Next Week")
        try waitFor("week title changed") { weekTitle.label != currentWeek }
        snapshot("mealplan-future-week")

        let add = try wait(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add to '")).firstMatch)
        add.tap()
        try wait(app.buttons["Add Note…"]).tap()
        let title = try wait(app.textFields["Title"])
        title.tap()
        title.typeText(noteTitle)
        snapshot("mealplan-note-editor")
        app.navigationBars.buttons["Add"].tap()

        let entry = try wait(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", noteTitle)).firstMatch, timeout: 15)
        snapshot("mealplan-note-added")
        try expectEntries { $0.contains { ($0["title"] as? String) == self.noteTitle } }

        entry.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }
        try waitUntilGone(entry, timeout: 10)
        try expectEntries { !$0.contains { ($0["title"] as? String) == self.noteTitle } }
    }

    private func expectEntries(_ check: ([[String: Any]]) -> Bool) throws {
        for _ in 0..<30 {
            if check(try api.mealPlanEntries(from: range.0, to: range.1)) { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("Server meal plan didn't reach the expected state")
    }
}
