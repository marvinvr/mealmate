import StoreKitTest
import XCTest

/// Supporter tier states in the real app, with purchases from the local `MealMate.storekit`
/// through `SKTestSession` (apps started by `simctl launch` don't get the scheme's StoreKit
/// configuration). Walks non-supporter → Sous Chef → Head Chef (upgrade) → Head Chef lapsed,
/// and writes `screenshots/qa-supporter-[ipad-]*-<appearance>.png`. `XCUIDevice.appearance` doesn't
/// switch the iOS 27 simulator, so set it first and pass its name for the file names:
///
///   xcrun simctl ui "$UDID" appearance dark
///   TEST_RUNNER_MEALMATE_APPEARANCE=dark scripts/ui-test.sh --derived-data build/DD-<role> "$UDID" SupporterScreenshotTests
final class SupporterScreenshotTests: MealMateUITestCase {
    private var session: SKTestSession!
    private var baseArguments: [String] = []
    /// Extra launch arguments for the current state (UserDefaults overrides).
    private var stateArguments: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        session = try SKTestSession(configurationFileNamed: "MealMate")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        baseArguments = app.launchArguments
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        try super.tearDownWithError()
    }

    func testSupporterStates() throws {
        // Non-supporter: ignore whatever an earlier run cached in this simulator.
        stateArguments = ["-supporter.status", "", "-supporter.activeTier", "0"]
        try shoot("none", sheet: true, prompt: true, icons: true)
        stateArguments = []

        // Sous Chef.
        try session.buyProduct(productIdentifier: "souschef.monthly")
        try shoot("souschef", sheet: true, icons: true)

        // Upgrade to Head Chef, then use one of its icons.
        try session.buyProduct(productIdentifier: "headchef.yearly")
        try shoot("headchef", sheet: true, icons: true)
        try open("app-icon", waitFor: "Copper Pot")
        app.buttons["Copper Pot"].tap()
        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 8), "icon change alert")
        snapshot("supporter-\(device)icon-applied-\(appearance)")
        dismissIconAlert()

        // Head Chef lapses. The running app hears about it (or the next launch does), the guard
        // puts the default icon back and the system confirms that with its alert.
        try session.expireSubscription(productIdentifier: "headchef.yearly")
        try session.expireSubscription(productIdentifier: "souschef.monthly")
        let alert = springboard.alerts.firstMatch
        if !alert.waitForExistence(timeout: 8) {
            app.terminate()
            app.launch()
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "icon reset alert")
        }
        snapshot("supporter-\(device)icon-reset-\(appearance)")
        dismissIconAlert()
        try shoot("lapsed", sheet: true, icons: true)
    }

    // MARK: Helpers

    private var appearance: String {
        ProcessInfo.processInfo.environment["MEALMATE_APPEARANCE"] ?? "light"
    }

    /// "ipad-" on iPad, so both devices can shoot side by side.
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func shoot(_ state: String, sheet: Bool, prompt: Bool = false, icons: Bool) throws {
        try open("settings", waitFor: "App Icon")
        snapshot("supporter-\(device)settings-\(state)-\(appearance)")
        if sheet {
            try open("supporter", waitFor: "App Icons")
            snapshot("supporter-\(device)sheet-\(state)-\(appearance)")
            app.swipeUp()
            snapshot("supporter-\(device)sheet-\(state)-middle-\(appearance)")
            app.swipeUp()
            app.swipeUp()
            snapshot("supporter-\(device)sheet-\(state)-bottom-\(appearance)")
        }
        if prompt {
            try open("supporter-prompt/1", waitFor: "Maybe Later")
            snapshot("supporter-\(device)prompt-\(appearance)")
        }
        if icons {
            try open("app-icon", waitFor: "Midnight Kitchen")
            snapshot("supporter-\(device)icons-\(state)-\(appearance)")
        }
    }

    private func open(_ route: String, waitFor text: String) throws {
        if springboard.alerts.firstMatch.exists { dismissIconAlert() }
        app.terminate()
        app.launchEnvironment["MEALMATE_TEST_SERVER"] = UITestConfig.serverURL!.absoluteString
        app.launchEnvironment["MEALMATE_TEST_TOKEN"] = UITestConfig.token
        app.launchArguments = baseArguments + stateArguments + ["-MealMateRoute", route]
        app.launch()
        try wait(element(containing: text), timeout: 15, "\(route): \(text)")
        Thread.sleep(forTimeInterval: 1.5) // products load, sheets settle
    }

    private func dismissIconAlert() {
        let ok = springboard.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
    }
}
