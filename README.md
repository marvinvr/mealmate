# MealMate

A free, native iOS app for [Mealie](https://github.com/mealie-recipes/mealie), the
self-hosted recipe manager. On the App Store as **MealMate for Mealie**.

MealMate is built with SwiftUI for iOS 26: native navigation, Liquid Glass, SF Symbols,
Dynamic Type and dark mode. It is not a web wrapper, has no paywall and no ads.

> MealMate is an independent project. It is not affiliated with or endorsed by the Mealie
> project.

## Features

- **Recipes**: browse with photos, fast search, filter by category, tag, tool or food,
  sort by recent, name, rating or last made; favorites and ratings.
- **Recipe detail**: servings scaler, ingredients you can check off, steps with ingredient
  references, notes, nutrition, times, comments and timeline ("Made it").
- **Cook mode**: large text, step by step, the screen stays awake.
- **Import**: from a URL, or straight from Safari and other apps via the share extension.
  AI import when your server has an AI provider configured.
- **Editor**: create recipes manually, edit the basics, ingredients, steps, notes, tags and
  categories, set an image from your photos, the camera or a URL.
- **Recipe actions**: trigger your household's recipe actions (e.g. a "Send to Bring" action)
  with one tap.
- **Shopping lists**: items grouped by label, swipe to check, free-text items parsed by Mealie,
  add a recipe's ingredients, clear checked items.
- **Meal planner**: week view that opens on today, recipes or notes per day and meal type, drag
  to move, random suggestions with undo; add any recipe to the plan from its page.
- **Library**: cookbooks, categories, tags and tools.
- Pull to refresh everywhere, instant launch with your last data, haptics, context menus and
  share sheets.

## Requirements

- iOS 26 or later.
- A Mealie server running **v3.x** (MealMate uses the household-scoped v3 API; developed
  against v3.28).
- Sign-in with your server's identity provider (OIDC) needs **Mealie v3.23.0 or later**,
  the release that added Mealie's native OIDC endpoints. Username/password and API token
  sign-in work on any v3 server.

## Signing in

Enter your server address (`https://mealie.example.com`, a LAN address or a reverse-proxy
sub-path all work), then choose one of:

1. **Sign in with <your provider>**: shown when your server has OIDC enabled. Needs a
   one-time setup at your identity provider, see below.
2. **Username and password**: when your server allows password login.
3. **API token**: create one in Mealie under *Profile → API Tokens* and paste it.

For OIDC and password sign-in MealMate creates a long-lived API token named
"MealMate on <device>" in your Mealie profile and keeps it in the iOS Keychain. Signing out
deletes that token on the server. A token you pasted yourself is never deleted.

## OIDC setup for your own identity provider

MealMate uses Mealie's **native OIDC flow**: the app opens your provider's login page in the
system browser (so saved logins and passkeys work), receives the authorization code at its
own redirect URI and hands the code to Mealie, which exchanges it with your provider.

### 1. Mealie must have OIDC configured

Set up OIDC for Mealie's web login first, as described in the
[Mealie OIDC docs](https://docs.mealie.io/documentation/getting-started/authentication/oidc-v2/)
(`OIDC_AUTH_ENABLED`, `OIDC_CONFIGURATION_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`).
`OIDC_PROVIDER_NAME` sets the button label ("Sign in with …"). No extra Mealie setting is
needed for native clients: the native endpoints are available whenever OIDC is configured.

### 2. Register MealMate's redirect URI at your provider

Add this redirect URI to the **same OIDC client that Mealie uses**:

```
mealmate://oauth/callback
```

Keep the existing web redirect URI (`https://mealie.example.com/login`) as well.

Why the same client: MealMate builds the authorization request with the `client_id` it gets
from your Mealie server, and Mealie exchanges the code with its own client ID and secret and
verifies the returned ID token for that client. A separate client for MealMate would not be
accepted by Mealie. The registered redirect URI is the only extra access control, and your
provider enforces it.

Notes:

- The client stays a **confidential** client. Its secret is known only to Mealie; MealMate
  never sees it.
- MealMate always sends **PKCE (S256)**, `state` and `nonce`. Requiring PKCE at your
  provider is fine.
- Providers that insist on a separate public client for native apps (notably Google and
  Microsoft Entra ID) are not supported by Mealie's native flow yet.

### Provider hints

Add the redirect URI wherever your provider lists the allowed redirect or callback URLs of
the Mealie client:

- **Authentik**: the OAuth2/OpenID provider used by Mealie, *Redirect URIs*.
- **Authelia**: the Mealie entry under `identity_providers.oidc.clients`, `redirect_uris`.
- **Keycloak**: the Mealie client, *Valid redirect URIs*.
- **Pocket ID**: the Mealie OIDC client, *Callback URLs*.
- **Tailscale (tsidp)**: the redirect URIs of the client Mealie uses. Your phone must be on
  the tailnet to reach the login page.

### Troubleshooting

- **The provider shows "invalid redirect_uri" or "redirect URI mismatch"**: the redirect URI
  is missing or mistyped on the client Mealie uses. It must be exactly
  `mealmate://oauth/callback`.
- **No "Sign in with …" button**: your server reports `enableOidc: false`
  (see `https://mealie.example.com/api/app/about`), so OIDC is not enabled or not fully
  configured in Mealie.
- **The button is there but sign-in fails right away**: the server is older than v3.23.0
  and has no native OIDC endpoints. Update Mealie, or use password or API token sign-in.
- **The provider login works but Mealie rejects it**: check Mealie's logs. Typical causes are
  a user outside `OIDC_USER_GROUP`, or a new user while `OIDC_SIGNUP_ENABLED` is off.

## Plain HTTP servers

Many self-hosted servers run on plain HTTP inside a home network or VPN. Server addresses are
only known at runtime, so MealMate's App Transport Security settings allow arbitrary loads.
MealMate only talks to the server you entered. Prefer HTTPS, or keep plain HTTP inside a VPN:
over plain HTTP your token travels unencrypted.

## Building from source

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open MealMate.xcodeproj
```

`project.yml` is the source of truth; the Xcode project is generated and not committed.

Simulator builds work as is. To run on a device, use your own signing setup: set
`DEVELOPMENT_TEAM` and the bundle IDs in `project.yml`, and change the App Group
(`group.com.mealmate-app.ios`) and Keychain access group (`com.mealmate-app.ios.shared`)
in both `.entitlements` files, `MealMate/Support/Info.plist` and `CredentialStore.appGroupID`
to identifiers your team owns. App and share extension must share the same App Group and
Keychain group, otherwise the extension can't use your sign-in.

Run the tests (any installed iPhone simulator works):

```bash
xcodebuild -project MealMate.xcodeproj -scheme MealMate \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Contributing

Issues and pull requests are welcome. Please:

- keep the app native (SwiftUI, system components) and free of third-party dependencies;
- follow [`STYLE.md`](STYLE.md) for UI and [`AGENTS.md`](AGENTS.md) for architecture and
  workflow (written for coding agents, but it applies to humans too);
- run the tests before opening a PR;
- never commit server addresses, tokens or personal data; use `mealie.example.com` in
  examples and fixtures.

Developer docs live in [`docs/`](docs/README.md).

## License

MealMate is released under the [MIT License](LICENSE). Mealie is a separate project with its
own license.
