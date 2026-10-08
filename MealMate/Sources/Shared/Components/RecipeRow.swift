import SwiftUI

/// List row: 56pt thumbnail, serif title, metadata. Use inside a `List`.
struct RecipeRow: View {
    let recipe: RecipeSummary
    var isFavorite = false
    /// Optional extra line under the metadata (e.g. a meal plan note).
    var subtitle: String?

    @ScaledMetric(relativeTo: .body) private var thumbnailSide: CGFloat = 56

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            RecipeImage(recipe: recipe, size: .tiny)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.displayName)
                    .font(.recipeRowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RecipeMetadataLine(recipe: recipe)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipe.accessibilitySummary + (isFavorite ? ", favorite" : ""))
    }
}

/// "35 min · ★ 4.5" under a card or row title. Decorative for VoiceOver (the card has a label).
struct RecipeMetadataLine: View {
    let recipe: RecipeSummary
    /// Trailing heart (cards; rows show it at the trailing edge instead).
    var isFavorite = false

    var body: some View {
        let metadata = recipe.cardMetadata
        let rating = RecipeFormatting.rating(recipe.rating)
        HStack(spacing: Theme.Spacing.xxs) {
            if let metadata {
                Text(metadata)
            }
            if metadata != nil, rating != nil {
                Text("·")
            }
            if let rating {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
                Text(rating)
            }
            if metadata == nil, rating == nil {
                Text(" ") // keeps card heights even
            }
            if isFavorite {
                Spacer(minLength: Theme.Spacing.xxs)
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
            }
        }
        .font(.metadata)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
}

#Preview("Rows") {
    List(RecipeSummary.previewSamples) { recipe in
        RecipeRow(recipe: recipe, isFavorite: recipe.slug == "tomato-soup")
    }
    .screenBackground()
}
