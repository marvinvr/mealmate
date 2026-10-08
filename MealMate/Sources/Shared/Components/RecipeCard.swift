import SwiftUI

/// Grid card: 4:3 photo, serif title (two lines reserved so rows line up), one line of
/// metadata. No background, shadow or border (STYLE.md §4/§5).
///
/// Not interactive by itself: wrap it in a `NavigationLink(value: AppDestination.recipe(slug:))`
/// with `.buttonStyle(.plain)`. One accessibility element ("Lemon Herb Chicken, 35 minutes, 4 stars").
struct RecipeCard: View {
    let recipe: RecipeSummary
    var isFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RecipeImage(recipe: recipe, size: .min)
                .aspectRatio(Theme.Aspect.card, contentMode: .fit)
                .recipeImageShape()

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.displayName)
                    .font(.recipeCardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RecipeMetadataLine(recipe: recipe, isFavorite: isFavorite)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipe.accessibilitySummary + (isFavorite ? ", favorite" : ""))
    }
}

#Preview("Card grid") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.gridMinimumColumnWidth), spacing: Theme.Spacing.grid)],
                  spacing: Theme.Spacing.xl) {
            ForEach(RecipeSummary.previewSamples) { recipe in
                RecipeCard(recipe: recipe, isFavorite: recipe.slug == "tomato-soup")
            }
        }
        .padding(Theme.Spacing.screen)
    }
    .screenBackground()
}

extension RecipeSummary {
    /// Sample data for previews (no images, example data only).
    static let previewSamples: [RecipeSummary] = [
        RecipeSummary(id: "p1", slug: "lemon-herb-chicken", name: "Lemon Herb Chicken", recipeServings: 4, totalTime: "35 minutes", rating: 4.5),
        RecipeSummary(id: "p2", slug: "tomato-soup", name: "Roasted Tomato Soup with Basil", recipeServings: 2, prepTime: "10 min", cookTime: "40 min"),
        RecipeSummary(id: "p3", slug: "banana-bread", name: "Banana Bread", recipeServings: 8, totalTime: "PT1H10M", rating: 5),
        RecipeSummary(id: "p4", slug: "green-curry", name: "Green Curry", recipeServings: 4),
    ]
}
