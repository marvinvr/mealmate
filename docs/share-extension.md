# Share Extension (MealMateShare)

"Import to Mealie" from Safari's share sheet (or any app sharing text with a link).
Target `MealMateShare` (`com.mealmate-app.ios.share`), sources in `ShareExtension/` plus
shared app files listed in `project.yml`.

## Flow

1. `ShareViewController` hosts `ShareImportView` in a `UIHostingController` and reads the
   first web URL from the extension items: a URL attachment wins, otherwise the first link in
   shared text (`RecipeURLExtractor`). Activation rule: one web URL or text (`Info.plist`).
2. `ShareImportModel.fromStoredCredentials()` builds a `MealieService` from
   `CredentialStore` (App Group defaults + shared Keychain group). No credentials →
   `signedOut` ("Sign In to MealMate First").
3. Phases: `loading` → `noLink` | `signedOut` | `ready` → `importing` → `imported` |
   `duplicate` (existing recipe from the same `orgURL`; import anyway or open it) | `failed`.
4. Import uses the same `RecipeImporter` as the app (respects
   `ImportPreferences.includeOrganizers`). "Open in MealMate" opens
   `mealmate://recipe/<slug>` (or `mealmate://recipes`) by walking the responder chain to
   `UIApplication`, since extensions have no public open-URL API, then closes.

## Rules

- Files compiled into the extension (`MealieService/`, `Models/`, `KeychainStore`,
  `CredentialStore`, `RecipeImporter.swift`, `ShareImportView.swift`, `Theme.swift`, the asset
  catalog) must stay free of app-only code: no `AppRouter`/`AppSession`, no
  `ASWebAuthenticationSession`, no `UIApplication.shared` (`APPLICATION_EXTENSION_API_ONLY`).
- The extension never signs in or stores credentials; it only reads what the app wrote.
  App and extension must keep the same App Group and Keychain access group (`auth.md`).
- Extensions don't inherit the app's global accent: `ShareViewController` sets the Rosemary
  `AccentColor` explicitly (hosting view `tintColor` and `.tint` on the SwiftUI root).

## Verification

The extension can only be opened from a share sheet, so its UI states are screenshotted in
the app via `share-preview/<state>` and `share-preview/live/<url>` (DEBUG, rendered by
`SharePreviewView`; routes in `scripts/README.md`). End to end: `ShareExtensionUITests`
(signs in through the UI so the token lands in the shared Keychain, shares a public recipe
page from Safari, imports, then deletes the recipe and anything it created).
