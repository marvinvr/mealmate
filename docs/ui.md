# UI

`STYLE.md` is the visual source of truth (colors, typography, spacing, images, Liquid Glass,
states, haptics, accessibility). This doc covers how screens are wired. Tokens:
`MealMate/Sources/Shared/Theme.swift`.

## App Shell

- `RootView`: onboarding vs. `MainTabView` by `AppSession.phase`; injects `\.mealie`.
- `MainTabView`: four tabs (`AppTab`: recipes, mealPlan, shopping, library), each wrapped in
  `TabRoot` = its own `NavigationStack(path:)` + the `AccountButton` toolbar item (avatar,
  opens Settings) + `.navigationDestination(for: AppDestination.self)`. Also hosts the
  Settings sheet, the full-screen cover (cook mode) and `createFlowRouteSheets()` (import /
  editor sheets requested by routes). Tab bar minimizes on scroll.
- Tab roots (`RecipesView`, `MealPlanView`, `ShoppingListsView`, `LibraryView`) must **not**
  create their own `NavigationStack`. Their toolbar items merge with the account button.
  They keep the default large title and default `.searchable` placement (STYLE.md §8). A
  screen that needs search must not put its primary grid in a `ScrollView`: the Recipes grid
  is a plain `List` of card rows, which shows the field under the large title right away.

## Navigation

- `AppRouter` (`@MainActor @Observable`, `@Environment(AppRouter.self)`): `selectedTab`, one
  `NavigationPath` per tab, `isSettingsPresented`, `presentedDestination` (full screen).
  `push(_:in:)`, `present(_:)`, `popToRoot(_:)`, `reset()` (after sign-out).
- `AppDestination`: typed targets `recipe(slug:)`, `cookMode(slug:)`, `shoppingList(id:)`,
  `cookbook(id:)`, `organizer(kind:slug:)`. Push with
  `NavigationLink(value: AppDestination.recipe(slug: s))` or `router.push(...)`; cook mode via
  `router.present(.cookMode(slug:))`.
- `AppDestinationView`: a thin switch from destination to screen. Add a case to
  `AppDestination` and one line here for every new navigable screen.
- `AppRoute.registry`: the single parser for `mealmate://<route>` deep links and the DEBUG
  `-MealMateRoute` argument. One line per route (`("recipe/*", { .push(.recipe(slug: $0[0]), tab: .recipes) })`).
  The `oauth` host is reserved for the OIDC callback.
- Screen states and sheets (filter sheet, search, cook step, ...) are reached with
  `AppRoute.intent(name, tab:, destination:, presented:)`: the router switches tab, optionally
  pushes/presents, and leaves `router.pendingIntent`; the owning screen reads it on appear via
  `router.consumeIntent("<prefix>")` (one-shot). Consumers: `RecipesView` (`recipes-`),
  `RecipeDetailView` (`recipe-`), `CookModeView` (`cook-`), `LibraryView` (`library-`),
  `ShoppingListsView` / `ShoppingListView` (`shopping-`), `MealPlanView` (`mealplan-`),
  `CreateFlowRouteSheets` (`create:`). The full route list lives in `scripts/README.md`.

## Reusable Components (`Shared/`)

- `RecipeImage`: recipe photo, fills its frame, placeholder while loading or failing. Size:
  hero `.original`, cards `.min`, thumbnails `.tiny`; clip with `.recipeImageShape()`. A
  cached `.min` stands in while `.original` loads. `RecipeImageLoader` (actor): memory
  `NSCache` → disk `Caches/RecipeImages` (300 MB, background revalidation after 7 days) →
  network, de-duplicated, decoded/downsampled off the main thread, 404s remembered,
  cleared on sign-out. Also loads user avatars.
- `UserAvatar` (`App/AccountButton.swift`): round Mealie profile picture of the signed-in
  user (toolbar account button, Settings), initials while loading, without a picture or on
  failure. Settings refreshes `/api/users/self` on open, so a changed picture shows up.
- `RecipeImagePlaceholder`: muted food tone picked deterministically from a seed.
- `RecipeCard` (grid: 4:3 photo, serif title, metadata) and `RecipeRow` (list: 56 pt
  thumbnail); `RecipeMetadataLine`. Rows go in a `NavigationLink`; cards inside `List` rows
  are a `Button` calling `router.push` (a `NavigationLink` there adds a chevron).
- `TagChip`: capsule label for tags/categories/tools/filters; selected = accent wash.
- `UserAvatar` (in `App/AccountButton.swift`).
- `RecipeFormatting`: times, servings, ratings text.
- Modifiers: `.screenBackground()` on every screen root (sheets and onboarding too),
  `.recipeImageShape()`, `.surfaceCard()`, `.primaryActionStyle()` for the one prominent button
  of a screen (never `.glassProminent` directly; it carries the contrast-safe fill).
  Fonts: `.recipeTitle`, `.recipeCardTitle`, `.recipeRowTitle`,
  `.sectionTitle`, `.metadata`, `.stepLabel`, `.cookStep`, `.cookIngredient`.

Add a component here only when two or more features use it; otherwise keep it in the feature.
Feature-level shared pieces: `RecipeCollectionContent` / `RecipeContextMenu`
(`Recipes/RecipeCollectionView.swift`, used by the Recipes tab and every Library list),
`PlanningRecipeThumbnail` and `ActionToast` (`Shopping/PlanningComponents.swift`).

## Sheets

Each brings its own `NavigationStack`; present with `.sheet`. Recipe screens present them
through `RecipeSheet` + `RecipeSheetView` (`Recipes/RecipeIntegrations.swift`).

| Sheet | Feature | Purpose |
| --- | --- | --- |
| `AddToShoppingListSheet(recipe:scale:)` / `(slug:)` | Shopping | Pick a list (last used preselected, or create one), servings, untick what's at home (on-hand foods start unticked) |
| `AddToMealPlanSheet(recipe:)` | MealPlan | Pick a day (next 7 days or any date) and a meal type |
| `RecipeEditorView()` / `(recipe:onSave:)` | RecipeEditor | Create or edit a recipe |
| `ImportRecipeView()` | Import | Import from a URL (duplicate check), AI import when available |
| `MealPlanEntryEditor` | MealPlan | Add/edit an entry: day, meal, recipe (searchable) or note |
| `ShoppingItemEditor` | Shopping | Quantity, unit, food, note, label of one item |
| `RecipeFilterSheet` | Recipes | Favorites, categories, tags, tools, foods; applies live |
| `RecipeCommentsSheet` | RecipeDetail | All comments, add and delete |

## Screen Patterns

- **View model**: `@MainActor @Observable final class`, created by the view with the
  `MealieService` from `@Environment(\.mealie)`. Views never call the network.
  `@Environment(AppSession.self)` gives the current user (`session.currentUser?.id` is
  needed for favorites and ratings).
- **Cached-first**: show `mealie.cached(...)` immediately, refresh, store the fresh value
  (`api.md`). First load without cache: redacted real layout or a centred `ProgressView`.
- **Pull-to-refresh**: `.refreshable` on every server-backed list or grid.
- **Background refresh errors** don't replace cached content: show a small inline note.
  Ignore `MealieError.cancelled`; never handle 401 (the session signs out).
- **Empty/error states**: `ContentUnavailableView` with symbol, short title, one sentence
  that says what to do, at most one `.bordered` action. Search:
  `ContentUnavailableView.search(text:)`.
- **Mutations**: optimistic update, roll back and show the error on failure; `.sensoryFeedback`
  per STYLE.md §9.
- **Lists**: swipe actions and context menus for common actions, share sheets where content
  is shareable.
- **Previews**: `#Preview` with `example.com` sample data only.
