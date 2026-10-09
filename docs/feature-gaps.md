# Feature Gaps: Mealie v3.28 vs. MealMate

Inventory of what Mealie offers end users (reference: v3.28.0, September 2026; sources:
release notes v3.0–v3.28, the frontend at tag v3.28.0, `docs/mealie-openapi-v3.28.json`)
compared with MealMate. Admin-only and server-ops features (backups, user/group admin,
maintenance, SMTP/LDAP/OIDC config, AI provider setup, migrations from other apps) are out
of scope on a phone and not listed.

Columns: **Value** = usefulness on an iPhone (high / medium / low). **Effort** = S (hours),
M (a day), L (several days). **Fit** = fits STYLE.md (native, calm, kitchen tool).
Status: ✅ supported, 🆕 built in this round, ⏭ skipped (reason in the last column).

Keep this file current when a gap is closed or Mealie adds something user-facing.

## Recipes: Browse, Search, Filter

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Grid/list, search, sort (name, added, updated, rating, last made, random) | `GET /api/recipes` | high | – | yes | ✅ |
| Filter by categories, tags, tools, foods (any/all), favorites | `GET /api/recipes` | high | – | yes | ✅ |
| **"What can I cook?"** recipe finder: pick ingredients you have, recipes ranked by missing foods/tools, with substitutions (v3.26) | `GET /api/recipes/suggestions` | high | M | yes | 🆕 Library → What Can I Cook? (foods only; picking owned tools ⏭, no test data) |
| Filter by household (recipes of other households in the group) | `households=` | low | S | yes | ⏭ most servers have one household; revisit on request |
| Query-filter builder (relative dates, rating, food labels) | `queryFilter` | low | L | no | ⏭ power-user UI, too heavy for a phone; presets cover the common cases |
| Household-wide timeline ("what we cooked lately") | `GET /api/recipes/timeline/events` | medium | M | yes | ⏭ nice-to-have; per-recipe history exists |

## Recipe Detail

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Hero, times, servings scaling, ingredient check-off, sections | `GET /api/recipes/{slug}` | high | – | yes | ✅ |
| Steps with linked ingredients, notes, nutrition, organizers, source link | – | high | – | yes | ✅ |
| Cook mode (screen awake, step by step) | – | high | – | yes | ✅ |
| Ratings, favorites | `/api/users/{id}/ratings`, `/favorites` | high | – | yes | ✅ |
| Comments (read, add, delete own) | `/api/comments` | medium | – | yes | ✅ (editing a comment ⏭ low value) |
| Timeline / "I made this" with date and note | `last-made` + timeline events | high | – | yes | ✅ |
| **"I made this" with a photo** (camera or library), photos in the history | `PUT /api/recipes/timeline/events/{id}/image` | high | S | yes | 🆕 |
| **Sub-recipes** (`referencedRecipe`, v3.5): ingredient showed only "1" | – | medium | S | yes | 🆕 shows the recipe name, opens it |
| **Ingredient substitutions** (v3.26) | `substitutions` | medium | S | yes | 🆕 "or Pecorino, a little less" under the line |
| **Attachments** (assets: PDFs, scans, photos) when the recipe shows them | `GET /api/media/recipes/{id}/assets/{file}` | medium | S | yes | 🆕 read-only list, opens in the browser |
| **Public link** (expiring share token, works without an account) | `POST/GET/DELETE /api/shared/recipes` | high | S | yes | 🆕 Share → Public Link… |
| **Duplicate** a recipe | `POST /api/recipes/{slug}/duplicate` | medium | S | yes | 🆕 More → Duplicate |
| **Delete** a recipe | `DELETE /api/recipes/{slug}` | medium | S | yes | 🆕 More → Delete Recipe… |
| Household recipe actions (link/post, e.g. "send to Bring") | `/api/households/recipe-actions` | medium | – | yes | ✅ |
| Print (with print preferences) | – (client side) | low | M | ok | ⏭ "Share as Text" covers most uses; AirPrint layout later if asked |
| Download JSON / zip export | `/api/recipes/{slug}/exports` | low | S | no | ⏭ not a phone task |
| Step↔note links (v3.26), images inside steps | – | low | M | ok | ⏭ rare; step text already renders |

## Create, Import, Edit

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Import from URL (+ share extension), duplicate check | `POST /api/recipes/create/url` | high | – | yes | ✅ |
| AI import from text / photos (when the server has AI) | `POST /api/recipes/create/ai` | high | – | yes | ✅ |
| AI import from a video URL (YouTube/TikTok/Instagram, needs an audio provider) | `create/ai` with `url` | medium | S | yes | ⏭ needs a server with an audio provider to verify; URL import already falls back to AI on the server |
| Manual create / edit: name, description, servings, yield, times, ingredients (parsed), steps, notes, categories, tags, photo, source | `POST`/`PATCH /api/recipes` | high | – | yes | ✅ |
| Edit nutrition, tools, recipe settings (public, locked, comments off) | `PATCH /api/recipes/{slug}` | low | M | ok | ⏭ rarely done on a phone; PATCH keeps them intact |
| Step↔ingredient linking, attachments upload in the editor | – | low | L | ok | ⏭ fiddly on a small screen |
| Bulk URL import, HTML/JSON import, zip import | `create/url/bulk`, `create/html-or-json`, `create/zip` | low | M | no | ⏭ desktop workflows |

## Library: Cookbooks and Organizers

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Browse cookbooks, categories, tags, tools; recipe lists per organizer | `/api/households/cookbooks`, `/api/organizers/*` | high | – | yes | ✅ |
| Create cookbooks (query filters), reorder | `POST/PUT /api/households/cookbooks` | low | L | no | ⏭ filter builder belongs to the web UI |
| Create / merge / delete organizers, foods, units, labels (data management) | `/api/organizers/*`, `/api/foods`, … | low | M | no | ⏭ creating tags/categories from the editor is supported |
| Mark tools / foods "on hand" for the household | `PUT /api/foods/{id}`, tools | medium | M | ok | ⏭ on-hand is shown and used by the finder; editing the pantry is a later candidate |

## Shopping Lists

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Lists, items grouped by label, check/uncheck, edit, clear checked, add recipe ingredients (scaled), recipe references | `/api/households/shopping/*` | high | – | yes | ✅ |
| **Section (label) order per list** | `PUT …/lists/{id}/label-settings` | high | S | yes | 🆕 List → More → Reorder Sections… |
| Condensed view / hide labels (v3.28) | client side | low | S | ok | ⏭ MealMate's layout is already compact |
| Share list as text | client side | medium | S | yes | 🆕 List → More → Share as Text |
| Change list owner | `PUT …/lists/{id}` | low | S | ok | ⏭ |

## Meal Planner

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Week view, add recipe or note per day and meal type, move, delete | `/api/households/mealplans` | high | – | yes | ✅ |
| Random suggestion (respects rules) with undo | `POST …/mealplans/random` | medium | – | yes | ✅ |
| **Add the week's (or a day's) recipes to a shopping list** | `POST …/lists/{id}/recipe` (bulk) | high | M | yes | 🆕 Meal Plan toolbar cart / day menu |
| Meal plan rules (which recipes "random" may pick per day/meal) | `/api/households/mealplans/rules` | low | M | ok | ⏭ set once on the web; the random suggestion already respects them |
| iCal feed | – | – | – | – | Mealie has none |

## Account, Household, Other

| Feature | Mealie API | Value | Effort | Fit | Status |
| --- | --- | --- | --- | --- | --- |
| Sign-in (OIDC native, password, API token), account info | `/api/auth/*`, `/api/users/self` | high | – | yes | ✅ |
| Profile picture (shown in the avatar) | `GET /api/media/users/{id}/profile.webp` | medium | S | yes | ✅ |
| Upload a new profile picture | `POST /api/users/{id}/image` | low | S | yes | ⏭ rarely changed; web UI |
| Change password, API tokens, profile fields | `PUT /api/users/*` | low | S | ok | ⏭ web UI; OIDC users have no password |
| Household preferences, members, permissions, invitations | `/api/households/*` | low | M | no | ⏭ admin-ish |
| Notifiers, webhooks (Apprise, meal plan webhooks) | `/api/households/events/*`, `/webhooks` | low | M | no | ⏭ admin-ish |
| Announcements (v3.15) | frontend only | – | – | – | no API |

## Built in This Round

- What Can I Cook? (recipe finder) in the Library.
- Meal plan → shopping list (week or day), section order per shopping list, share a list
  as text.
- Recipe detail: photo for "I made this", public links, duplicate, delete, sub-recipe links,
  substitutions, attachments. Recipe lists now refresh after a create, import, edit,
  duplicate or delete (`RecipeChanges`).

## Candidates for Later

1. Pantry: mark foods and tools on hand (feeds the recipe finder and the shopping sheet).
2. Household timeline ("Recently cooked") in the Library.
3. Edit nutrition and tools in the editor.
4. Widget for today's meals (`TodayMealsProvider` is ready); not a Mealie feature but a
   natural iOS one.
