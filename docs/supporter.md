# Supporter Tier

MealMate stays **fully free**: every feature works without paying. The supporter tier is an
optional way to chip in, with cosmetic thanks only (app icons and a thank-you). Code:
`MealMate/Sources/Features/Supporter/`, products mirrored in `MealMate/Support/MealMate.storekit`.

## Products

`SupporterProduct` (`SupporterStatus.swift`) is the catalog; the `.storekit` file and App Store
Connect must use the same IDs (full listing in [App Store Connect](#app-store-connect)).

| ID | Type | Level | USD | Offered |
| --- | --- | --- | --- | --- |
| `headchef.monthly` | Auto-renewable, group "MealMate Supporter" | 1 | 2.99 / month | yes |
| `headchef.yearly` | Auto-renewable, same group | 1 | 24.99 / year | yes |
| `souschef.monthly` | Auto-renewable, same group | 2 | 1.99 / month | retired |
| `souschef.yearly` | Auto-renewable, same group | 2 | 14.99 / year | retired |
| `tip.espresso` | Consumable | – | 2.99 | yes |
| `tip.brunch` | Consumable | – | 9.99 | yes |
| `tip.dinnerparty` | Consumable | – | 19.99 | yes |
| `tip.feast` | Consumable | – | 49.99 | yes |

- **One subscription, two billing periods** ("MealMate Supporter", monthly or yearly). It reuses
  the `headchef.*` IDs of the earlier two-level setup (Sous Chef / Head Chef), which already sit
  at the top level of the group. Monthly ↔ yearly is a crossgrade at the next renewal.
- **Retired:** `souschef.*`. The sheet doesn't offer them (`SupporterProduct.offeredIDs`), but an
  active one still counts as subscribed with every subscription perk, and buying the current
  subscription from it is an immediate upgrade (it's the higher level). Keep them in the
  `.storekit` file and the catalog (`isLegacy`) as long as anyone might still renew one.
- `supporter.*` IDs are taken by Dusk in the same developer account (product IDs are unique
  across all apps), hence the chef names.
- Subscriptions are Family Sharing enabled; tips (consumables) can't be.
- Tips are consumables so they can be given again. App Store Connect is the source of truth
  for prices; the `.storekit` file mirrors the USD prices.
- **Espresso is a thank-you only:** it makes someone a supporter but unlocks no icon. Brunch,
  Dinner Party and Feast (and the subscription) unlock the food icons
  (`SupporterProduct.unlocksFoodIcons`).
- The sheet shows prices from StoreKit (`displayPrice`, localized per storefront); names and
  plan copy are the app's own (English like the rest of the UI). The App Store Connect
  names/descriptions appear in the purchase sheet, receipts and the subscription settings.

## Status Rules

`SupporterStore` (`@MainActor @Observable`, StoreKit 2) is created in `MealMateApp`, injected
into the environment and started in the root `.task`.

- **Any verified purchase ever ⇒ supporter forever.** `SupporterStatus.merging` folds a
  `Transaction.all` read into the cached status (`isSupporter`, `supporterSince`, `tipCount`,
  `hasFoodIcons`, UserDefaults `supporter.status`) and only ever adds: an empty history read (offline, sandbox
  hiccup), a lapsed subscription or a refund never downgrades it on this device. A fresh
  install resolves it from the history again (refunded transactions don't count there).
- **Food icons** (`hasFoodIcons`, `SupporterStore.hasFoodIcons`): set by any subscription (also a
  retired or lapsed one) or a tip from Brunch up, ever; monotonic like `isSupporter`. Not by the
  Espresso tip. Caches from before the flag decode with it off and the next history read sets it
  again. No grandfathering for Espresso: until this change MealMate was only on TestFlight, so
  every Espresso tip so far was a free sandbox purchase. A tester with only an Espresso tip and a
  food icon set goes back to the default icon (the guard below).
- **Subscribed** (`isSubscribed`, `activeSubscription`) comes from
  `Transaction.currentEntitlements` (`SupporterStatus.activeSubscription`: a subscription that
  isn't revoked, upgraded away or expired, retired `souschef.*` included). It can go away.
  Cached (`supporter.isSubscribed`) only so the UI is right on launch; the old
  `supporter.activeTier` cache (0 / 1 / 2) is read once as a fallback and removed.
  `hasResolvedEntitlements` says whether entitlements were read this launch.
- `SKIncludeConsumableInAppPurchaseHistory` = `true` in `Info.plist` keeps finished tips in
  `Transaction.all`. Don't remove it: reinstall and second-device recognition of tippers
  depend on it.
- Every verified transaction is finished (in `purchase`, the `Transaction.updates` listener and
  a launch sweep of `Transaction.unfinished`); an unfinished consumable blocks buying it again.
- `AppStore.sync()` (Restore Purchases) can ask for the Apple Account password: only
  `restorePurchases()` calls it, from the button in the sheet.

## Perks: App Icons

`MealMateAppIcon` lists the icons; `Design/make-icon-variants.swift` draws the default and the
food icons, `Design/make-icon-subscriber.swift` the subscription icons (see `STYLE.md` §12).

- **Default** (Salad, shown as "MealMate"): free.
- **Food icons** (any subscription or a tip from Brunch up, for good; not the Espresso tip):
  Grain Bowl, Spaghetti, Shakshuka, Ramen, Margherita.
- **Subscription icons** (only while a subscription is active): Enamel Cocotte, Candlelight,
  Sunday Brunch.
- Alternates live in `MealMate/Resources/AppIcons.xcassets` (app target only, so the share
  extension doesn't carry them), registered via `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
  in `project.yml`. Previews for the picker: `IconPreview<Name>` imagesets (light + dark).
- Retired: Mono, Dark, Herb, Tomato, Pastel, Wood (replaced by the food icons) and the earlier
  subscription icons Copper Pot and Midnight Kitchen. If the home screen still
  names one of them (`MealMateAppIcon.currentIsRetired`), the guard below switches to the default
  the next time the app is active.
- **Lapse:** `appIconEntitlementGuard()` (on the root view) switches back to the default icon
  when the current one is no longer included (`MealMateAppIcon.fallback`): only once
  entitlements were read this launch, when the subscription state changes, and when the app
  becomes active (`setAlternateIconName` needs an active app). iOS shows its usual "You have
  changed the icon" alert; there is no public API to suppress it. Supporter status and unlocked
  food icons stay.
- Adding an icon: draw it in one of the scripts, add a `MealMateAppIcon` case, add the name to
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, `xcodegen generate`.

## UI

- **`SupporterView`** (one sheet, `.presentationSizing(.page)` on iPad, max 560 pt wide), laid
  out like Dusk's Supporter page. One spacing scale (`SupporterLayout`): 32 pt between sections,
  10 pt from a section label to its first card and between stacked cards, cards inset 16 pt; all
  text in a section (uppercase footnote label, card content, caption footnote, the icon strip's
  first tile) starts on that one 16 pt column. Close is the system close button in the toolbar
  (leading, STYLE.md §8), so scrolled content passes under the bar.
  - Header: heart in a 14% accent circle, "Support MealMate" / prompt headline / "Thank You",
    the pitch or thank-you, "Supporter since … · n tips".
  - **App icons** (`SupporterIconShowcase`): "Supporter Perk — App Icons" / "Your App Icons", a
    strip with the default and food icons, a hairline, then the subscription icons. Tiles are
    sized so a sixth one is cut in half at the edge (it shows the strip scrolls); the strip bleeds
    to the screen edge. Locked tiles carry a white lock on a dark disc (`AppIconImage`, also in
    the picker); unlocked ones apply on tap.
  - **Recurring:** one "MealMate Supporter" card: checkmark perks (the five food icons, yours to
    keep; three subscriber exclusives with inline thumbnails; keeps MealMate free) and two
    equal-width price buttons ("$2.99 / month", "$24.99 / year") with "Billed monthly" /
    "Saves n%" under each. Right below: the subscription terms (charged to the Apple Account,
    auto-renewal, how to cancel, the subscription icons only while active, Family Sharing) and
    the Privacy Policy (`PRIVACY.md` on GitHub) and Terms of Use (Apple's standard EULA) links,
    as App Review requires them at the subscription options. Subscribed (a retired Sous Chef
    plan included): an "Active" badge and accent outline, the billing period and Manage
    Subscription (`manageSubscriptionsSheet`) instead of the price buttons.
  - **One-Time** ("Support Again" for supporters): one full-width row per tip with the name, the
    app's own description (`SupporterProduct.tipDescription`), from Brunch up "Includes the five
    food icons" (one line; the footnote says they're yours to keep), and the price on the right; footnote "A tip is a one-time
    thank-you…".
  - Footer: everything stays free, Restore Purchases (and Manage Subscription while subscribed
    but the products can't load).
  - Busy buttons keep their size: `busyOverlay` hides the label and overlays a small spinner.
- **Settings**: the first section holds the supporter row (opens the sheet; "Thank You for
  Subscribing" / "Thank You for Your Support" for supporters) and the **App Icon** row, which
  pushes `AppIconPickerView` (default / Supporter / Subscription sections; a locked tile opens
  the sheet).
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

- **Unit tests** (`MealMateTests/SupporterTests.swift`): status merging (Espresso vs. Brunch and
  up, the cache from before `hasFoodIcons`) and the active subscription (retired levels included), icon availability and the lapse fallback, the old
  cache key, the prompt ladder and usage days, the `.storekit` file vs. the catalog, and
  StoreKit flows through `SKTestSession` with `MealMate.storekit` (bundled into the test target):
  load the offered catalog, buy every tip (and one again; Espresso alone unlocks no icon, also
  after a reinstall), subscribe, a Sous Chef subscriber
  keeps every perk and moves to the current subscription, lapse (`oneRenewalEveryTwoSeconds` +
  auto-renew off), fresh-install resolution, refund keeps the cached status.
- **By hand in the simulator:** run from Xcode; the `MealMate` scheme's Run action attaches
  `MealMate.storekit` (`project.yml`), so products load locally and Xcode's
  Debug → StoreKit → Manage Transactions can expire, refund or delete purchases. Local runs
  never hit App Store Connect: verify real product loading in TestFlight.
- **Screenshots / routes:** `supporter` (sheet from Settings), `supporter-prompt/<n>` (prompt
  n), `app-icon` (picker). Apps launched by `scripts/screenshot.sh` (`simctl launch`) don't get
  the scheme's StoreKit configuration, so the sheet shows its "couldn't be loaded" state there;
  the purchase states come from `SupporterScreenshotTests` (UI test that drives
  `SKTestSession`, see `scripts/README.md`). Busy buttons: DEBUG launch argument
  `-supporter.debugBusy <productID|restore>`; they keep their size (`busyOverlay` hides the
  label and overlays a small spinner).

## App Store Connect

Everything the maintainer enters by hand. IDs must match exactly.

### Subscription group

- Reference name: **MealMate Supporter**
- Group display name (localization), EN and DE: **MealMate Supporter**; app name display: the
  app's name.
- Levels (top = highest): **Level 1** `headchef.monthly`, `headchef.yearly` (the subscription);
  **Level 2** `souschef.monthly`, `souschef.yearly` (retired, removed from sale). Monthly ↔
  yearly is a crossgrade.
- **Family Sharing: on** for all subscriptions (can't be turned off once on).
- No introductory or promotional offers.

### Auto-renewable subscriptions

| Product ID | Reference name | Duration | USD | Level | Status |
| --- | --- | --- | --- | --- | --- |
| `headchef.monthly` | Supporter – Monthly | 1 month | 2.99 | 1 | on sale |
| `headchef.yearly` | Supporter – Yearly | 1 year | 24.99 | 1 | on sale |
| `souschef.monthly` | Sous Chef – Monthly (retired) | 1 month | 1.99 | 2 | removed from sale |
| `souschef.yearly` | Sous Chef – Yearly (retired) | 1 year | 14.99 | 2 | removed from sale |

Localizations of the offered ones (display name ≤ 30, description ≤ 45 characters):

| Product ID | EN display name | EN description | DE display name | DE description |
| --- | --- | --- | --- | --- |
| `headchef.monthly` | Supporter Monthly | All app icons and a big thank-you. | Supporter monatlich | Alle App-Icons und ein herzliches Danke. |
| `headchef.yearly` | Supporter Yearly | All app icons and a big thank-you. | Supporter jährlich | Alle App-Icons und ein herzliches Danke. |

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
  > support development: the subscription or a tip from Brunch up unlocks five alternate app
  > icons for good; the subscription additionally unlocks three more icons while it is active.
  > The Espresso tip is a thank-you only and unlocks nothing. To find them: sign
  > in (demo server credentials are in the app review notes), tap the avatar at the top right
  > to open Settings, then "Support MealMate" at the top. The App Icon row below it shows the
  > icons. Restore Purchases and Manage Subscription are in the same sheet.

### Before submitting

1. Paid Apps agreement, tax and banking active.
2. The group, the two offered subscriptions and four consumables above, with prices,
   localizations, review screenshot and notes; the retired Sous Chef products removed from sale
   (or deleted, if they were never submitted).
3. App Store listing: privacy policy URL (`PRIVACY.md`) and, because of the subscription, a
   Terms of Use (EULA) link: Apple's standard EULA is fine (the app links it). Add the purchase
   note to the description if desired.
4. Submit the in-app purchases together with the app version that first contains them.
5. TestFlight: check that the sheet loads real products (local runs use `MealMate.storekit`).
