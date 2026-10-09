# Supporter Tier

MealMate stays **fully free**: every feature works without paying. The supporter tier is an
optional way to chip in, with cosmetic thanks only (app icons and a thank-you). Code:
`MealMate/Sources/Features/Supporter/`, products mirrored in `MealMate/Support/MealMate.storekit`.

## Products

`SupporterProduct` (`SupporterStatus.swift`) is the catalog; the `.storekit` file and App Store
Connect must use the same IDs (full listing in [App Store Connect](#app-store-connect)).

| ID | Type | Level | USD |
| --- | --- | --- | --- |
| `souschef.monthly` | Auto-renewable, group "MealMate Supporter" | Sous Chef (2) | 1.99 / month |
| `souschef.yearly` | Auto-renewable, same group | Sous Chef (2) | 14.99 / year |
| `headchef.monthly` | Auto-renewable, same group | Head Chef (1, highest) | 4.99 / month |
| `headchef.yearly` | Auto-renewable, same group | Head Chef (1, highest) | 39.99 / year |
| `tip.espresso` | Consumable | – | 2.99 |
| `tip.brunch` | Consumable | – | 9.99 |
| `tip.dinnerparty` | Consumable | – | 19.99 |
| `tip.feast` | Consumable | – | 49.99 |

- `supporter.*` IDs are taken by Dusk in the same developer account (product IDs are unique
  across all apps), hence `souschef.*`.
- Both levels share one group, so Sous Chef → Head Chef is an immediate upgrade (prorated by
  the App Store) and Head Chef → Sous Chef a downgrade at the next renewal. Subscriptions are
  Family Sharing enabled; tips (consumables) can't be.
- Tips are consumables so they can be given again. App Store Connect is the source of truth
  for prices; the `.storekit` file mirrors the USD prices.
- The sheet shows prices from StoreKit (`displayPrice`, localized per storefront); names and
  plan copy are the app's own (`SupporterProduct.displayName`, English like the rest of the
  UI). The App Store Connect names/descriptions appear in the purchase sheet, receipts and the
  subscription settings.

## Status Rules

`SupporterStore` (`@MainActor @Observable`, StoreKit 2) is created in `MealMateApp`, injected
into the environment and started in the root `.task`.

- **Any verified purchase ever ⇒ supporter forever.** `SupporterStatus.merging` folds a
  `Transaction.all` read into the cached status (`isSupporter`, `supporterSince`, `tipCount`,
  UserDefaults `supporter.status`) and only ever adds: an empty history read (offline, sandbox
  hiccup), a lapsed subscription or a refund never downgrades it on this device. A fresh
  install resolves it from the history again (refunded transactions don't count there).
- **Active level** (`activeTier`: none / Sous Chef / Head Chef) comes from
  `Transaction.currentEntitlements` (`SupporterStatus.activeTier`: highest level that isn't
  revoked, upgraded away or expired). It can go down. Cached (`supporter.activeTier`) only so the
  UI is right on launch; `hasResolvedEntitlements` says whether it was read this launch.
- `SKIncludeConsumableInAppPurchaseHistory` = `true` in `Info.plist` keeps finished tips in
  `Transaction.all`. Don't remove it: reinstall and second-device recognition of tippers
  depend on it.
- Every verified transaction is finished (in `purchase`, the `Transaction.updates` listener and
  a launch sweep of `Transaction.unfinished`); an unfinished consumable blocks buying it again.
- `AppStore.sync()` (Restore Purchases) can ask for the Apple Account password: only
  `restorePurchases()` calls it, from the button in the sheet.

## Perks: App Icons

`MealMateAppIcon` lists the icons, `Design/make-icon.swift` draws them (see `STYLE.md` §12).

- **Default** (MealMate): free.
- **Supporter** (any tip or subscription, for good): Mono, Dark, Herb, Tomato, Pastel, Wood.
- **Head Chef** (only while that subscription is active): Copper Pot, Midnight Kitchen.
- Alternates live in `MealMate/Resources/AppIcons.xcassets` (app target only, so the share
  extension doesn't carry them), registered via `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
  in `project.yml`. Previews for the picker: `IconPreview<Name>` imagesets (light + dark).
- **Lapse:** `appIconEntitlementGuard()` (on the root view) switches back to the default icon
  when the current one is no longer included (`MealMateAppIcon.fallback`): only once
  entitlements were read this launch, when the level changes, and when the app becomes active
  (`setAlternateIconName` needs an active app). iOS shows its usual "You have changed the icon"
  alert; there is no public API to suppress it. Supporter status and supporter icons stay.
- Adding an icon: draw it in `make-icon.swift`, add a `MealMateAppIcon` case, add the name to
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, `xcodegen generate`.

## UI

- **`SupporterView`** (one sheet, `.presentationSizing(.page)` on iPad): header (pitch, or
  "Thank You" + level + "Supporter since … · n tips"), the icon strip (`SupporterIconShowcase`,
  locked tiles before a purchase, tap to apply after), the two plan cards (Sous Chef and Head
  Chef with what each includes and monthly / yearly price buttons; side by side in regular
  width), right below them the subscription terms (charged to the Apple Account, auto-renewal,
  how to cancel, Family Sharing) with the Privacy Policy (`PRIVACY.md` on GitHub) and Terms of
  Use (Apple's standard EULA) links, as App Review requires them at the subscription options;
  every price button shows price and period ("$1.99 / month"). Then tips (2 columns, 4 on
  iPad), Restore Purchases and Manage Subscription (`manageSubscriptionsSheet`) while
  subscribed.
  Plan states: active level shows "Your Plan" + billing period + Manage Subscription; a Sous
  Chef sees Head Chef as an upgrade; a Head Chef sees Sous Chef as "Included" (switching down
  goes through Manage Subscription).
- **Settings**: the first section holds the supporter row (opens the sheet; "Thank You, Head
  Chef" etc. for supporters) and the **App Icon** row, which pushes `AppIconPickerView`
  (default / Supporter / Head Chef sections; a locked tile opens the sheet).
- Copy: calm, no guilt, no countdowns or "last chance"; every surface says everything stays free.

## Prompt Ladder

`SupporterPromptGate` + `SupporterPromptLedger` + `supporterPromptPresenter()`
(`SupporterPrompt.swift`), applied to `MainTabView`, so it only runs signed in (never during
onboarding) and only signed-in days count.

| Prompt | Days since first launch | Usage days | Days since previous prompt |
| --- | --- | --- | --- |
| 1 | ≥ 7 | ≥ 3 | – |
| 2 | ≥ 30 | ≥ 10 | ≥ 14 |
| 3 | ≥ 90 | ≥ 25 | ≥ 30 |
| yearly | ≥ 365 | ≥ 12 new since the last prompt | ≥ 180 after prompt 3, then ≥ 365 |

- Evaluated whenever the app becomes active, after a 2 s grace period, not only after "Made
  it". Never for supporters (and only once StoreKit has answered this launch, so a supporter's
  fresh install doesn't ask), never while anything is presented over the tabs (cook mode,
  Settings, any sheet, alert or dialog: checked via the window's `presentedViewController`
  plus the router), never during onboarding.
- Usage days are distinct calendar days. `firstLaunchDate` is the first launch of the version
  that ships this (existing installs start their clock then).
- The ladder advances the moment a prompt shows; "Maybe Later" just closes. Prompt 1 asks
  "Enjoying MealMate?", later ones "Still Cooking with MealMate?". The sheet never describes
  the cadence or promises it's the last ask.

## Testing

- **Unit tests** (`MealMateTests/SupporterTests.swift`): status merging and active level, icon
  availability and the lapse fallback, the prompt ladder and usage days, the `.storekit` file
  vs. the catalog, and StoreKit flows through `SKTestSession` with `MealMate.storekit` (bundled
  into the test target): load the catalog, buy every tip (and one again), Sous Chef → Head Chef
  upgrade, downgrade at renewal, Head Chef lapse (`expireSubscription`), fresh-install
  resolution + Restore Purchases, refund keeps the cached status.
- **By hand in the simulator:** run from Xcode; the `MealMate` scheme's Run action attaches
  `MealMate.storekit` (`project.yml`), so products load locally and Xcode's
  Debug → StoreKit → Manage Transactions can expire, refund or delete purchases. Local runs
  never hit App Store Connect: verify real product loading in TestFlight.
- **Screenshots / routes:** `supporter` (sheet from Settings), `supporter-prompt/<n>` (prompt
  n), `app-icon` (picker). Apps launched by `scripts/screenshot.sh` (`simctl launch`) don't get
  the scheme's StoreKit configuration, so the sheet shows its "couldn't be loaded" state there;
  the purchase states come from `SupporterScreenshotTests` (UI test that drives
  `SKTestSession`, see `scripts/README.md`).

## App Store Connect

Everything the maintainer enters by hand. IDs must match exactly.

### Subscription group

- Reference name: **MealMate Supporter**
- Group display name (localization), EN and DE: **MealMate Supporter**; app name display: the
  app's name.
- Levels (top = highest): **Level 1: Head Chef** (`headchef.monthly`, `headchef.yearly`),
  **Level 2: Sous Chef** (`souschef.monthly`, `souschef.yearly`). Same-level monthly ↔ yearly
  is a crossgrade.
- **Family Sharing: on** for all four subscriptions (can't be turned off once on).
- No introductory or promotional offers.

### Auto-renewable subscriptions

| Product ID | Reference name | Duration | USD (tier) | Level |
| --- | --- | --- | --- | --- |
| `souschef.monthly` | Sous Chef – Monthly | 1 month | 1.99 | 2 |
| `souschef.yearly` | Sous Chef – Yearly | 1 year | 14.99 | 2 |
| `headchef.monthly` | Head Chef – Monthly | 1 month | 4.99 | 1 |
| `headchef.yearly` | Head Chef – Yearly | 1 year | 39.99 | 1 |

Localizations (display name ≤ 30, description ≤ 45 characters):

| Product ID | EN display name | EN description | DE display name | DE description |
| --- | --- | --- | --- | --- |
| `souschef.monthly` | Sous Chef Monthly | Six app icons and a big thank-you. | Sous Chef monatlich | Sechs App-Icons und ein herzliches Danke. |
| `souschef.yearly` | Sous Chef Yearly | Six app icons and a big thank-you. | Sous Chef jährlich | Sechs App-Icons und ein herzliches Danke. |
| `headchef.monthly` | Head Chef Monthly | All icons, incl. two Head Chef exclusives. | Head Chef monatlich | Alle App-Icons plus zwei exklusive. |
| `headchef.yearly` | Head Chef Yearly | All icons, incl. two Head Chef exclusives. | Head Chef jährlich | Alle App-Icons plus zwei exklusive. |

### Consumables (tips)

| Product ID | Reference name | USD | EN name | EN description | DE name | DE description |
| --- | --- | --- | --- | --- | --- | --- |
| `tip.espresso` | Tip – Espresso | 2.99 | Espresso | A quick thank-you. | Espresso | Ein kleines Dankeschön. |
| `tip.brunch` | Tip – Brunch | 9.99 | Brunch | A generous thank-you. | Brunch | Ein herzliches Dankeschön. |
| `tip.dinnerparty` | Tip – Dinner Party | 19.99 | Dinner Party | Thanks for keeping MealMate going. | Dinnerparty | Danke, dass du MealMate am Laufen hältst. |
| `tip.feast` | Tip – Feast | 49.99 | Feast | Wow. Thank you, truly. | Festmahl | Wow. Von Herzen danke. |

Consumables aren't Family Sharing eligible.

### Review information (every product)

- Screenshot: the supporter sheet (`screenshots/supporter-sheet-light.png`, retaken on a
  device size App Review accepts).
- Review notes (paste for each product):

  > MealMate is free; every feature works without purchases. These optional purchases only
  > support development: any tip or subscription unlocks six alternate app icons, the Head
  > Chef subscription additionally two exclusive icons while it is active. To find them: sign
  > in (demo server credentials are in the app review notes), tap the avatar at the top right
  > to open Settings, then "Support MealMate" at the top. The App Icon row below it shows the
  > icons. Restore Purchases and Manage Subscription are in the same sheet.

### Before submitting

1. Paid Apps agreement, tax and banking active.
2. Create the group, the four subscriptions and four consumables above, with prices,
   localizations, review screenshot and notes.
3. App Store listing: privacy policy URL (`PRIVACY.md`) and, because of the subscriptions, a
   Terms of Use (EULA) link: Apple's standard EULA is fine (the app links it). Add the purchase
   note to the description if desired.
4. Submit the in-app purchases together with the app version that first contains them.
5. TestFlight: check that the sheet loads real products (local runs use `MealMate.storekit`).
