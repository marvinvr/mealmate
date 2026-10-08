import XCTest

/// Real onboarding through the UI: server address → login options → password form
/// validation → API token sign-in → session restore → sign-out (pasted token NOT revoked)
/// → stored credentials gone.
final class OnboardingUITests: MealMateUITestCase {
    func testServerEntryLoginOptionsTokenSignInAndSignOut() throws {
        let tokensBefore = try api.apiTokenNames()
        let info = try api.appInfo()

        app.launch()
        try signOutIfNeeded()

        // 1. Server address
        try wait(element(containing: "Welcome to MealMate"), timeout: 10)
        let address = try wait(app.textFields["Server address"])
        address.replaceText(UITestConfig.server!)
        snapshot("onboarding-server-filled")
        let continueButton = button("label ==[c] 'Continue'")
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        // 2. Login screen: provider button + alternatives
        try wait(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Sign in'")).firstMatch, timeout: 20)
        if info["enableOidc"] as? Bool == true {
            let provider = (info["oidcProviderName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "SSO"
            try wait(button("label ==[c] %@", "Sign in with \(provider)"), timeout: 5, "OIDC button for \(provider)")
        }
        let passwordButton = button("label CONTAINS[c] 'password'")
        let tokenButton = button("label CONTAINS[c] 'API token'")
        if info["allowPasswordLogin"] as? Bool != false { try wait(passwordButton) }
        try wait(tokenButton)
        snapshot("onboarding-login")

        // 3. Username & password: renders and validates (never submits real credentials).
        if passwordButton.exists {
            passwordButton.tap()
            let username = try wait(app.textFields["Username or email"])
            let password = try wait(app.secureTextFields["Password"])
            let submit = button("label ==[c] 'Sign in'")
            XCTAssertFalse(submit.isEnabled, "Sign in must be disabled while the form is empty")
            username.tap()
            username.typeText("mealmate-test-nobody")
            XCTAssertFalse(submit.isEnabled, "Sign in must stay disabled without a password")
            password.tap()
            password.typeText("not-a-real-password")
            XCTAssertTrue(submit.isEnabled)
            snapshot("onboarding-password-form")
            submit.tap()
            try wait(element(containing: "Wrong username or password"), timeout: 15)
            snapshot("onboarding-password-wrong")
        }

        // 4. API token sheet → sign in → tabs
        tokenButton.tap()
        try wait(app.navigationBars["API Token"])
        let signIn = app.navigationBars["API Token"].buttons["Sign In"]
        XCTAssertFalse(signIn.isEnabled, "Sign In must be disabled without a token")
        snapshot("onboarding-token-sheet-empty")
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["Paste token"]
        field.tap()
        field.typeText(UITestConfig.token!)
        // No screenshot here: the token is visible.
        XCTAssertTrue(signIn.isEnabled)
        signIn.tap()
        try wait(tab("Recipes"), timeout: 20, "Main tabs after token sign-in")
        snapshot("onboarding-signed-in")

        // 5. Relaunch restores the stored session (Keychain).
        app.terminate()
        app.launch()
        try wait(tab("Recipes"), timeout: 15, "Session restored after relaunch")

        // 6. Sign out from Settings
        try signOutFromSettings()
        try wait(element(containing: "Welcome to MealMate"), timeout: 10)
        snapshot("onboarding-after-signout")

        // 7. The pasted token is the user's: it must still work and still exist.
        _ = try api.currentUser()
        let tokensAfter = try api.apiTokenNames()
        XCTAssertEqual(tokensAfter, tokensBefore, "Sign-out must not revoke or add API tokens for a pasted token")

        // 8. Stored credentials are gone: a relaunch stays signed out.
        app.terminate()
        app.launch()
        try wait(element(containing: "Welcome to MealMate"), timeout: 10)
        XCTAssertFalse(tab("Recipes").exists)
    }
}
