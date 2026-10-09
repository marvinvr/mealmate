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
  plain `List` (the grid as rows of `RecipeCard`s, at least 2 per row, larger cards and 4–5
  per row on iPad, 1 at accessibility sizes), so the search field is visible under the large
  title from the start.
- `RecipeFilterSheet` applies live; active filters show as removable chips (`ActiveFilterBar`).
  Foods are search-first: selected foods first, then server results (`foods(search:)`,
  250 ms debounce) as you type; nothing else is listed before typing.
- `RecipeUserData.shared`: favorites and own ratings for all screens (cached
  `recipes.userRatings`, refreshed at most every minute, reset per server/token). Toggling a
  heart or rating is optimistic.
- `OrganizerStore.shared`: categories, tags, tools, cookbooks (cached `library.<kind>`,
  refreshed at most every two minutes), shared by Library and the filter sheet.

## What Can I Cook?

- `CookSuggestionsScreen` / `CookSuggestionsModel` (`Features/Library`, `LibraryRoute.whatCanICook`,
  a row under Favorites): the user picks foods they have (search-first chips, 250 ms debounce,
  like the filter sheet) and gets `GET /api/recipes/suggestions` results (limit 30), fewest
  missing first, with "Missing: …" / "You have everything" and substitutions per row.
- `CookPantry` (selected foods, missing-ingredients allowance 0/1/2/3/5, "Count Foods on Hand")
  is kept in `UserDefaults` per server (`cook.pantry.<server>`), cleared on sign-out. Results
  reload (debounced) on every change; the last result is cached (`recipes.suggestions`).
- No selection = no request (see the quirk in `api.md`). Only recipes with parsed ingredients
  (foods linked) can match. Pure logic (`CookSuggestions`: query, texts, allowances) is unit tested.

## Detail and Cook Mode

- `RecipeDetailView` / `RecipeDetailModel`: recipe cached-first (`recipes.detail.<slug>`),
  comments, timeline, household recipe actions (`recipes.actions`). "Made it" (`MadeItSheet`,
  also in cook mode) = `markLastMade` + a timeline event + optional photo upload to the event;
  a failed photo upload still saves the entry. Recipe actions: `post` actions are triggered on the
  server with the current scale; `link` actions open a URL with Mealie's placeholders
  (`${url}`, `${slug}`, `${scale}`, `${servings}`, …) filled by `RecipeActionLink`.
- More menu: Duplicate (`POST …/duplicate`, Mealie names the copy "<name> (1)", then it is
  pushed) and Delete Recipe (confirmation, then pop). Share menu: Public Link…
  (`RecipePublicLinkSheet`: expiring share tokens, copy / share / revoke).
- Servings scaling and ingredient text: `IngredientFormatting` (parsed ingredients are rebuilt
  from quantity × scale, unit, food, note; unparsed free-text ones are shown as entered and never scaled).
  A line linking a sub-recipe (`referencedRecipe`, Mealie's `display` is only "1") shows the
  scaled amount + recipe name and a button that opens it. Substitutions (Mealie ≥ 3.26) show
  as "or <food>, <note>" under the line; `RecipeIngredient.substitutes` reads them from the raw
  JSON the editor sends back unchanged.
- Attachments (`Recipe.assets`) are listed only when the recipe's `showAssets` setting is on,
  like the web UI; they open in the browser (media URLs need no auth).
- `RecipeChanges.shared`: bumped after a create, import, edit, duplicate or delete; every
  `RecipeCollectionContent` hides deleted IDs and reloads page one.
- `CookingSessionStore.shared`: servings, checked ingredients and cook step per recipe,
  shared by detail and cook mode, kept 12 h in UserDefaults, cleared on sign-out.
- `RecipeDetailView` from 900 pt wide (iPad): ingredients beside steps (`wideBody`); below
  that one 680 pt column. The hero height comes from `heroHeight(for:)` (also the threshold
  for the inline title).
- `CookModeView` (full screen via `router.present(.cookMode(slug:))`): one step per page with
  its referenced ingredients, ingredients sheet, done page with "I made this"; disables the
  idle timer while visible. From 1000 pt wide (iPad) `CookIngredientsPanel` replaces the
  sheet and the per-step list: all ingredients beside the steps, the current step's
  highlighted. Keyboard: ← / → step, Esc closes, ⌘I ingredients sheet.

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

Unit: `RecipeFeatureTests` (incl. public links, sub-recipes, substitutions), `RecipeEditorTests`,
`CookSuggestionsTests`. UI: `RecipesUITests`,
`RecipeEditorUITests`. Screenshot routes: `scripts/README.md` (recipes, recipe-, cook-,
library-, library-cook, import, editor-).
