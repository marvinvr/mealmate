# MealMate: product brief

MealMate ("MealMate for Mealie" on the App Store) is a **native SwiftUI iOS app for
[Mealie](https://github.com/mealie-recipes/mealie)**, the self-hosted recipe manager. Existing
third-party Mealie apps suffer from paywalls, half-working features and cluttered layouts.
MealMate must be the opposite: **free, fast, beautiful, actually works**.

## Hard requirements

1. **Covers Mealie's everyday features** (below) with a genuinely good, native iOS layout
   (iOS 26, Liquid Glass where it fits, SF Symbols, Dynamic Type, dark mode). Not a web wrapper.
2. **"Sign in with your server's login" (OIDC)** as the primary method: no API key, no
   password. Uses Mealie's native OIDC flow (Mealie ≥ v3.23.0):
   - `GET /api/auth/oauth/native/config` → `{authorization_endpoint, client_id, scope}`.
   - The app runs the authorization request itself with **PKCE + state + nonce** in
     `ASWebAuthenticationSession`, redirect URI `mealmate://oauth/callback`.
   - `POST /api/auth/oauth/native/token` with `{code, code_verifier, redirect_uri, nonce}`
     → Mealie token; then mint a long-lived API token (`POST /api/users/api-tokens`) and
     store it in the Keychain.
   - Server admins register the redirect URI at their IdP client (documented in README).
   - Fallbacks: username/password (`POST /api/auth/token`) and pasting an API token. OIDC is
     the prominent button when `/api/app/about` reports `enableOidc: true`; its label uses
     `oidcProviderName` ("Sign in with …").
3. **Nice to use**: pull-to-refresh everywhere, fast search, instant launch with the last data
   then refresh, haptics, swipe actions, context menus, share sheets, empty/error states that
   say what to do.
4. **Free.** An optional tip jar may come later (plan in `supporter.md`, not built).

## Mealie features (v1)

Target: Mealie v3.x (reference v3.28, API in `mealie-openapi-v3.28.json`). Everything is
household-scoped in v3. Servers are user-entered and often plain HTTP on a LAN/VPN, so an ATS
exception is required.

- **Server setup**: enter URL, validate via `GET /api/app/about` (version, OIDC enabled and
  provider name, signup allowed).
- **Recipes**: browse grid/list with images, search, filter by category/tag/tool/food, sort
  (recent, name, rating, last made), favorites (`/api/users/self/favorites`), ratings.
  Detail: hero image, servings scaler, ingredients (check off while cooking), steps (with
  ingredient references), notes, nutrition, times, tags/categories, comments, timeline
  ("Made it" → `PATCH /api/recipes/{slug}/last-made` + timeline event).
  **Cook mode**: large text, screen stays awake, step by step.
- **Create/import**: import from URL (`POST /api/recipes/create/url`, also via a **share
  extension** from Safari), create manually, edit basic fields, upload an image
  (`PUT /api/recipes/{slug}/image`) or set one from a URL. AI import (`/api/recipes/create/ai`)
  only when the server has an AI provider.
- **Recipe actions**: list household recipe actions (`/api/households/recipe-actions`) and
  trigger them (`POST .../{id}/trigger/{slug}`) one tap from the recipe (e.g. a
  "Send to Bring" action).
- **Shopping lists**: lists, items grouped by label, check/uncheck with swipe, add items as
  free text (parsed via `/api/parser/ingredient`), add a recipe's ingredients, clear checked.
- **Meal planner**: week view, add a recipe or note per day and meal type, a widget-ready
  "today" view, random suggestion (`/api/households/mealplans/random`).
- **Library**: browse cookbooks, categories, tags, tools.
- **Foods "on hand"** is server-side; show it where relevant.
- Out of scope for v1: admin, backups, user management, migrations, webhook configuration.

## Quality bar

- Subtle, neutral, native UI with generous whitespace and real typography; nothing
  over-styled. `STYLE.md` is the visual source of truth.
- Architecture: SwiftUI + `@Observable` view models, one `MealieService` API client,
  async/await, xcodegen `project.yml`, no third-party dependencies.
- Every screen verified in the simulator against a real server, light and dark, using a local
  test token file outside the repo (never committed, printed or logged).
- Unit tests for API decoding (recorded, anonymized fixtures) and the OIDC/PKCE helpers.
- Concise agent docs: `AGENTS.md` (+ `CLAUDE.md`), `docs/README.md`, `docs/codebase-map.md`
  and topic docs.

## Distribution

- App `com.mealmate-app.ios`, share extension `com.mealmate-app.ios.share`, display name
  **MealMate**.
- The repo must build with `xcodegen generate && xcodebuild`. Agents never bump versions or
  touch signing; the maintainer handles App Store Connect, signing and TestFlight.
