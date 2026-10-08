# Auth

Getting, storing and dropping a Mealie token. Sources: `MealMate/Sources/Auth/`,
`MealieService+Auth.swift`, `Features/Onboarding/`, `Models/Auth.swift`, `Models/AppInfo.swift`.

## Server Setup

`ServerEntryViewModel` turns the input into candidate URLs (`ServerAddress.candidates`:
without a scheme, https then http; web-UI/API suffixes are stripped, reverse-proxy sub-paths
kept) and accepts the first that answers `GET /api/app/about` like Mealie (otherwise
`MealieError.notMealie`). The resulting `ResolvedServer` (URL + `AppInfo`) drives `LoginView`:

- `enableOidc` → primary "Sign in with <oidcProviderName>" button (fallback "Sign in with SSO").
- `allowPasswordLogin` (missing on old servers = allowed) → password form; it is primary and
  open when OIDC is off.
- "Use API token" is always available.

## Native OIDC Flow (primary)

`SignInFlow.signInWithOIDC()`, Mealie ≥ v3.23.0:

1. `GET /api/auth/oauth/native/config` (unauthenticated) → `authorization_endpoint`,
   `client_id`, `scope`. 404 means OIDC is not configured or the server is too old.
2. `OIDCAuthorizationRequest` builds the authorize URL: `response_type=code`, `client_id`,
   `redirect_uri=mealmate://oauth/callback`, `scope`, random `state` and `nonce`, PKCE
   `code_challenge` (S256, `PKCE.generate()`). Existing query items on the endpoint are kept;
   `+` is escaped.
3. `WebAuthenticator` opens it in `ASWebAuthenticationSession` with callback scheme
   `mealmate` and a **shared** browser session (reuses IdP cookies and passkeys). It anchors
   to the key window itself because SwiftUI's environment action failed when called early.
4. `authorizationCode(from:)` validates the callback: scheme, `error` (`access_denied` →
   cancelled, a redirect-related `invalid_request` → "allow mealmate://oauth/callback"
   message), `state` equality, non-empty `code`.
5. `POST /api/auth/oauth/native/token` `{code, code_verifier, redirect_uri, nonce}`. Mealie
   exchanges the code with its own confidential client (ID + secret), validates the ID token
   and nonce, provisions the user and returns `{access_token, token_type, expires_in}` (a
   48 h session token).
6. Shared tail (below).

The redirect URI must be registered on the **same** IdP client Mealie uses; the client
secret never reaches the app. User-facing setup and IdP hints live in the root `README.md`.

## Password and API Token

- Password: `POST /api/auth/token` (form: `username`, `password`, `remember_me=true`) → session
  token. 401 → `SignInError.wrongCredentials`.
- API token: trimmed, a leading `Bearer ` stripped, validated directly. 401 →
  `SignInError.invalidToken`. Never minted or revoked by the app.

## Shared Tail, Storage, Sharing

`SignInFlow.finish` mints a long-lived token for OIDC and password sessions
(`POST /api/users/api-tokens`, name "MealMate on <device name>"; duplicates are allowed by
Mealie), validates with `GET /api/users/self` and returns a `SignInResult`. If minting fails,
the session token is kept (it simply expires sooner).

`AppSession.signIn(with:)` persists through `CredentialStore`:

- Token → Keychain via `KeychainStore` (service `com.mealmate-app.ios`, account
  `mealie-token`, `AfterFirstUnlock`). Access group from Info.plist key
  `MealMateKeychainAccessGroup` = `$(AppIdentifierPrefix)com.mealmate-app.ios.shared`; falls
  back to the default group only when `SecItemAdd` reports `errSecMissingEntitlement` or
  `errSecNoAccessForItem`; reads try the shared group first, then the default.
- Server URL, minted token ID, cached `User` and `AppInfo`, last server URL → App Group
  defaults `group.com.mealmate-app.ios` (falls back to `.standard`).
- Both are readable by the share extension, which compiles `KeychainStore` and
  `CredentialStore`.

**Simulator vs device.** `codesign -d --entitlements` on a simulator build shows an empty
dict because simulator apps are ad-hoc signed; Xcode embeds the entitlements in the
`__TEXT,__entitlements` section instead (`*-Simulated.xcent`, team prefix expanded), and the
simulator enforces those. Verified: the token item lands in
`<TeamID>.com.mealmate-app.ios.shared` and the share extension finds the sign-in
(`ShareExtensionUITests`). No signing changes are needed for simulator builds. On device,
Automatic signing puts the same groups into the profile; the fallback only matters for a
build without the entitlement, and then the extension shows "Sign In to MealMate First".

On launch `restore()` activates the stored session immediately with the cached user/app info
and refreshes both in the background (network errors keep the cache).

## Sign-Out and Revocation

- `AppSession.signOut()`: clears `CredentialStore`, revokes the minted token
  (`DELETE /api/users/api-tokens/{id}`, best effort, detached), clears `ResponseCache`,
  `RecipeImageLoader` (memory + disk) and `CookingSessionStore`, resets the router (via
  `RootView`).
- Only a token MealMate minted itself (`mintedTokenID` set) is revoked. A pasted API token
  belongs to the user and is never deleted on the server (covered by `OnboardingUITests`).
- Any authenticated 401 calls the service's `onUnauthorized` → sign-out with a reason shown
  in onboarding. That path does **not** call the server (the token is already invalid). A
  late 401 from a previous session's token is ignored. Feature code never handles 401 itself.

## DEBUG Harness

Compiled out of Release (`DebugLaunch`, `WebAuthenticator.prefersEphemeralSession`):

- `MEALMATE_TEST_SERVER` + `MEALMATE_TEST_TOKEN`: ephemeral sign-in at launch, nothing
  persisted, nothing revoked.
- `-MealMateRoute <route>`: `onboarding`, `login`, `login-oidc` (starts OIDC on appear),
  `login-demo` (sample OIDC server, no network), `signout` (revokes the stored minted token)
  and all screen routes, see `development-workflow.md`.
- `MEALMATE_OIDC_EPHEMERAL=1`: ephemeral web-auth session, which skips the iOS
  "wants to use … to sign in" alert so OIDC can run unattended.

## Verification

Automated: `PKCETests`, `OIDCAuthorizationTests` (URL building, callback validation),
`ServerAndRouteTests`, `DecodingTests` (`oidc-native-config.json`, `api-token-create.json`).
UI tests: `OnboardingUITests` (server entry, password validation, token sign-in, restore,
sign-out without revoking a pasted token), `ShareExtensionUITests` (shared Keychain group).

Verified once end to end against a real server: config fetch, authorize URL accepted by the
IdP (302 to `mealmate://oauth/callback?code=…&state=…`), code exchange with nonce, and in the
simulator with `MEALMATE_OIDC_EPHEMERAL=1` sign-in → minted token → tabs, session restore on
relaunch, and revocation via the `signout` route.

Has to be checked by hand on a device or a normal simulator run after auth changes: tap
"Sign in with …", confirm the system alert with **Continue**, complete the IdP login (passkey
or account), land in the Recipes tab; relaunch restores the session; Settings → Sign Out
removes "MealMate on <device>" from Mealie → Profile → API Tokens.
