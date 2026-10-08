# Development Workflow

Build, test and verify MealMate. Rules for git and privacy are in `AGENTS.md`.

## Setup

```bash
brew install xcodegen      # once
xcodegen generate          # after any project.yml change or file add/remove/rename
```

Xcode 26+ (developed with Xcode 27). Deployment target iOS 26.0; current simulators run the
iOS 27 runtime. `MealMate.xcodeproj`, `build/` and `screenshots/` are git-ignored.

## Simulators

Use your own simulator so parallel agents don't collide, and your own derived data:

```bash
UDID=$(xcrun simctl create "MealMate-<role>" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$UDID"
# ... work ...
xcrun simctl delete "$UDID"   # when done
```

Never use, shut down or erase simulators you didn't create.

## Build and Test

```bash
xcodebuild -project MealMate.xcodeproj -scheme MealMate -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/DD-<role> build

xcodebuild -project MealMate.xcodeproj -scheme MealMate \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/DD-<role> test
```

Unit tests use Swift Testing in `MealMateTests/`: decoding, dates, PKCE/OIDC, server
address parsing and routes, plus feature logic (`RecipeFeatureTests`: quantities, scaling,
ingredient display, durations, list queries; `RecipeEditorTests`: draft ↔ PATCH mapping,
ingredient lines, shared-URL extraction; `PlanningTests`: shopping grouping, item parsing,
weeks, meal ordering). Fixtures in `MealMateTests/Fixtures/` are anonymized JSON loaded by
`Fixtures.swift`. Add focused tests for view-model logic (scaling math, grouping, date
ranges, parsing).

## UI Tests (XCUITest, real server)

`MealMateUITests` (scheme `MealMateUITests`, not part of the `MealMate` scheme's tests) taps
through onboarding + token sign-in/sign-out, recipes (search, scaling, check-off, cook mode,
filters, favorite/rating), the editor, shopping, the meal plan and the share extension
(Safari → Share → MealMate) against the test server:

```bash
scripts/ui-test.sh --derived-data build/DD-<role> "$UDID"                    # all
scripts/ui-test.sh --derived-data build/DD-<role> "$UDID" ShoppingUITests    # one class
scripts/ui-test.sh --derived-data build/DD-<role> "$UDID" RecipesUITests/testFilterSheetApplyAndClear
```

The script hands server + token to the runner as `TEST_RUNNER_MEALMATE_TEST_*` (never in
files), redacts both from the output and deletes the result bundle (XCTest logs typed text),
unless `--keep-results`. Without the variables every test skips. Tests create only
"MealMate Test UI …" data (or one imported test recipe) and delete it in `tearDown`; the
pasted token is never revoked. Screenshots: `screenshots/qa-*.png`; on failure also
`qa-failure-*.png/.txt` (accessibility hierarchy). Turn off autocorrect on the simulator first
(`xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardAutocorrection -bool NO`).
Signed-in tests use the DEBUG harness (`launchSignedIn`); onboarding and the share extension
sign in through the UI so the token lands in the Keychain.

## Test Server and Token

The DEBUG harness signs in with `MEALMATE_TEST_SERVER` + `MEALMATE_TEST_TOKEN` (ephemeral,
nothing persisted). `scripts/screenshot.sh` reads them from `~/.config/mise/test-server` and
`~/.config/mise/test-token` (outside the repo; override with `MEALMATE_TEST_SERVER_FILE` /
`MEALMATE_TEST_TOKEN_FILE`) and passes the token via `SIMCTL_CHILD_*` without printing it.

For `curl` checks, read the token into a variable only:
`TOKEN=$(cat ~/.config/mise/test-token)` then `-H "Authorization: Bearer $TOKEN"`. Never
echo it, never `set -x`, never paste it into files, logs or commit messages.

Test data you create on the server: prefix **"MealMate Test"**, delete it afterwards. Never
modify existing data.

## Screenshots

```bash
scripts/screenshot.sh --derived-data build/DD-<role> "$UDID" recipes recipes-list
scripts/screenshot.sh --no-token --derived-data build/DD-<role> "$UDID" onboarding onboarding-server
```

Installs the already built app (never builds), launches it with the route in light and dark
and writes `screenshots/<name>-{light,dark}.png` (status bar 9:41). Options: `--no-token`,
`--delay <s>`, `--only light|dark`, `--app <path>`. Name shots `<area>-<screen>`. Look at
every screenshot and iterate. They show real server data: never commit them.

## Debug Routes

`-MealMateRoute <route>` (DEBUG) and `mealmate://<route>` share `AppRoute.registry`. The full
list (shell, recipe, shopping, meal plan, create/import and share-preview routes) lives only
in `scripts/README.md`; keep it in sync when you add a route. Add one for every screen, sheet
or state you need to screenshot (one registry line, consumed as an intent, see `ui.md`).
`MEALMATE_OIDC_EPHEMERAL=1` lets the OIDC flow run without the system consent alert.

## Before Finishing

- `xcodegen generate` if files changed; build succeeds; tests pass if you touched tested logic.
- UI: light + dark screenshots reviewed.
- Docs updated for changed flows, components or routes (`docs/README.md` lists owners).
- Server test data deleted; simulator deleted.
