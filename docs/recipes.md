# Recipes, Cook Mode, Editor, Import, Library

Sources: `Features/Recipes`, `RecipeDetail`, `CookMode`, `RecipeEditor`, `Import`, `Library`.
Endpoints: `MealieService+Recipes.swift`, `+Organizers.swift`, `+Parser.swift`.

## Recipe Lists

- `RecipeListModel` drives every recipe list: the Recipes tab and each Library list
  (`RecipeCollectionPreset`: all, favorites, cookbook, category/tag/tool). Search (250 ms
  debounce), sort, `RecipeFilters` (favorites, categories, tags, tools, foods), paging from
  each item's `onAppear`. The first page is cached (`ResponseCache`).
  `RecipeListQueryBuilder` turns preset + filters into a `RecipeQuery` (unit tested).
- `RecipeCollectionContent` renders grid or rows (`RecipeLayout`, persisted per device),
  pull-to-refresh, context menus (`RecipeContextMenu`), empty/error states. Both layouts are a
  plain `List` (the grid as rows of `RecipeCard`s, 2 per row on iPhone, 1 at accessibility
  sizes), so the search field is visible under the large title from the start.
- `RecipeFilterSheet` applies live; active filters show as removable chips (`ActiveFilterBar`).
  Foods are search-first: selected foods first, then server results (`foods(search:)`,
  250 ms debounce) as you type; nothing else is listed before typing.
- `RecipeUserData.shared`: favorites and own ratings for all screens (cached
  `recipes.userRatings`, refreshed at most every minute, reset per server/token). Toggling a
  heart or rating is optimistic.
- `OrganizerStore.shared`: categories, tags, tools, cookbooks (cached `library.<kind>`,
  refreshed at most every two minutes), shared by Library and the filter sheet.

## Detail and Cook Mode

- `RecipeDetailView` / `RecipeDetailModel`: recipe cached-first (`recipes.detail.<slug>`),
  comments, timeline, household recipe actions (`recipes.actions`). "Made it" =
  `markLastMade` + a timeline event. Recipe actions: `post` actions are triggered on the
  server with the current scale; `link` actions open a URL with Mealie's placeholders
  (`${url}`, `${slug}`, `${scale}`, `${servings}`, …) filled by `RecipeActionLink`.
- Servings scaling and ingredient text: `IngredientFormatting` (parsed ingredients are rebuilt
  from quantity × scale, unit, food, note; unparsed free-text ones are shown as entered and never scaled).
- `CookingSessionStore.shared`: servings, checked ingredients and cook step per recipe,
  shared by detail and cook mode, kept 12 h in UserDefaults, cleared on sign-out.
- `CookModeView` (full screen via `router.present(.cookMode(slug:))`): one step per page with
  its referenced ingredients, ingredients sheet, done page with "I made this"; disables the
  idle timer while visible.

## Editor

- `RecipeEditorView` (sheet): create or edit. `RecipeDraft` holds the form; `patch(against:)`
  builds a `RecipePatch` with only changed fields. Unchanged ingredient/step/note lines are
  sent back verbatim (food/unit, `referenceId`, step `ingredientReferences`), so editing
  never drops data the editor doesn't show. Edited lines are parsed via
  `/api/parser/ingredients` when "Recognize amounts" is on, else stored as notes.
- New recipe: `POST /api/recipes` (name) → one PATCH → optional photo upload
  (`RecipePhotoEncoder`: downsampled JPEG) or image from URL.
- `OrganizerPickerView`: multi-select categories/tags, can create missing ones.

## Import

- `ImportRecipeView` / `ImportRecipeViewModel` (sheet): paste a URL → duplicate check
  (`RecipeImporter.existingRecipe`, by `orgURL`) → `POST /api/recipes/create/url`. AI import
  from text or photos only when `aiProviderSettings().isAIAvailable`.
- `ImportPreferences.includeOrganizers` (App Group defaults, off by default): import the
  site's keywords as tags/categories.
- `RecipeImporter.swift` and `ShareImportView.swift` are compiled into the share extension
  too; see `share-extension.md`.

## Verification

Unit: `RecipeFeatureTests`, `RecipeEditorTests`. UI: `RecipesUITests`,
`RecipeEditorUITests`. Screenshot routes: `scripts/README.md` (recipes, recipe-, cook-,
library-, import, editor-).
