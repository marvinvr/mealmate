# MealMate Design System

Visual source of truth for MealMate. Tokens live in `MealMate/Sources/Shared/Theme.swift` and
`MealMate/Resources/Assets.xcassets`; change them together with this file.

## 1. Philosophy

- **Food leads, UI recedes.** Recipe photos carry the colour. Chrome is neutral, quiet and native.
- **Native first.** System navigation, lists, forms, menus, sheets, `ContentUnavailableView`,
  SF Symbols and Liquid Glass. Reach for a custom component only when the system has none.
- **Calm.** Generous whitespace, few weights, one accent used sparingly. No gradients, no
  drop-shadowed cards, no decorative illustrations, no emoji in UI.
- **A kitchen tool.** Readable from arm's length, usable with one (possibly floury) hand.

## 2. Color

Warm neutrals instead of the system's cool greys: food photos look better on a paper tone.

| Token (Swift / asset) | Light | Dark | Use |
| --- | --- | --- | --- |
| `.mealMateBackground` / `MealMateBackground` | `#F7F6F2` | `#121211` | Root background of every screen |
| `.mealMateSurface` / `MealMateSurface` | `#FFFFFF` | `#1C1B19` | Cards, sheets, grouped rows |
| `.mealMateSurfaceSecondary` / `MealMateSurfaceSecondary` | `#EFEDE7` | `#262522` | Chips, fills, image placeholders |
| `.mealMateAccent` / `AccentColor` ("Rosemary") | `#4E7048` | `#7A9E6C` | Global tint (see below) |
| `.mealMateProminent` / `MealMateProminent` | `#4E7048` | `#557A4E` | Fill of the one prominent button (`.primaryActionStyle()`) |
| Text primary: `.primary` | `#000000` | `#FFFFFF` | Titles, body |
| Text secondary: `.secondary` | `#3C3C43` @ 60% | `#EBEBF5` @ 60% | Metadata, captions |
| Text tertiary: `.tertiary` | `#3C3C43` @ 30% | `#EBEBF5` @ 30% | Placeholders, disabled |

- **Text and separators are system colours** (`.primary`, `.secondary`, `.tertiary`, `Divider`).
  They adapt to vibrancy on glass and to Increase Contrast; do not hardcode text hex values.
- **Destructive / warnings** use system `.red` / `.orange` only for their semantic meaning.
- **Accent: Rosemary**, a muted herb green. Food-friendly without competing with photos (orange
  and red fight with food, blue feels clinical), reads as "fresh / done" for check-offs, and is
  dark enough to work as a real tint. It has high-contrast variants (`#3D5A38` / `#93B486`).
  WCAG contrast:

  | | on background | on surface | on surfaceSecondary | white label on accent |
  | --- | --- | --- | --- | --- |
  | Light `#4E7048` | 5.2 : 1 | 5.6 : 1 | 4.8 : 1 | 5.6 : 1 |
  | Dark `#7A9E6C` | 6.2 : 1 | 5.7 : 1 | 5.1 : 1 | 3.0 : 1 (large/semibold text only) |

  All pass AA for text. In dark mode, white text on the light accent fill would only reach 3 : 1,
  so prominent buttons use `MealMateProminent` instead (a deeper rosemary in dark mode, white label
  4.9 : 1; high-contrast variants `#3D5A38` / `#4A6B44`). System confirm buttons in toolbars keep
  the global tint (icon-only, ≥ 3 : 1 for graphics).
- **Where the accent goes:** the global tint (links, toolbar buttons, toggles, selected tab, check
  marks, steppers), the one primary action of a screen, selected chips (16% wash + accent text),
  favourite heart, rating stars. **Not** on backgrounds, headers, section titles or body text.

## 3. Typography

- **Recipe names are New York (serif)**, everywhere a recipe name is the primary text. It gives the
  app a cookbook feel without decoration. **Everything else is SF Pro**, including navigation titles.
- Only Dynamic Type text styles; never fixed point sizes.

| Swift | Style | Use |
| --- | --- | --- |
| `.recipeTitle` | largeTitle, serif, bold | Recipe detail title |
| `.recipeCardTitle` | headline, serif, semibold | Recipe name on grid cards / carousels |
| `.recipeRowTitle` | body, serif, semibold | Recipe name in list rows |
| `.sectionTitle` | title3, semibold | "Ingredients", "Steps", "Notes" |
| `.metadata` | subheadline (+ `.secondary`) | Times, servings, ratings; `.monospacedDigit()` for changing numbers |
| `.stepLabel` | footnote, semibold | "Step 2" above step text |
| `.cookStep` | title2 | Cook mode step text |
| `.cookStepRegular` | title | Cook mode step text in regular width (iPad) |
| `.cookIngredient` | title3 | Cook mode ingredients |

- Reading text (steps, notes, descriptions): `.body` with `.lineSpacing(Theme.LineSpacing.body)`;
  cook mode `Theme.LineSpacing.cook`. Max ~70 characters per line on iPad (`.frame(maxWidth: 680)`).
- Recipe card/row titles: `lineLimit(2)`; never truncate a recipe title on the detail screen.
- Metadata separator: ` · ` (e.g. `35 min · 4 servings`), or SF Symbol labels (`clock`, `person.2`).

## 4. Spacing, shape, layout

- Spacing scale (`Theme.Spacing`): `xxs 4 · xs 8 · s 12 · m 16 · l 20 · xl 24 · xxl 32 · xxxl 48`.
  Screen margin `screen` = 20, grid gap `grid` = 16. Sections in detail screens are `xxl` apart.
- Radii (`Theme.Radius`, always `.continuous`): `thumbnail 10`, `card 16`, `large 24`.
  Chips and buttons: `.capsule`.
- No shadows on content. Separation comes from whitespace, surface tone and the image hairline.
- **Grid vs list:** recipe browsing (home, search without a query, cookbook contents) is a grid of
  `gridMinimumColumnWidth` columns (at least 2, also on 375 pt phones; in regular width
  `gridMinimumColumnWidthRegular` = 220: 4 on a 13" iPad in portrait, 5 in landscape; 1 at
  accessibility sizes), built
  as a plain `List` of card rows (not `ScrollView` + `LazyVGrid`, see §8), with an optional list
  toggle. Cards in List rows are `Button`s that push via `AppRouter` (a `NavigationLink` there
  gets a chevron). Everything task-like is a `List`
  (`.insetGrouped` or `.plain`): shopping items, meal plan days, search results, categories /
  tags / tools, settings, forms.
- Every screen root: `.screenBackground()`. Grouped list rows keep their system row background
  (it matches `mealMateSurface`).
  Exception: partial-height (`.medium` detent) sheets give grouped rows a grey glass fill; when such
  a sheet mixes a `.surfaceCard()` with rows, give the rows `.listRowBackground(Color.mealMateSurface)`.

### iPad (regular width)

Same design language, more room; never a stretched iPhone layout. Narrow iPad windows (Split
View, Slide Over, small Stage Manager windows) are compact width and look exactly like iPhone.

- Lists and forms (meal plan, shopping list, library, recipe rows) stay at a readable width:
  `.readableContentWidth()` centres them at `Theme.readableWidth` (720 pt), like UIKit's
  readable content guide. The shopping add bar matches that width.
- Recipe detail from 900 pt wide: header on top (max 760 pt), then ingredients (300–400 pt)
  beside steps and everything after them (max 680 pt), content max 1180 pt. Hero stays
  full-bleed; its height is capped at 520 pt and 42% of the screen height (landscape).
- Shopping: lists in a sidebar column beside the open list (`NavigationSplitView`); the
  selected list is a 16% accent wash like a selected chip, not the solid system fill.
- Cook mode from 1000 pt wide: the ingredients (servings, check-off) stay in a panel beside
  the steps, the current step's ingredients get a 12% accent wash; step text `.cookStepRegular`.
- Long sheets (editor, Add to Shopping List, meal plan entry, the week's Add to List) use
  `.presentationSizing(.page)`;
  short ones keep the default form sheet.
- Onboarding and sign-in keep their 520 pt column and sit lower on tall screens instead of
  hugging the top.
- Hardware keyboard: ⌘1–⌘4 tabs, ⌘N new recipe, ⇧⌘N import, ⌘, settings (menu bar
  commands); cook mode ← / → and Esc.

## 5. Images

- Mealie serves `original.webp`, `min-original.webp`, `tiny-original.webp` under
  `/api/media/recipes/{id}/images/`. Hero → `original`, cards → `min-original`,
  thumbnails (≤ 64pt) → `tiny-original`.
- Cards: `Theme.Aspect.card` (4:3), `.fill` + clipped, `.recipeImageShape()` (16pt radius +
  0.5pt hairline). Title and metadata sit **below** the image, never on top of it.
- List thumbnails: square 56pt, `.recipeImageShape(cornerRadius: Theme.Radius.thumbnail)`.
- Detail hero: full-bleed, edge to edge under the navigation bar (`ignoresSafeArea(edges: .top)`),
  4:3 on iPhone, capped height on iPad. No gradient scrim; toolbar buttons are glass, the title
  sits below the image on the background.
- No photo / loading / failed: `RecipeImagePlaceholder(seed: recipe.id)` (muted tone + `fork.knife`).
  Fade the real image in (`.transition(.opacity)`), no spinners on images.

## 6. Liquid Glass

- **Yes:** the system navigation bar, toolbars, tab bar and search (automatic on iOS 26); floating
  controls over content (e.g. cook-mode next/previous, a floating "add item" button):
  `.buttonStyle(.glass)` or `.glassEffect()`; toolbar buttons over the recipe hero.
- **Primary action** (Start cooking, Sign in, Import): `.primaryActionStyle()` (prominent glass
  with the `MealMateProminent` fill) and `.controlSize(.large)`, capsule. At most one per screen.
  Never `.buttonStyle(.glassProminent)` directly. Secondary actions: `.buttonStyle(.glass)` or
  `.bordered` with `.tint(.primary)`.
- **No:** cards, list rows, chips, section backgrounds, sheets' content. Don't stack glass on glass.
  Group neighbouring glass controls in a `GlassEffectContainer`.

## 7. States

- **Empty / error:** `ContentUnavailableView` with an SF Symbol, a short title and one sentence that
  says what to do, plus at most one action (`.buttonStyle(.bordered)`). Examples: "No Recipes Yet ·
  Import one from a website or create your own." / "Can’t Reach Your Server · Check that you’re on
  the same network, then try again." Search: `ContentUnavailableView.search(text:)`.
- **Loading:** show cached content immediately and refresh in place; first load without cache uses
  `.redacted(reason: .placeholder)` on the real layout or a centred `ProgressView()`. No custom
  spinners, no shimmer.
- Pull-to-refresh (`.refreshable`) on every list/grid backed by the server.
- Don't stack empty states: one screen shows one. A collection of mostly empty groups (e.g. meal plan
  days) collapses empty groups to their header instead of repeating "nothing here" rows.
- Errors from a background refresh don't replace cached content; show a small inline note instead.

## 8. Navigation, toolbars & copy

- Tab roots: large title, `.screenBackground()`, the account avatar first in the trailing toolbar,
  then the screen's actions (a `+` / `+` menu, then a view-options menu). Search uses the default
  `.searchable` placement: on a plain `List` (Recipes) the field shows under the large title right
  away; on inset-grouped lists (Library) it appears when pulling down. Don't use
  `.navigationBarDrawer(displayMode: .always)` (on iOS 26/27 it collapses the large title on
  `ScrollView`s, short lists and after a tab switch) and don't put a primary grid in a `ScrollView`
  if it needs search. Active filters show as removable chips above the content, not as a changed
  toolbar glyph. Long pick lists (e.g. foods in the filter) are search-first: show the selection,
  then results as you type.
- Pushed screens: large title for collections (lists, cookbooks), inline for detail (recipe).
  Sheets: inline title, `xmark` cancel leading, `checkmark` confirm trailing.
- Copy: Title Case for navigation titles, buttons, menu items and empty-state titles
  ("Add to Shopping List", "No Favorites Yet"); sentence case for descriptions, footers, placeholders
  and toasts. Curly apostrophes and quotes (’ “ ”). Short, friendly, no jargon; say what to do.
- Informational text is `.secondary`; `.tertiary` only for placeholders, disabled content and
  quiet counts.

## 9. Haptics & motion

- `.sensoryFeedback(.selection, trigger:)` when checking an ingredient or shopping item;
  `.success` after an import, "Made it", or adding ingredients to a list; `.error` when a
  user-triggered action fails. No haptics on navigation, scrolling or ordinary taps.
- System animations only: `.smooth` / `.snappy`, no bouncy springs. Check-off: checkmark +
  strikethrough + fade to `.secondary`, animated. Respect Reduce Motion (cross-fade instead of
  movement); matched-geometry hero transitions only when Reduce Motion is off.

## 10. Accessibility

- Support Dynamic Type through AX5. At accessibility sizes grids become one column
  (`dynamicTypeSize.isAccessibilitySize`) and horizontal metadata stacks wrap or stack vertically.
- Tap targets ≥ 44×44pt. Cook-mode controls are larger (≥ 60pt).
- Never rely on colour alone: checked = checkmark + strikethrough; selected chip has the
  `.isSelected` trait.
- Recipe cards are one accessibility element (`.accessibilityElement(children: .combine)`) with a
  label like "Lemon Herb Chicken, 35 minutes, 4 stars". Decorative images are hidden.
- Cook mode keeps the screen awake and must be usable in landscape.

## 11. Dos and don'ts

**Do**
- Use `.screenBackground()`, the `Theme` tokens and system text styles in every new view.
- Let photos be big; give sections room (`Theme.Spacing.xxl`).
- Prefer system controls: `Menu`, `Picker`, `Stepper`, swipe actions, context menus, share sheet.

**Don't**
- Hardcode colours (`.green`, `.orange`, hex) or font sizes in views.
- Put text on top of photos, add gradient scrims, shadows or borders on cards.
- Use the accent for large fills, backgrounds or more than one prominent button per screen.
- Use serif for anything other than recipe names.
- Add new tokens without updating this file.

## 12. App icon

`Design/make-icon.swift` (run `swift Design/make-icon.swift` from the repo root) draws the icon and
writes it to `AppIcon.appiconset`: one larger prep bowl of chopped herbs and two small bowls of
paprika and saffron, seen from above, on an oat ground. Light (opaque), dark (transparent; the
system supplies the backdrop) and tinted (grayscale) variants, single 1024pt universal size.
Edit the script, never the PNGs.

## 13. Asset notes

- `AccentColor` is the global accent (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`).
- Swift reads colour sets by name in `Theme.swift`. Keep
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` off (the default), otherwise the
  generated `Color.mealMate…` members collide with the hand-written ones.
- Launch screen: `UILaunchScreen` → `UIColorName` = `MealMateBackground`, so launch matches the app.
