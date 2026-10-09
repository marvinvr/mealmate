# Shopping Lists and Meal Plan

Sources: `Features/Shopping`, `Features/MealPlan`. Endpoints: `MealieService+Shopping.swift`,
`+MealPlan.swift`, `+Parser.swift`. Server quirks that matter here are in `api.md`.

## Shopping

- `ShoppingListsView` / `ShoppingListsViewModel` (tab root): lists with unchecked counts
  (cached `shopping.lists`), create, rename, delete.
- `ShoppingListView` / `ShoppingListViewModel`: one list (cached `shopping.list.<id>`).
  - Grouping is pure and unit tested (`ShoppingListLayout`): items filed under their label,
    else their food's label; sections in the list's label order, unknown labels by name,
    "No Label" last; items by `position`, then oldest first. Checked items sit in a
    collapsible section, most recent first. Just-checked items stay in place briefly so the
    animation is visible (`keepInPlace`); "Clear Checked" counts and removes those too.
  - Every write is optimistic with per-change rollback; a mutation counter keeps a refresh
    that started earlier from overwriting newer local state. Apply the server's
    `{createdItems, updatedItems, deletedItems}` result. Light polling while visible picks
    up changes from other devices.
  - Add bar: free text → `/api/parser/ingredient` → `ShoppingItemDraft` (unit tested). Only
    foods/units that exist on the server are linked; unknown ones become part of the note,
    so nothing typed is lost and no foods are created. No quantity = 0 (shown without a number).
  - Item updates always send `recipeReferences` back unchanged (see `api.md`).
  - Row text: `ShoppingListItem.displayText`. Free-text items (no food/unit) with quantity
    0 or 1 show only the note: Mealie's web UI creates them with quantity 1 and its
    `display` would read "1 2 Lemons".
- `ShoppingItemEditor`: quantity, unit, food, note, label (`ShoppingCatalog`, cached
  `shopping.units` / `shopping.labels`).
- `AddToShoppingListSheet`: adds a recipe's ingredients with a servings scale via
  `POST …/lists/{id}/recipe`; last used list preselected; foods marked on hand start unticked.
- `ShoppingListChoice` + `ShoppingListPickerRow`: the target-list picker shared by both
  "add to list" sheets (cached lists, last used preselected via `shopping.lastListID`,
  "New List…" when there is none).

## Meal Plan

- `MealPlanView` / `MealPlanViewModel` (tab root): one week at a time (cached per week),
  entries per day in meal order, add (recipe or note), move (drag between days, or edit),
  delete, all optimistic with rollback. Scrolls to today on first appear and after "Today".
- `MealPlanWeek`: weeks of `MealieDay`s starting on the locale's first weekday, built from
  whole days (never "+ 7 × 24 h") so DST can't shift a day. Unit tested with `MealPlanLayout`.
- "Suggest a recipe": `POST /api/households/mealplans/random` creates a real entry; the
  toast's Undo deletes it.
- `TodayMealsProvider`: today's entries, cached (`mealplan.today`, only for the current day),
  kept up to date by `MealPlanViewModel`. Not shown in the UI (the Today card was removed);
  it stays self-contained for a future widget.
- `MealPlanEntryEditor`: day, meal type, recipe (debounced search) or note.
- `AddToMealPlanSheet`: a recipe to a day (next 7 days or any date) and meal type.
- Shop for the plan: the cart button in the toolbar ("Add Week to Shopping List") and
  "Add Day to Shopping List…" in a day's + menu (days with recipes only) open
  `MealPlanShoppingSheet`. It lists the shown week's recipe entries by day (notes excluded;
  day mode shows only that day); today and later start ticked, past days unticked. Rules in
  `MealPlanShopping` (unit tested): a recipe planned n times becomes one request with
  `recipeIncrementQuantity` n, all sent in one `POST …/lists/{id}/recipe`.

Shared small views: `PlanningRecipeThumbnail`, `ActionToast` (`PlanningComponents.swift`).

## Verification

Unit: `PlanningTests` (layout, item parsing, weeks, meal ordering, add-to-list model,
meal plan shopping). UI:
`ShoppingUITests`, `MealPlanUITests` (they create and delete "MealMate Test UI …" data).
Screenshot routes: `shopping-*`, `mealplan-*` in `scripts/README.md`.
