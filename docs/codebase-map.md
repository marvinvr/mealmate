# Codebase Map

Fast orientation for `MealMate/Sources` and friends. Ownership and flow, not a symbol index.
Confirm details in source: `find MealMate/Sources -type f | sort`.

## Top-Level Shape

```text
project.yml            XcodeGen source of truth (MealMate, MealMateShare, MealMateTests, MealMateUITests)
STYLE.md               Visual source of truth
MealMate/
  Sources/
    App/               Entry, root switch, tab shell, router, route registry, debug harness
    Auth/              Session, sign-in flows, OIDC/PKCE, web auth, Keychain, credential store
    MealieService/     API client core + one extension file per area, errors, JSON, cache
    Models/            Codable DTOs, one file per area
    Features/
      Onboarding/      Server entry, login (OIDC / password / token)
      Recipes/         Recipes tab, shared recipe list (grid/list, search, sort, filters), sheets hub
      RecipeDetail/    Detail screen, ingredient formatting/scaling, cooking session state
      CookMode/        Full-screen step-by-step cooking
      RecipeEditor/    Create/edit sheet, draft ↔ PATCH mapping, photos, organizer picker
      Import/          Import sheet (URL + AI), importer + share UI shared with the extension
      Library/         Library tab, organizer store, preset recipe lists
      Shopping/        Lists, list screen, item editor, add-recipe sheet, planning components
      MealPlan/        Week view, entry editor, add-to-plan sheet, week math, today provider
      Settings/        Account, server, about, sign out
    Shared/            Theme.swift (tokens, fonts, modifiers), RecipeFormatting, Components/
  Resources/           Assets.xcassets (AppIcon, AccentColor, background/surface/prominent colors)
  Support/             Info.plist, MealMate.entitlements
ShareExtension/        MealMateShare: ShareViewController hosting ShareImportView
MealMateTests/         Swift Testing; Fixtures/ = anonymized JSON responses
MealMateUITests/       XCUITest flows against a real server (scripts/ui-test.sh)
scripts/               screenshot.sh, ui-test.sh + README (route list, harness)
Design/                make-icon.swift (app icon generator)
```

## App Lifetime

`MealMateApp` creates `AppSession` and `AppRouter`, enlarges `URLCache.shared`, runs the
DEBUG harness (`DebugLaunch`) or `session.restore()` before the first frame, and injects both
into the environment. `RootView` switches on `session.phase`:

```text
.signedOut -> OnboardingFlowView (ServerEntryView -> LoginView)
.signedIn  -> MainTabView, with \.mealie = session.service
```

`RootView` also handles `mealmate://` deep links via `AppRoute(url:)` and resets the router
on sign-out.

## Boundaries

- **App/**: `MainTabView` owns one `NavigationStack` per tab (`TabRoot`), the account
  button, the settings sheet, the full-screen cover and `createFlowRouteSheets()`.
  `AppDestinationView` is a thin switch from `AppDestination` to screens. See `ui.md`.
- **Auth/**: getting and keeping a token. See `auth.md`.
- **MealieService/**: the only code that talks HTTP to Mealie. See `api.md`.
- **Models/**: plain `Codable` + `Sendable` types; no networking, no UI.
- **Features/<Area>/**: views + `@MainActor @Observable` view models; feature docs in
  `recipes.md`, `shopping-and-mealplan.md`, `share-extension.md`.
- **Cross-feature sheets** go through `Features/Recipes/RecipeIntegrations.swift`
  (`RecipeSheet` / `RecipeSheetView`), so recipe screens don't depend on other features'
  internals. `Shopping/PlanningComponents.swift` holds views shared by Shopping and Meal Plan.
- **App-wide stores** (`.shared` singletons, reset per server/token or on sign-out):
  `RecipeUserData` (favorites, own ratings), `OrganizerStore` (categories, tags, tools,
  cookbooks), `CookingSessionStore` (servings, check marks, cook step), `RecipeImageLoader`.
- **Shared/**: reusable UI and formatting with no feature knowledge.
- **ShareExtension/**: compiles `MealieService/`, `Models/`, `KeychainStore`,
  `CredentialStore`, `Features/Import/RecipeImporter.swift`, `Features/Import/ShareImportView.swift`,
  `Shared/Theme.swift` and the asset catalog (see `project.yml`). Those files must stay free
  of app-only code (app shell, `ASWebAuthenticationSession`, `UIApplication.shared`).

## Where New Code Goes

- New endpoint: the matching `MealieService+<Area>.swift`; new/changed DTO in
  `Models/<Area>.swift`; fixture + decoding test in `MealMateTests`.
- New screen: `Features/<Area>/`, plus an `AppDestination` case and a line in
  `AppDestinationView` if it is navigated to, plus a route in `AppRoute.registry` for
  screenshots/deep links (listed in `scripts/README.md`).
- A sheet another feature presents from a recipe: a `RecipeSheet` case.
- Reusable view used by two or more features: `Shared/Components/`.
- Design tokens: `Shared/Theme.swift` and `Resources/Assets.xcassets`, together with `STYLE.md`.
- Files added/removed/renamed: run `xcodegen generate`.
