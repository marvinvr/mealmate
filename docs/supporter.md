# Supporter Tip Jar (plan, not built)

MealMate stays **fully free**: every feature works without paying. A later, optional tip jar
lets people chip in and get cosmetic thanks. Nothing here exists in code yet; this is the
agreed design for whoever builds it.

## Products

Defined in one `SupporterProduct` enum and mirrored in a local StoreKit configuration file
(`MealMate/Support/MealMate.storekit`). App Store Connect must use the same IDs.

| ID | Type | Note |
| --- | --- | --- |
| `tip.small` | Consumable | e.g. ~$1.99 |
| `tip.medium` | Consumable | e.g. ~$4.99 |
| `tip.large` | Consumable | e.g. ~$9.99 |
| `supporter.monthly` | Auto-renewable, group "MealMate Supporter" | optional |
| `supporter.yearly` | Auto-renewable, same group | optional |

Tips are **consumables** so they can be bought again. Subscriptions are optional; ship tips
first. Prices are set in App Store Connect (source of truth); the `.storekit` file mirrors
them. Names and descriptions shown in the UI come from StoreKit product metadata.

## Status Rules

`SupporterStore` (`@MainActor @Observable`, StoreKit 2, created in `MealMateApp`):

- **Any verified purchase ever ⇒ supporter forever.** Status only upgrades; the cached flag in
  UserDefaults is never downgraded by an empty or transient history read.
- Lifetime evidence (`isSupporter`, `supporterSince`, `tipCount`) from `Transaction.all`;
  active subscription from `Transaction.currentEntitlements`.
- Set `SKIncludeConsumableInAppPurchaseHistory` = `true` in `Info.plist` so finished
  consumables appear in `Transaction.all` (reinstall and second-device recognition depend on it).
- Listen to `Transaction.updates`, finish every verified transaction, sweep unfinished ones at
  launch (an unfinished consumable blocks buying it again).
- `AppStore.sync()` (Restore Purchases) can prompt for the Apple ID password: call it only
  from an explicit user action.

## Perks (cosmetic only)

- Alternate app icons (`UIApplication.setAlternateIconName`, registered via
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in `project.yml`); the default icon is free.
- A thank-you state in Settings. No feature is ever gated.

## UI

- One `SupporterView` sheet: pitch, purchase rows, thank-you, icon preview.
- Entry point: a row at the top of Settings (thank-you state for supporters), plus an
  "App Icon" row.
- **Gentle prompts** (optional, `SupporterPromptGate`): never for supporters, never during
  cook mode, onboarding or a sheet, only after a calm moment (e.g. after "Made it").
  Escalating thresholds, for example prompt 1 after ≥ 7 days since first launch and ≥ 3
  distinct usage days; prompt 2 after ≥ 30 days, ≥ 10 usage days, ≥ 14 days since prompt 1;
  prompt 3 after ≥ 90 days, ≥ 25 usage days, ≥ 30 days since prompt 2; then at most yearly.
  "Maybe Later" just closes. The sheet never guilt-trips and never promises it is the last ask.

## Maintainer Steps (App Store Connect)

1. Create the consumables (and, if used, the subscription group + both subscriptions) with
   the IDs above, prices, localized names/descriptions and a review screenshot.
2. Subscriptions only: privacy policy and terms (EULA) links in the app and the listing.
3. Submit the in-app purchases with the app version that first contains them.
4. Attach `MealMate.storekit` to the scheme's Run action (`project.yml` `schemes:` →
   `storeKitConfiguration`) for local testing; note that local runs then never hit App Store
   Connect, so verify real product loading in TestFlight.

## Verification (when built)

Build; in the simulator with the `.storekit` config, buy each product, check supporter status
survives an app reinstall (resolved from transaction history), test Restore Purchases and the
icon picker.
