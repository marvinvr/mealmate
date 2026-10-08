import SwiftUI

/// Main tabs.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case recipes, mealPlan, shopping, library

    var title: String {
        switch self {
        case .recipes: "Recipes"
        case .mealPlan: "Meal Plan"
        case .shopping: "Shopping"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .recipes: "book.pages"
        case .mealPlan: "calendar"
        case .shopping: "cart"
        case .library: "books.vertical"
        }
    }
}

/// Typed navigation targets shared across tabs, deep links and debug routes.
/// Push with `NavigationLink(value: AppDestination.recipe(slug:))` or
/// `router.push(_:)`; full-screen ones via `router.present(_:)`.
/// Rendered by `AppDestinationView` (feature agents replace their case there).
enum AppDestination: Hashable, Identifiable, Sendable {
    case recipe(slug: String)
    case cookMode(slug: String)
    case shoppingList(id: String)
    case cookbook(id: String)
    case organizer(kind: OrganizerKind, slug: String)

    var id: String {
        switch self {
        case .recipe(let slug): "recipe/\(slug)"
        case .cookMode(let slug): "cook/\(slug)"
        case .shoppingList(let id): "shopping/\(id)"
        case .cookbook(let id): "cookbook/\(id)"
        case .organizer(let kind, let slug): "\(kind.rawValue)/\(slug)"
        }
    }
}

/// App-wide navigation state: selected tab, one path per tab, global sheets.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .recipes
    var recipesPath = NavigationPath()
    var mealPlanPath = NavigationPath()
    var shoppingPath = NavigationPath()
    var libraryPath = NavigationPath()

    var isSettingsPresented = false
    /// Full-screen destination (e.g. cook mode), shown over the tab view.
    var presentedDestination: AppDestination?
    /// One-shot UI intent for the screen that's about to show (debug routes / deep links
    /// that open a sheet or a state, e.g. `"recipes-filter"`). The owning screen reads it
    /// on appear and calls `consumeIntent(_:)`. See `AppRoute.intent`.
    var pendingIntent: String?

    /// Prefill for onboarding (debug `login` route, last used server).
    var onboardingPrefill: OnboardingPrefill?
    /// DEBUG harness (`login-oidc` route): start OIDC as soon as the login screen appears.
    var autoStartOIDC = false

    struct OnboardingPrefill: Equatable {
        var serverAddress: String
        /// Resolve the server immediately and continue to the login screen.
        var autoContinue: Bool
        /// DEBUG (`login-demo`): show the login screen for this server without resolving it.
        var resolved: ResolvedServer? = nil
    }

    /// Pushes onto the selected tab's stack (or `tab` if given, switching to it).
    func push(_ destination: AppDestination, in tab: AppTab? = nil) {
        let tab = tab ?? selectedTab
        selectedTab = tab
        switch tab {
        case .recipes: recipesPath.append(destination)
        case .mealPlan: mealPlanPath.append(destination)
        case .shopping: shoppingPath.append(destination)
        case .library: libraryPath.append(destination)
        }
    }

    func present(_ destination: AppDestination) {
        presentedDestination = destination
    }

    /// Returns and clears `pendingIntent` if it starts with `prefix`.
    func consumeIntent(_ prefix: String) -> String? {
        guard let intent = pendingIntent, intent.hasPrefix(prefix) else { return nil }
        pendingIntent = nil
        return intent
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .recipes: recipesPath = NavigationPath()
        case .mealPlan: mealPlanPath = NavigationPath()
        case .shopping: shoppingPath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        }
    }

    /// Back to a clean state (after sign-out).
    func reset() {
        AppTab.allCases.forEach(popToRoot)
        selectedTab = .recipes
        isSettingsPresented = false
        presentedDestination = nil
    }
}
