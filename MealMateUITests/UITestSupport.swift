import XCTest

/// Server + token for UI tests. `scripts/ui-test.sh` reads them from files outside the repo
/// and passes them as `TEST_RUNNER_MEALMATE_TEST_SERVER` / `TEST_RUNNER_MEALMATE_TEST_TOKEN`
/// (xcodebuild strips the prefix for the test runner). Never print or attach the token.
enum UITestConfig {
    static var server: String? { value("MEALMATE_TEST_SERVER") }
    static var token: String? { value("MEALMATE_TEST_TOKEN") }

    /// `server` with a scheme (`mealie.local` → `http://mealie.local` is tried by the app too,
    /// but the API helper needs one URL).
    static var serverURL: URL? {
        guard let server else { return nil }
        let withScheme = server.contains("://") ? server : "http://\(server)"
        return URL(string: withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func value(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

/// Base class: skips without a server, launches the app through the DEBUG harness, and
/// saves screenshots as attachments and as `screenshots/qa-<name>.png` (git-ignored).
@MainActor
class MealMateUITestCase: XCTestCase {
    var api: MealieTestAPI!
    var app: XCUIApplication!

    override func setUpWithError() throws {
        // Failing helpers throw `UITestFailure` to end a test. Tests are synchronous: an
        // async test deadlocks when XCTest interrupts it (e.g. a failed tap) and runs tearDown.
        continueAfterFailure = true
        guard UITestConfig.serverURL != nil, let token = UITestConfig.token else {
            throw XCTSkip("Set TEST_RUNNER_MEALMATE_TEST_SERVER and TEST_RUNNER_MEALMATE_TEST_TOKEN (scripts/ui-test.sh).")
        }
        api = MealieTestAPI(baseURL: UITestConfig.serverURL!, token: token)
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    /// Launches signed in with the harness (ephemeral: nothing stored, nothing revoked).
    func launchSignedIn(route: String? = nil) throws {
        app.launchEnvironment["MEALMATE_TEST_SERVER"] = UITestConfig.serverURL!.absoluteString
        app.launchEnvironment["MEALMATE_TEST_TOKEN"] = UITestConfig.token
        if let route { app.launchArguments += ["-MealMateRoute", route] }
        app.launch()
        try wait(app.tabBars.firstMatch, timeout: 15, "Main tabs didn't appear")
    }

    // MARK: Persisted sign-in (token typed into the UI)

    /// From a fresh launch without the harness: signs out a leftover session, enters the
    /// server and signs in with the pasted API token (stored in the Keychain like a user's).
    func signInWithTokenThroughUI() throws {
        app.launch()
        try signOutIfNeeded()
        try wait(element(containing: "Welcome to MealMate"), timeout: 10)
        try wait(app.textFields["Server address"]).replaceText(UITestConfig.server!)
        button("label ==[c] 'Continue'").tap()
        try wait(button("label CONTAINS[c] 'API token'"), timeout: 20).tap()
        try wait(app.navigationBars["API Token"])
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["Paste token"]
        field.tap()
        field.typeText(UITestConfig.token!)
        app.navigationBars["API Token"].buttons["Sign In"].tap()
        try wait(tab("Recipes"), timeout: 20, "Main tabs after token sign-in")
    }

    func signOutIfNeeded() throws {
        if tab("Recipes").waitForExistence(timeout: 4) { try signOutFromSettings() }
    }

    /// Settings → Sign Out → confirm. Never revokes a pasted token (see AppSession.signOut).
    func signOutFromSettings() throws {
        try wait(app.buttons["Account and settings"]).tap()
        try wait(app.navigationBars["Settings"])
        let signOut = app.buttons.matching(NSPredicate(format: "label ==[c] 'Sign Out'")).firstMatch
        if !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        let confirm = app.sheets.buttons.matching(NSPredicate(format: "label ==[c] 'Sign Out'")).firstMatch
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        } else {
            app.buttons.matching(NSPredicate(format: "label ==[c] 'Sign Out'")).element(boundBy: 1).tap()
        }
        try wait(element(containing: "Welcome to MealMate"), timeout: 10)
    }

    // MARK: Screenshots

    /// Attaches a screenshot and writes `screenshots/qa-<name>.png`. Never call this while the
    /// API token is visible on screen.
    func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "screenshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appending(path: "qa-\(name).png"))
    }

    /// Writes the accessibility hierarchy to `screenshots/qa-<name>.txt` (debugging aid).
    func dumpHierarchy(_ name: String) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "screenshots", directoryHint: .isDirectory)
        try? app.debugDescription.write(to: directory.appending(path: "qa-\(name).txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    func button(_ predicate: String, _ args: Any...) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: predicate, argumentArray: args)).firstMatch
    }

    @discardableResult
    func wait(_ element: XCUIElement, timeout: TimeInterval = 10, _ message: String? = nil,
              file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            try fail(message ?? "Missing: \(element)", file: file, line: line)
        }
        return element
    }

    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        if XCTWaiter().wait(for: [gone], timeout: timeout) != .completed {
            try fail("Still visible: \(element)", file: file, line: line)
        }
    }

    /// Waits until `condition` holds (polling the UI).
    func waitFor(_ description: String, timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { try fail("Timed out: \(description)", file: file, line: line) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    /// Records the failure (with a hierarchy dump + screenshot) and ends the test.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) throws -> Never {
        let tag = "failure-\(name.filter { $0.isLetter || $0.isNumber })-\(line)"
        dumpHierarchy(tag)
        snapshot(tag)
        XCTFail(message, file: file, line: line)
        throw UITestFailure(message: message)
    }

    func tab(_ title: String) -> XCUIElement {
        app.tabBars.buttons[title]
    }

    /// Text containing `substring` (labels of static texts, buttons, cells).
    func element(containing substring: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", substring)).firstMatch
    }
}

struct UITestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

extension XCUIElement {
    /// Replaces the field's text.
    func replaceText(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
