# API Client

`MealMate/Sources/MealieService/` is the only code that talks to Mealie. Models live in
`MealMate/Sources/Models/`. Reference spec: `docs/mealie-openapi-v3.28.json` (query with `jq`).

## Structure

- `MealieService` (core): a `Sendable` value type with `baseURL`, optional bearer `token`,
  `URLSession.mealie` (20 s request timeout, no URL cache, `User-Agent: MealMate-iOS`) and
  `onUnauthorized`. Cheap to copy; `withToken(_:)` makes a same-server copy.
- `MealieService+<Area>.swift`: `Auth`, `Recipes` (incl. favorites, ratings, timeline,
  comments, recipe actions, create/import/image), `Organizers` (categories, tags, tools,
  cookbooks, foods, units, labels), `Shopping`, `MealPlan`, `Parser`, `Images`.
- `MealieError`, `MealieJSON` (coders + date parser), `ResponseCache`.
- Feature code reads the signed-in client with `@Environment(\.mealie) private var mealie`
  and passes it to its view model. The share extension builds its own from `CredentialStore`.

## Adding an Endpoint

Add a method to the matching area file; keep it a thin, typed wrapper:

```swift
func cookbookRecipes(slug: String) async throws -> Page<RecipeSummary> {
    var query = RecipeQuery(); query.cookbook = slug
    return try await recipes(query)
}
try await send(.get("/api/path/\(id.pathSegment)", query: items))       // decode JSON
try await send(.json(.post, "/api/path", body: encodable), as: T.self)
try await perform(.delete("/api/path/\(id.pathSegment)"))                // ignore body
MealieRequest.form(...) / .multipart(...) / .empty(.post, path)
try await fetchAllPages("/api/paginated", query: items) as [T]           // every page
```

- Escape slugs/IDs with `.pathSegment`. Query `+` is escaped to `%2B` automatically.
- Set `request.authenticated = false` for public endpoints (`/api/app/about`, OIDC, login).
- Paginated responses decode as `Page<Item>`; `RecipeQuery` builds recipe list queries
  (search, sort, organizer filters, cookbook, `queryFilter`, `paginationSeed` for random).

Models: extend `Models/<Area>.swift`. Keep fields optional unless Mealie always sends them.
Helpers in `ModelSupport.swift`: `OpenStringEnum` (string enums that tolerate unknown values),
`MealieDay` (date-only fields), `FlexibleString`, `JSONValue`, `decodeLossyArrayIfPresent`
(one bad element must not fail a list). New response shapes get an anonymized fixture in
`MealMateTests/Fixtures/` and a test in `DecodingTests`.

## Errors

Everything thrown is a `MealieError` whose `errorDescription` is user-facing and can be shown
as is. `MealieError.wrap(error)` converts anything else (URL errors, TLS, cancellation).

- `.unauthorized` (401 on an authenticated request) also triggers `onUnauthorized` → the
  session signs out. Don't handle it in features.
- `.cancelled`: ignore (refresh or view disappearance cancelled the task).
- `isConnectivityProblem` (`.unreachable`, `.timedOut`): keep showing cached data with a hint.
- `detailMessage(from:)` extracts Mealie's `detail` in all its shapes (string,
  `{message, error, exception}`, FastAPI validation arrays).

## Dates

`MealieJSON.decoder` accepts `…+00:00` (lists), `…Z` (details), microseconds, naive
timestamps (treated as UTC) and numeric epochs. Date-only fields (`dateAdded`, meal plan
`date`) are `MealieDay`, never `Date`, so days don't shift across time zones.

## Caching ("instant launch with last data")

```swift
if items.isEmpty, let cached = await mealie.cached([RecipeSummary].self, key: "recipes.recent") {
    items = cached
}
let fresh = try await mealie.recipes(RecipeQuery()).items
items = fresh
await mealie.storeInCache(fresh, key: "recipes.recent")
```

`ResponseCache` (actor) stores JSON in `Caches/ResponseCache/<server>/`, best effort, cleared
on sign-out. Keys are free-form, prefixed with the area (`shopping.list.<id>`).

## Images

Media endpoints need no auth. `recipeImageURL(recipeID:imageKey:size:)` /
`imageURL(for:size:)` build `/api/media/recipes/{id}/images/{original|min-original|tiny-original}.webp?version=<imageKey>`
(WebP only, no `.jpg`). `recipe.image` is a short cache key; `null` means no image. Avatars:
`userAvatarURL(for:)` → `/api/media/users/{id}/profile.webp?cacheKey=<user.cacheKey>`, exactly
like Mealie's web UI; uploading a picture sets a new `cacheKey` (default `"1234"`), and a user
without a picture gets 404. `mediaRequest(_:)` adds the bearer token to a media URL (harmless
on plain Mealie, needed behind auth proxies).

Mealie sends `Cache-Control: no-cache` (+ ETag) on media, so `URLCache` would revalidate every
image on every appearance. Recipe photos therefore go through `RecipeImage` /
`RecipeImageLoader` (`ui.md`), which treats a URL as immutable because `version` changes
with the photo. Avatars (`UserAvatar`) use the same loader, keyed by the `cacheKey` URL; a
404 is remembered until sign-out so a missing picture isn't re-requested.

## Server Quirks (Mealie v3.28)

Recipes

- `PATCH /api/recipes/{slug}` merges the sent top-level fields into the stored recipe and
  returns the full recipe; a sent array (ingredients, steps, notes, tags, categories)
  replaces the stored one. The editor sends only changed fields and sends unchanged lines
  back verbatim (`RecipeDraft`), so nutrition, settings, assets, tools etc. survive. `PUT`
  needs the full recipe.
- New recipes: `POST /api/recipes` takes only a name and returns the slug (JSON string), then
  PATCH the rest. `createRecipe(fromURL:)` also returns the slug.
- Import duplicate check: Mealie stores the source in `orgURL`; query
  `queryFilter=orgURL = "<url>"` before importing.
- `PATCH …/last-made` does **not** add a timeline event: create one for "Made it".
- Ratings: `{"rating": null}` is ignored; sending `0` clears the rating.
  `/api/users/self/favorites` and `/ratings` both return `{ratings: [...]}`.
- Timeline per recipe: `queryFilter=recipe_id="<uuid>"`. Event photo:
  `PUT /api/recipes/timeline/events/{id}/image` (multipart `image` + `extension`), after the
  event exists; the event's `image` then reads `"has image"`.
- Public links: `POST /api/shared/recipes` `{recipeId, expiresAt}`; `GET ?recipe_id=` lists
  them unpaginated (expired ones included: filter client-side). The page is
  `<server>/g/<groupSlug>/shared/r/<tokenId>`, so it needs the user's `groupSlug`.
- `POST /api/recipes/{slug}/duplicate` with `{}` copies everything (assets too) and names it
  "<name> (1)", "(2)", …
- Sub-recipe ingredients: `referencedRecipe` set, no food/unit, `display` is only the
  quantity ("1").
- `GET /api/recipes/suggestions` with no `foods` and no `tools` applies no matching and returns
  every recipe with empty missing lists: only query with a selection. It matches linked foods
  only (unparsed ingredients never match), never reports on-hand foods as missing
  (`includeFoodsOnHand`), and orders by fewest missing, then most matched.

Shopping

- Item create/update/delete return `{createdItems, updatedItems, deletedItems}`: the server
  may merge an added item into a matching existing item instead of creating a new one.
  Apply all three lists; never assume the created item is new.
- `PUT /api/households/shopping/items/{id}` needs the full item, including
  `recipeReferences` unchanged: an update without them drops the references (and the list's
  "added from recipe" entry). Mealie removes them itself when an item is checked.
- `PUT /api/households/shopping/lists/{id}` replaces the list's items with the body's
  `listItems`: a rename without them deletes every item. `renameShoppingList` fetches the list
  and sends its items back.
- The lists endpoint omits `listItems`: fetch a list by ID for its items.
- `POST …/lists/{id}/recipe` takes an array (several recipes, each with
  `recipeIncrementQuantity`) and adds scaled ingredients; adding the same recipe again
  raises the reference's `recipeQuantity`. `…/recipe/{recipeID}/delete` removes them again.
- Section order is per list: `labelSettings` (one per label, created by Mealie for every
  label). `PUT …/lists/{id}/label-settings` takes `[{id, shoppingListId, labelId, position}]`
  (setting ids, not label ids) and returns the full list.

Meal plan and other

- `POST /api/households/mealplans/random` **creates** an entry (respecting the household's
  meal plan rules); it is not a preview. A "suggestion" UI deletes it on undo.
- AI availability: `GET /api/groups/ai-providers/settings` → `aiEnabled`
  (`/api/groups/ai-providers/providers` returns web-UI HTML for non-admins).
- Duplicate API token names are allowed.
