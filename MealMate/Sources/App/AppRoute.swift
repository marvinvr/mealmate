import Foundation

/// Route registry for deep links (`mealmate://recipe/<slug>`) and the DEBUG
/// launch argument `-MealMateRoute <route>`.
///
/// To add a route, add one line to `registry`: a pattern (`*` captures a path
/// segment) and a builder. Keep this the only place routes are parsed.
enum AppRoute: Equatable, Sendable {
    /// Onboarding: server entry (doesn't touch stored credentials in DEBUG).
    case onboarding
    /// Onboarding at the login screen for `MEALMATE_TEST_SERVER` (or the last server).
    case login
    /// Like `login`, then starts the OIDC sign-in automatically (DEBUG: verify the browser flow).
    case loginOIDC
    /// DEBUG: login screen for a sample `mealie.example.com` server offering OIDC (no network).
    case loginDemo
    /// DEBUG: sign out the stored session (revokes the minted token) and show onboarding.
    case signOut
    case tab(AppTab)
    case settings
    /// Push `destination` onto `tab`'s stack.
    case push(AppDestination, tab: AppTab)
    /// Present `destination` full screen (e.g. cook mode).
    case present(AppDestination)
    /// Show `tab` (pushing `destination` if given, presenting it if `presented`) and leave
    /// `intent` in `AppRouter.pendingIntent` for the screen to act on (open a sheet, a state).
    case intent(String, tab: AppTab, destination: AppDestination? = nil, presented: Bool = false)

    private static let registry: [(pattern: String, make: @Sendable ([String]) -> AppRoute)] = [
        ("onboarding", { _ in .onboarding }),
        ("login", { _ in .login }),
        ("login-oidc", { _ in .loginOIDC }),
        ("login-demo", { _ in .loginDemo }),
        ("signout", { _ in .signOut }),
        ("recipes", { _ in .tab(.recipes) }),
        ("mealplan", { _ in .tab(.mealPlan) }),
        ("shopping", { _ in .tab(.shopping) }),
        ("library", { _ in .tab(.library) }),
        ("settings", { _ in .settings }),
        ("recipe/*", { .push(.recipe(slug: $0[0]), tab: .recipes) }),
        ("cook/*", { .present(.cookMode(slug: $0[0])) }),
        ("shopping/*", { .push(.shoppingList(id: $0[0]), tab: .shopping) }),
        ("cookbook/*", { .push(.cookbook(id: $0[0]), tab: .library) }),
        ("category/*", { .push(.organizer(kind: .category, slug: $0[0]), tab: .library) }),
        ("tag/*", { .push(.organizer(kind: .tag, slug: $0[0]), tab: .library) }),
        ("tool/*", { .push(.organizer(kind: .tool, slug: $0[0]), tab: .library) }),
        // Recipes / recipe detail / cook mode / library states (screens consume the intent).
        ("recipes-list", { _ in .intent("recipes-list", tab: .recipes) }),
        ("recipes-grid", { _ in .intent("recipes-grid", tab: .recipes) }),
        ("recipes-filter", { _ in .intent("recipes-filter", tab: .recipes) }),
        ("recipes-filtered/*", { .intent("recipes-filtered/\($0[0])", tab: .recipes) }),
        ("recipes-favorites", { _ in .intent("recipes-favorites", tab: .recipes) }),
        ("recipes-sort/*", { .intent("recipes-sort/\($0[0])", tab: .recipes) }),
        ("recipes-search/*", { .intent("recipes-search/\($0[0])", tab: .recipes) }),
        ("recipes-new", { _ in .intent("recipes-new", tab: .recipes) }),
        ("recipes-import", { _ in .intent("recipes-import", tab: .recipes) }),
        ("recipes-error", { _ in .intent("recipes-error", tab: .recipes) }),
        ("recipe-scaled/*", { .intent("recipe-scaled", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-cooking/*", { .intent("recipe-cooking", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-steps/*", { .intent("recipe-steps", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-notes/*", { .intent("recipe-notes", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-history/*", { .intent("recipe-history", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-add-to-list/*", { .intent("recipe-add-to-list", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-edit/*", { .intent("recipe-edit", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-comments/*", { .intent("recipe-comments", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-timeline/*", { .intent("recipe-timeline", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-madeit/*", { .intent("recipe-madeit", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-actions/*", { .intent("recipe-actions", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-share/*", { .intent("recipe-share", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-public-link/*", { .intent("recipe-public-link", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("recipe-delete/*", { .intent("recipe-delete", tab: .recipes, destination: .recipe(slug: $0[0])) }),
        ("cook-ingredients/*", { .intent("cook-ingredients", tab: .recipes, destination: .cookMode(slug: $0[0]), presented: true) }),
        ("cook-done/*", { .intent("cook-done", tab: .recipes, destination: .cookMode(slug: $0[0]), presented: true) }),
        ("cook-step/*/*", { .intent("cook-step/\($0[1])", tab: .recipes, destination: .cookMode(slug: $0[0]), presented: true) }),
        ("library-search/*", { .intent("library-search/\($0[0])", tab: .library) }),
        ("library-all/*", { .intent("library-all/\($0[0])", tab: .library) }),
        ("library-cook", { _ in .intent("library-cook", tab: .library) }),
        ("library-cook/*", { .intent("library-cook/\($0[0])", tab: .library) }),
        // Shopping / meal plan states and sheets.
        ("shopping-new", { _ in .intent("shopping-new", tab: .shopping) }),
        ("shopping-add-recipe/*", { .intent("shopping-add-recipe/\($0[0])", tab: .shopping) }),
        ("shopping-adding/*", { .intent("shopping-adding", tab: .shopping, destination: .shoppingList(id: $0[0])) }),
        ("shopping-item/*/*", { .intent("shopping-item/\($0[1])", tab: .shopping, destination: .shoppingList(id: $0[0])) }),
        ("shopping-clear/*", { .intent("shopping-clear", tab: .shopping, destination: .shoppingList(id: $0[0])) }),
        ("shopping-bottom/*", { .intent("shopping-bottom", tab: .shopping, destination: .shoppingList(id: $0[0])) }),
        ("shopping-sections/*", { .intent("shopping-sections", tab: .shopping, destination: .shoppingList(id: $0[0])) }),
        ("mealplan-week/*", { .intent("mealplan-week/\($0[0])", tab: .mealPlan) }),
        ("mealplan-add/*", { .intent("mealplan-add/\($0[0])", tab: .mealPlan) }),
        ("mealplan-note/*", { .intent("mealplan-note/\($0[0])", tab: .mealPlan) }),
        ("mealplan-entry/*", { .intent("mealplan-entry/\($0[0])", tab: .mealPlan) }),
        ("mealplan-suggest/*", { .intent("mealplan-suggest/\($0[0])", tab: .mealPlan) }),
        ("mealplan-add-recipe/*", { .intent("mealplan-add-recipe/\($0[0])", tab: .mealPlan) }),
        ("mealplan-shop/*", { .intent("mealplan-shop/\($0[0])", tab: .mealPlan) }),
        ("mealplan-shop-day/*", { .intent("mealplan-shop-day/\($0[0])", tab: .mealPlan) }),
        // Create / import sheets (presented by `createFlowRouteSheets()`, see CreateFlowRoutes.swift).
        // `import-state/*` and `share-preview/*` only do something in DEBUG builds.
        ("import", { _ in .intent("create:import", tab: .recipes) }),
        ("import/*", { .intent("create:import/\($0[0])", tab: .recipes) }),
        ("import-run/*", { .intent("create:import-run/\($0[0])", tab: .recipes) }),
        ("import-state/*", { .intent("create:import-state/\($0[0])", tab: .recipes) }),
        ("editor-new", { _ in .intent("create:editor-new", tab: .recipes) }),
        ("editor-new/*", { .intent("create:editor-new/\($0[0])", tab: .recipes) }),
        ("editor-edit/*", { .intent("create:editor-edit/\($0[0])", tab: .recipes) }),
        ("editor-edit/*/*", { .intent("create:editor-edit/\($0[0])/\($0[1])", tab: .recipes) }),
        ("share-preview/*", { .intent("create:share-preview/\($0[0])", tab: .recipes) }),
        ("share-preview/live/*", { .intent("create:share-preview/live/\($0[0])", tab: .recipes) }),
    ]

    /// Parses `"recipe/lemon-herb-chicken"`, `"/shopping"`, ...
    init?(string: String) {
        let parts = string.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        for entry in Self.registry {
            let pattern = entry.pattern.split(separator: "/").map(String.init)
            guard pattern.count == parts.count else { continue }
            var captures: [String] = []
            var matches = true
            for (expected, actual) in zip(pattern, parts) {
                if expected == "*" {
                    captures.append(actual.removingPercentEncoding ?? actual)
                } else if expected != actual.lowercased() {
                    matches = false
                    break
                }
            }
            if matches {
                self = entry.make(captures)
                return
            }
        }
        return nil
    }

    /// `mealmate://recipe/<slug>` → `.push(.recipe(slug:))`. The OIDC callback is not a route.
    init?(url: URL) {
        guard url.scheme?.lowercased() == OIDCAuthorizationRequest.callbackScheme,
              let host = url.host(), host != "oauth" else { return nil }
        self.init(string: host + url.path(percentEncoded: true))
    }

    @MainActor
    func apply(router: AppRouter, session: AppSession) {
        switch self {
        case .onboarding, .login, .loginOIDC, .loginDemo, .signOut:
            break // handled by DebugLaunch (needs the harness environment)
        case .tab(let tab):
            router.selectedTab = tab
        case .settings:
            router.isSettingsPresented = true
        case .push(let destination, let tab):
            router.popToRoot(tab)
            router.push(destination, in: tab)
        case .present(let destination):
            router.present(destination)
        case .intent(let intent, let tab, let destination, let presented):
            router.popToRoot(tab)
            router.selectedTab = tab
            router.pendingIntent = intent
            if let destination {
                if presented { router.present(destination) } else { router.push(destination, in: tab) }
            }
        }
    }
}
