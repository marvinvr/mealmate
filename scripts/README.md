# scripts

## testflight.sh

Builds a commit, signs it for the App Store and uploads it to TestFlight, then waits until
App Store Connect has processed it. Also the mmux process **TestFlight** (`mmux start TestFlight`).

```bash
scripts/testflight.sh [ref] [--dry-run] [--no-wait]
```

- `ref`: commit or ref, default `origin/main` (fetched first). The build comes from `git archive`
  of that commit, so local changes never end up in it.
- `--dry-run`: archive, sign and export the `.ipa` locally, no upload. `--no-wait`: upload only.
- Apple assigns the build number (`manageAppVersionAndBuildNumber`); versions in the repo are
  never changed. A VALID build lands in the internal TestFlight group automatically.

The last line is always `TESTFLIGHT OK platform=ios build=<n> state=VALID id=<build id> commit=<sha>` or
`TESTFLIGHT FAIL platform=ios code=<n> reason=<text> log=<work dir>`.

| Exit | Meaning |
| --- | --- |
| 0 | OK (VALID, or EXPORTED with `--dry-run`) |
| 2 | Usage |
| 3 | Signing: no valid App Store profile for a bundle id (e.g. a new extension), profile expired or INVALID in App Store Connect (capabilities changed), entitlement or app group missing from the profile |
| 4 | Archive (compile) failed, see `archive.log` |
| 5 | Export / upload failed, see `export.log` |
| 6 | Processing ended INVALID (App Store Connect mails the details) |
| 7 | Processing not finished after 45 min (the build may still turn VALID) |
| 8 | Source: unknown ref, `xcodegen`, build settings |
| 9 | Another build of this repo is running |
| 10 | Credentials missing |
| 1 | Unexpected error |

Setup (once per machine, nothing of it in the repo): an env file at `ASC_ENV_FILE` (default
`~/.config/testflight/env`, mode 600) or the same variables in the environment:

```bash
ASC_KEY_ID=<App Store Connect API key id>
ASC_ISSUER_ID=<issuer id>
ASC_KEY_PATH=<path to the .p8>
SIGNING_KEYCHAIN=<optional: keychain with the "Apple Distribution" identity>
SIGNING_KEYCHAIN_PASSWORD_FILE=<optional: file with its password>
```

plus an installed App Store provisioning profile per bundle id (app and every extension), made
with that distribution certificate. The script picks the newest matching one, checks it is
ACTIVE in App Store Connect and covers the target's entitlements, and signs manually with it
(the project itself keeps automatic signing).

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
default 4), `--only light|dark`, `--suffix <text>` (appended to the name, e.g.
`-landscape`), `--width <points>` (iPad: narrow, horizontally compact window like Split
View / Slide Over, DEBUG `-MealMateWindowWidth`; the shot is cropped to it, at 2x or
`MEALMATE_SHOT_SCALE`). The status bar is overridden to 9:41 with full battery/signal.

## sim-orientation.sh

Rotates a simulator (iPad landscape screenshots); `simctl` can't, and iPad apps can't rotate
themselves in windowing modes. Runs the one-line UI test `DeviceOrientationUITests`
(XCUIDevice); the orientation sticks until changed. No server or token involved. Builds the
`MealMateUITests` scheme for testing first if the derived data has no `.xctestrun`.

```bash
scripts/sim-orientation.sh --derived-data build/DD-<role> "$UDID" landscape
scripts/screenshot.sh --derived-data build/DD-<role> --suffix -landscape "$UDID" recipe/<slug> ipad-recipe
scripts/sim-orientation.sh --derived-data build/DD-<role> "$UDID" portrait
```

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
| `library-cook`, `library-cook/<food>,…` | What Can I Cook? with the saved selection / with exactly these foods (replaces the saved selection; `library-cook/-` = empty) |

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
