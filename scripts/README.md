# scripts

## screenshot.sh

Light + dark screenshots of one screen, driven by the DEBUG test harness. It
never builds; build first with your own derived data path.

```bash
# one-time: your own simulator (never use other agents' devices)
UDID=$(xcrun simctl create "MealMate-<role>" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$UDID"

# build
xcodegen generate
xcodebuild -project MealMate.xcodeproj -scheme MealMate -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/DD-<role> build

# signed-in screen (token from ~/.config/mise/test-token, server from ~/.config/mise/test-server)
scripts/screenshot.sh --derived-data build/DD-<role> "$UDID" recipes recipes-list

# signed-out screens: no token
scripts/screenshot.sh --no-token --derived-data build/DD-<role> "$UDID" onboarding onboarding-server
scripts/screenshot.sh --no-token --delay 6 --derived-data build/DD-<role> "$UDID" login onboarding-login
```

Output: `screenshots/<name>-light.png` and `screenshots/<name>-dark.png`
(`screenshots/` is git-ignored: it shows real server data).

Options: `--no-token`, `--derived-data <dir>` (or `MEALMATE_DERIVED_DATA`),
`--app <path/to/MealMate.app>`, `--delay <seconds>` (or `MEALMATE_SHOT_DELAY`,
default 4), `--only light|dark`. The status bar is overridden to 9:41 with full
battery/signal.

The token is passed as `SIMCTL_CHILD_MEALMATE_TEST_TOKEN` and never printed.
Never `set -x` around it, never echo it.

## ui-test.sh

Builds and runs the `MealMateUITests` scheme (XCUITest) against the test server.

```bash
scripts/ui-test.sh --derived-data build/DD-<role> "$UDID" [TestClass[/testMethod] ...]
```

Server and token come from the same files as above and reach the test runner as
`TEST_RUNNER_MEALMATE_TEST_SERVER` / `TEST_RUNNER_MEALMATE_TEST_TOKEN`; both are
redacted from the output. The `.xcresult` (which records typed text) is deleted
unless `--keep-results` (then `build/ui-tests.xcresult`, local only). Details:
`docs/development-workflow.md`.

## Routes

The single list of routes. `-MealMateRoute <route>` (DEBUG launch argument) and
`mealmate://<route>` deep links share one registry: `AppRoute.registry` in
`MealMate/Sources/App/AppRoute.swift` (source of truth if this table lags). State
routes leave a one-shot intent for the screen (see `docs/ui.md`). Routes marked
DEBUG do nothing in Release; the harness-only ones (`onboarding`, `login`,
`login-oidc`, `login-demo`, `signout`) need the DEBUG harness.

**Shell and navigation**

| Route | Opens |
| --- | --- |
| `onboarding` | Server entry (stored credentials untouched) |
| `login` | Login screen for the test server (resolved automatically) |
| `login-oidc` | Login screen, then starts OIDC sign-in |
| `login-demo` | Login screen for a sample `mealie.example.com` with OIDC ("Sign in with Authentik"), no network |
| `signout` | Signs out the stored session (revokes the minted token) |
| `recipes`, `mealplan`, `shopping`, `library` | Tab |
| `settings` | Settings sheet |
| `recipe/<slug>` | Recipe detail (pushed on Recipes) |
| `cook/<slug>` | Cook mode (full screen) |
| `shopping/<id>` | Shopping list (pushed on Shopping) |
| `cookbook/<id>`, `category/<slug>`, `tag/<slug>`, `tool/<slug>` | Library recipe list |

**Recipes, detail, cook mode, library**

| Route | Opens |
| --- | --- |
| `recipes-list`, `recipes-grid` | Recipes tab in list / grid layout (not persisted) |
| `recipes-filter`, `recipes-favorites` | Filter sheet / favorites only |
| `recipes-filtered/<kind>:<slug>,…` | Preset filters, e.g. `tag:quick,category:pasta` |
| `recipes-sort/<sort>`, `recipes-search/<text>` | Sorted list / search results (or empty search) |
| `recipes-error` | First-load error state (DEBUG) |
| `recipes-new`, `recipes-import` | Editor / import sheet from the Recipes "+" menu |
| `recipe-scaled/<slug>`, `recipe-cooking/<slug>` | Detail with servings ×2 / first three ingredients checked |
| `recipe-steps/<slug>`, `recipe-notes/<slug>`, `recipe-history/<slug>` | Detail scrolled to a section |
| `recipe-comments/<slug>`, `recipe-timeline/<slug>`, `recipe-madeit/<slug>` | Detail with that sheet open |
| `recipe-add-to-list/<slug>`, `recipe-edit/<slug>`, `recipe-share/<slug>` | Detail with Add to Shopping List / editor / share sheet |
| `recipe-actions/<slug>` | Detail (recipe actions in place) |
| `recipe-public-link/<slug>`, `recipe-delete/<slug>` | Detail with the Public Link sheet / delete confirmation (nothing is deleted) |
| `cook-step/<slug>/<n>`, `cook-ingredients/<slug>`, `cook-done/<slug>` | Cook mode at step n / ingredients sheet / done page |
| `library-search/<text>` | Library search |
| `library-all/<category\|tag\|tool\|cookbooks\|favorites>` | Full organizer list / favorites |

**Shopping and meal plan** (`<day>` = `YYYY-MM-DD`)

| Route | Opens |
| --- | --- |
| `shopping-new` | New list alert |
| `shopping-add-recipe/<slug>` | Add to Shopping List sheet for a recipe |
| `shopping-adding/<id>`, `shopping-bottom/<id>` | List with the add bar focused / scrolled to the bottom |
| `shopping-item/<id>/<itemID>`, `shopping-clear/<id>` | List with the item editor / Clear Checked confirmation |
| `shopping-sections/<id>` | List with the Reorder Sections sheet |
| `mealplan-week/<day>` | Week containing that day |
| `mealplan-add/<day>`, `mealplan-note/<day>` | Entry editor for a recipe / note on that day |
| `mealplan-entry/<entryID>` | Entry editor for an existing entry |
| `mealplan-suggest/<day>` | Suggests a random dinner (creates a real entry) |
| `mealplan-add-recipe/<slug>` | Add to Meal Plan sheet for a recipe |
| `mealplan-shop/<day>`, `mealplan-shop-day/<day>` | Add to Shopping List sheet for the week containing that day / that day only |

**Create and import**

| Route | Opens |
| --- | --- |
| `import`, `import/<url>` | Import sheet (URL prefilled, not started) |
| `import-run/<url>` | Import sheet that starts importing right away (DEBUG; real write) |
| `import-state/<importing\|failed\|unavailable\|duplicate\|ai>` | Import sheet in a fixed state (DEBUG) |
| `editor-new` | New recipe editor (`editor-new/autosave`: scripted create + save, DEBUG) |
| `editor-edit/<slug>`, `editor-edit/<slug>/<section>` | Editor for a recipe (sections DEBUG: ingredients/steps/notes/organize, `tags`/`categories` picker, `autosave`) |
| `share-preview/<ready\|importing\|imported\|duplicate\|failed\|signedout\|nolink>` | Share extension UI rendered in the app (DEBUG) |
| `share-preview/live/<url>` | Share extension UI for a real URL (DEBUG; imports for real) |

Harness env vars (DEBUG builds only): `MEALMATE_TEST_SERVER`,
`MEALMATE_TEST_TOKEN` (ephemeral sign-in, nothing persisted),
`MEALMATE_OIDC_EPHEMERAL=1` (ephemeral web-auth session: skips the iOS
"wants to use … to sign in" alert so OIDC can run unattended).
