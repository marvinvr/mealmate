import SwiftUI

// Design tokens. STYLE.md (repo root) is the source of truth; change both together.

// MARK: - Colors

/// Brand surfaces backed by the asset catalog (light + dark variants live there).
/// Text uses the system label styles (`.primary`, `.secondary`, `.tertiary`), not custom tokens.
///
/// Declared on `ShapeStyle where Self == Color` so both `Color.mealMateBackground`
/// and the leading-dot form `.background(.mealMateBackground)` work.
extension ShapeStyle where Self == Color {
    /// Root screen background. Warm paper `#F7F6F2` / warm near-black `#121211`.
    static var mealMateBackground: Color { Color("MealMateBackground") }

    /// Elevated content: cards, sheets, grouped rows. `#FFFFFF` / `#1C1B19`.
    static var mealMateSurface: Color { Color("MealMateSurface") }

    /// Quiet fills: chips, search fields, image placeholders. `#EFEDE7` / `#262522`.
    static var mealMateSurfaceSecondary: Color { Color("MealMateSurfaceSecondary") }

    /// Rosemary. Same as the global tint; prefer `.tint` / `.foregroundStyle(.tint)` in views.
    /// `#4E7048` / `#7A9E6C`.
    static var mealMateAccent: Color { Color.accentColor }

    /// Fill of the one prominent action per screen (`.primaryActionStyle()`). Same as the accent
    /// in light mode, a deeper rosemary in dark mode so the white label keeps ≥ 4.5 : 1.
    /// `#4E7048` / `#557A4E`.
    static var mealMateProminent: Color { Color("MealMateProminent") }
}

// MARK: - Layout

enum Theme {
    /// 4pt-based spacing scale.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48

        /// Horizontal margin of custom (non-List) screens on iPhone.
        static let screen: CGFloat = 20
        /// Gap between cards in a grid.
        static let grid: CGFloat = 16
    }

    /// Continuous corner radii. Chips and buttons use `.capsule`.
    enum Radius {
        /// Small list thumbnails (≤ 64pt).
        static let thumbnail: CGFloat = 10
        /// Recipe cards, content cards.
        static let card: CGFloat = 16
        /// Large standalone surfaces (e.g. a cook-mode step panel).
        static let large: CGFloat = 24
    }

    /// Image aspect ratios (width / height).
    enum Aspect {
        /// Recipe cards in grids and carousels.
        static let card: CGFloat = 4 / 3
        /// Recipe detail hero.
        static let hero: CGFloat = 4 / 3
    }

    /// Extra line spacing for multi-line reading text.
    enum LineSpacing {
        static let body: CGFloat = 4
        static let cook: CGFloat = 6
    }

    /// Minimum width of a grid column (use with `GridItem(.adaptive(minimum:))`).
    static let gridMinimumColumnWidth: CGFloat = 160
    /// Minimum grid column width in regular width (iPad): bigger photos, 4 columns on a 13" iPad
    /// in portrait, 5 in landscape.
    static let gridMinimumColumnWidthRegular: CGFloat = 220

    /// Widest a list or form gets on iPad before it's centred (`.readableContentWidth()`).
    static let readableWidth: CGFloat = 720
}

// MARK: - Typography

/// Recipe names are set in New York (serif); everything else is SF Pro.
/// All styles are Dynamic Type text styles, so they scale.
extension Font {
    /// Recipe detail title.
    static let recipeTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    /// Recipe name on grid cards and carousels.
    static let recipeCardTitle = Font.system(.headline, design: .serif, weight: .semibold)
    /// Recipe name in list rows (meal plan, search results, cookbooks).
    static let recipeRowTitle = Font.system(.body, design: .serif, weight: .semibold)

    /// In-content section headers: "Ingredients", "Steps", "Notes".
    static let sectionTitle = Font.title3.weight(.semibold)
    /// Times, servings, counts, ratings. Add `.monospacedDigit()` where numbers change.
    static let metadata = Font.subheadline
    /// "Step 2", small uppercase-free labels above content.
    static let stepLabel = Font.footnote.weight(.semibold)

    /// Cook mode: current step text.
    static let cookStep = Font.title2
    /// Cook mode step text in regular width (iPad), read from further away.
    static let cookStepRegular = Font.title
    /// Cook mode: ingredient lines.
    static let cookIngredient = Font.title3
}

// MARK: - Modifiers

extension View {
    /// Root background for every screen. Hides the default List/Form/ScrollView
    /// background so the warm token shows; grouped rows keep their system background,
    /// which matches `mealMateSurface`.
    func screenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(.mealMateBackground, ignoresSafeAreaEdges: .all)
    }

    /// Clips a recipe photo (or placeholder) to the shared continuous shape and adds a
    /// hairline so pale photos keep an edge against the background.
    func recipeImageShape(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }

    /// The screen's one primary action (Start cooking, Sign in, Import): prominent glass with the
    /// `mealMateProminent` fill. Set `.controlSize` at the call site.
    func primaryActionStyle() -> some View {
        buttonStyle(.glassProminent)
            .tint(.mealMateProminent)
    }

    /// Centres a List's / ScrollView's content at `Theme.readableWidth` once the view is wider
    /// (iPad), like UIKit's readable content guide. No effect at iPhone widths.
    func readableContentWidth(_ maxWidth: CGFloat = Theme.readableWidth) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }

    /// Flat content card for non-image blocks (nutrition, notes, server info). No shadow.
    func surfaceCard(padding: CGFloat = Theme.Spacing.m) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.mealMateSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}


private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        // `nil` keeps the system margins (iPhone, narrow iPad windows).
        let margin: CGFloat? = width > maxWidth + 2 * Theme.Spacing.screen ? (width - maxWidth) / 2 : nil
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
