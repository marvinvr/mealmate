This is **MealMate**, a free, native SwiftUI iOS app for the self-hosted recipe manager
[Mealie](https://github.com/mealie-recipes/mealie) ("MealMate for Mealie" on the App Store).
The bar: free, fast, beautiful, actually works. `docs/brief.md` holds product intent and scope.

Mandatory for agents: read this `AGENTS.md` before planning, editing, committing or pushing. It
is the repo-local source of truth for workflow, verification and multi-agent git hygiene.

If `AGENTS.local.md` exists (git-ignored, checkout-specific: test server, simulator, publishing
constraints), read it immediately after this file. The test server and token themselves live
outside the repo in `~/.config/mise/test-server` and `~/.config/mise/test-token` (legacy
folder name); `scripts/screenshot.sh` reads them from there.

Then read:

- `docs/codebase-map.md`: where things live. Read it before discovery-heavy work.
- `STYLE.md`: visual source of truth for colors, typography, spacing and materials. Follow it
  for every UI change.
- `docs/README.md` and the topic doc for the area you touch (auth, API, UI, recipes,
  shopping and meal plan, share extension, workflow).

## Essential Context

- **Mealie is the source of truth.** The app stores only the server URL, the token (Keychain)
  and a best-effort response cache. All recipes, lists and plans come from the server.
- **Mealie v3, household-scoped.** Shopping lists, meal plans and recipe actions live under
  `/api/households/...`. Reference API: `docs/mealie-openapi-v3.28.json` (large: grep or `jq`
  targeted parts, never read it whole).
- **One API client.** `MealieService` (value type) plus one `MealieService+<Area>.swift` per
  area. No provider abstractions, no second client.
- **Shared sign-in.** App and share extension share an App Group and a Keychain access group.
  The extension compiles only the files listed in `project.yml` (API client, models,
  credential store, importer + share UI, theme); keep those free of app-only code.
- **No third-party dependencies.**

## Code Style

- SwiftUI views backed by `@MainActor @Observable` view models; views never touch the network.
- Async/await throughout, no Combine. Swift 6 with strict concurrency.
- Cached-first loading, pull-to-refresh on every list, optimistic UI with rollback,
  `ContentUnavailableView` empty/error states that say what to do (see `docs/ui.md`).
- `#Preview` with sample data is welcome; use `example.com` data only.

## Privacy (public repository)

This repo is open source. Never commit real server addresses, tokens, client IDs, user names,
emails or real recipe/list/meal-plan names: not in code, fixtures, tests, previews, docs,
comments or commit messages. Use `https://mealie.example.com` (or `http://mealie.local`) and
fake data ("Lemon Herb Chicken", "Jane Doe", `jane@example.com`). Fixtures are hand-written or
fully anonymized. `screenshots/` shows real data and is git-ignored: never force-add it.
Never print, echo or log the test token; never `set -x` around it.

## Test Data on a Real Server

Reading real data is fine. Anything you create on a server for testing must be named with the
prefix **"MealMate Test"** and deleted when you are done. Never modify or delete existing data.

## Documentation Maintenance

- Keep `docs/` concise and operational: responsibilities, data/control flow, extension
  points, invariants, traps, verification. Don't mirror every method.
- Update the matching doc in the same change when you alter a flow, boundary, reusable
  component, setting, setup step or verification expectation.
- Prefer extending an existing topic doc over adding a new one.
- If a doc and the source disagree, the source wins: fix the doc and mention it in your summary.

## Project Setup

[XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is the source of truth and
`MealMate.xcodeproj` is generated and git-ignored. Run `xcodegen generate` after adding,
removing or renaming any file or changing `project.yml`.

```bash
xcodegen generate
xcodebuild -project MealMate.xcodeproj -scheme MealMate -configuration Debug \
  -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath build/DD-<role> build
```

Do not change bundle IDs, App Group, Keychain group, team, `MARKETING_VERSION` or
`CURRENT_PROJECT_VERSION`. Signing, App Store Connect and TestFlight belong to the maintainer.

## Verification

- After code changes, build (command above). Run `xcodebuild ... test` when you touch logic
  covered by `MealMateTests` or add tests. UI flows against the test server:
  `scripts/ui-test.sh` (`docs/development-workflow.md`).
- UI work: screenshot every screen/state you built, light and dark, with
  `scripts/screenshot.sh` (output in git-ignored `screenshots/`), look at them and iterate.
  Details, debug routes and simulator conventions: `docs/development-workflow.md`.

## Multi-Agent Git Hygiene

Several agents may work in the same working tree at once.

- Stage only your own files with explicit paths; never `git add -A` / `git add .`.
- Never `git stash`, `git reset`, `git checkout -- <file>` or revert other agents' changes.
- Shared files (`project.yml`, `AppDestinationView.swift`, `AppRoute.swift`, models): re-read
  right before editing, keep edits minimal and additive.
- If the build breaks only because of another agent's in-progress files, wait and retry.
- Commit in small steps without attribution trailers. Push the current branch; if rejected,
  `git pull --rebase` and push again. Never force-push. If `index.lock` exists, wait and retry.
