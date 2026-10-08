import XCTest

/// Share extension end to end: sign in for real (pasted token, stored in the shared
/// Keychain group), open a public recipe page in Safari, Share → MealMate → Import. The
/// imported recipe and any categories/tags/tools it created are deleted afterwards, then
/// the app signs out (a pasted token is never revoked).
final class ShareExtensionUITests: MealMateUITestCase {
    /// Public page that Mealie's scraper handles (checked with /api/recipes/test-scrape-url).
    private let pageURL = URL(string: "https://www.bbcgoodfood.com/recipes/easy-pancakes")!
    private var organizersBefore: [String: Set<String>] = [:]
    private var recipesBefore: Set<String> = []
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUpWithError() throws {
        try super.setUpWithError()
        for kind in ["categories", "tags", "tools"] {
            organizersBefore[kind] = try api.organizerIDs(kind)
        }
        recipesBefore = try importedSlugs(all: true)
        if !recipesBefore.isEmpty {
            throw XCTSkip("The test page is already imported on this server; not touching it.")
        }
    }

    override func tearDownWithError() throws {
        if let api {
            // Only organizers that are new AND attached to the imported recipe are removed.
            var attached: [String: Set<String>] = [:]
            for slug in (try? importedSlugs(all: false)) ?? [] {
                if let recipe = try? api.recipe(slug) {
                    for (kind, key) in [("categories", "recipeCategory"), ("tags", "tags"), ("tools", "tools")] {
                        let ids = (recipe[key] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                        attached[kind, default: []].formUnion(ids)
                    }
                }
                api.deleteRecipe(slug)
            }
            for kind in ["categories", "tags", "tools"] {
                let now = (try? api.organizerIDs(kind)) ?? []
                let created = now.subtracting(organizersBefore[kind] ?? []).intersection(attached[kind] ?? [])
                api.deleteOrganizers(kind, ids: Array(created))
            }
        }
        safari.terminate()
        try super.tearDownWithError()
    }

    func testShareFromSafariImportsRecipe() throws {
        try signInWithTokenThroughUI()
        app.terminate()

        safari.open(pageURL)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        try waitForPage()
        snapshot("share-safari-page")

        try openShareSheet()
        snapshot("share-sheet")
        let mealMate = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'MealMate'")).firstMatch
        if !mealMate.waitForExistence(timeout: 8) {
            dump(safari, "share-sheet")
            try fail("MealMate isn't offered in the share sheet")
        }
        mealMate.tap()

        let importButton = safari.buttons.matching(NSPredicate(format: "label ==[c] 'Import to Mealie'")).firstMatch
        if !importButton.waitForExistence(timeout: 15) {
            dump(safari, "share-extension")
            snapshot("share-extension-missing")
            try fail("Share extension UI didn't appear (or isn't signed in)")
        }
        snapshot("share-extension")
        importButton.tap()

        let imported = safari.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Imported'")).firstMatch
        if !imported.waitForExistence(timeout: 60) {
            dump(safari, "share-import-result")
            snapshot("share-import-result")
            try fail("Import didn't finish")
        }
        snapshot("share-imported")
        safari.buttons["Done"].firstMatch.tap()

        // Back in the app: sign out (pasted token stays valid on the server).
        app.launch()
        try wait(tab("Recipes"), timeout: 15)
        try signOutFromSettings()
    }

    // MARK: Safari

    private func waitForPage() throws {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if safari.webViews.firstMatch.exists, safari.webViews.staticTexts.count > 3 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        dump(safari, "safari-page")
        try fail("Safari didn't load the page")
    }

    /// Safari's share button is in the toolbar, or behind the "…" menu in the compact layout.
    private func openShareSheet() throws {
        let share = safari.buttons.matching(NSPredicate(format: "identifier == 'ShareButton' OR label == 'Share'")).firstMatch
        if share.waitForExistence(timeout: 3), share.isHittable {
            share.tap()
        } else {
            let more = safari.buttons.matching(NSPredicate(format: "label IN {'More', 'Page Menu', 'Tab Overview Options'} OR identifier == 'MoreButton'")).firstMatch
            guard more.waitForExistence(timeout: 3) else {
                dump(safari, "safari-toolbar")
                try fail("No share button in Safari")
            }
            more.tap()
            let menuShare = safari.buttons.matching(NSPredicate(format: "label == 'Share'")).firstMatch
            guard menuShare.waitForExistence(timeout: 3) else {
                dump(safari, "safari-menu")
                try fail("No Share item in Safari's menu")
            }
            menuShare.tap()
        }
    }

    private func dump(_ target: XCUIApplication, _ name: String) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "screenshots", directoryHint: .isDirectory)
        try? target.debugDescription.write(to: directory.appending(path: "qa-\(name).txt"), atomically: true, encoding: .utf8)
    }

    // MARK: API

    /// Slugs of recipes imported from `pageURL` (`all`: regardless of name).
    private func importedSlugs(all: Bool) throws -> Set<String> {
        let recipes = try api.items("/api/recipes", query: [URLQueryItem(name: "orderBy", value: "created_at")])
        var slugs: Set<String> = []
        for summary in recipes {
            guard let slug = summary["slug"] as? String else { continue }
            let org = summary["orgURL"] as? String ?? ""
            if org.contains("bbcgoodfood.com/recipes/easy-pancakes") { slugs.insert(slug) }
        }
        return all ? slugs : slugs.subtracting(recipesBefore)
    }
}
