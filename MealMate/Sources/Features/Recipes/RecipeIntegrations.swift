import SwiftUI

/// Sheets that recipe screens present, implemented by other features (shopping, meal
/// plan, editor, import). Kept in one place so the recipe screens don't depend on their
/// internals.
enum RecipeSheet: Identifiable {
    /// From a list (loads the recipe first, servings as written).
    case addToShoppingList(slug: String)
    /// From the detail screen, with the chosen servings scale.
    case addRecipeToShoppingList(Recipe, scale: Double)
    case addToMealPlan(RecipeSummary)
    case newRecipe
    case importRecipe
    case edit(Recipe)

    var id: String {
        switch self {
        case .addToShoppingList(let slug): "shopping-\(slug)"
        case .addRecipeToShoppingList(let recipe, let scale): "shopping-\(recipe.id)-\(scale)"
        case .addToMealPlan(let recipe): "mealplan-\(recipe.id)"
        case .newRecipe: "new"
        case .importRecipe: "import"
        case .edit(let recipe): "edit-\(recipe.id)"
        }
    }
}

/// Renders a `RecipeSheet` with the owning feature's view.
struct RecipeSheetView: View {
    let sheet: RecipeSheet
    /// Called with the saved recipe after editing.
    var onRecipeSaved: ((Recipe) -> Void)?

    var body: some View {
        switch sheet {
        case .addToShoppingList(let slug):
            AddToShoppingListSheet(slug: slug)
        case .addRecipeToShoppingList(let recipe, let scale):
            AddToShoppingListSheet(recipe: recipe, scale: scale)
        case .addToMealPlan(let recipe):
            AddToMealPlanSheet(recipe: recipe)
        case .newRecipe:
            RecipeEditorView()
        case .importRecipe:
            ImportRecipeView()
        case .edit(let recipe):
            RecipeEditorView(recipe: recipe, onSave: onRecipeSaved)
        }
    }
}

// MARK: - Links & plain text

enum RecipeLinks {
    /// The recipe on the Mealie web UI: `<server>/g/<group>/r/<slug>`.
    static func webURL(server: URL, groupSlug: String?, slug: String) -> URL? {
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let groupSlug, !groupSlug.isEmpty else {
            return URL(string: "\(base)/recipe/\(slug.pathSegment)")
        }
        return URL(string: "\(base)/g/\(groupSlug.pathSegment)/r/\(slug.pathSegment)")
    }

    /// A public link (share token) on the Mealie web UI: `<server>/g/<group>/shared/r/<token>`.
    /// Needs the group slug; Mealie has no group-less form of this page.
    static func publicURL(server: URL, groupSlug: String?, tokenID: String) -> URL? {
        guard let groupSlug, !groupSlug.isEmpty else { return nil }
        var base = server.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/g/\(groupSlug.pathSegment)/shared/r/\(tokenID.pathSegment)")
    }

    /// Plain-text recipe for sharing: title, description, ingredients, steps.
    static func plainText(_ recipe: Recipe, scale: Double = 1, servings: Double? = nil) -> String {
        var lines: [String] = [recipe.displayName]
        if let description = recipe.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            lines += ["", description]
        }
        if let servings = RecipeFormatting.servings(servings ?? recipe.recipeServings) {
            lines += ["", servings]
        }
        let ingredientSections = RecipeSections.ingredients(recipe.ingredients)
        if !ingredientSections.isEmpty {
            lines += ["", "Ingredients"]
            for section in ingredientSections {
                if let title = section.title { lines += ["", title] }
                for entry in section.items {
                    lines.append("• " + IngredientFormatting.text(for: entry.item, scale: scale))
                }
            }
        }
        let stepSections = RecipeSections.steps(recipe.instructions)
        if !stepSections.isEmpty {
            lines += ["", "Steps"]
            var number = 1
            for section in stepSections {
                if let title = section.title { lines += ["", title] }
                for entry in section.items {
                    lines.append("\(number). \(entry.item.text.trimmingCharacters(in: .whitespacesAndNewlines))")
                    number += 1
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Toast

/// A short confirmation shown at the bottom of a screen ("Added to favorites").
struct RecipeToast: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var systemImage: String
    var isError = false
}

extension View {
    /// Shows `toast` for a couple of seconds as a floating glass capsule.
    func recipeToast(_ toast: Binding<RecipeToast?>) -> some View {
        modifier(RecipeToastModifier(toast: toast))
    }
}

private struct RecipeToastModifier: ViewModifier {
    @Binding var toast: RecipeToast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    Label(toast.message, systemImage: toast.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(toast.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, Theme.Spacing.m)
                        .padding(.horizontal, Theme.Spacing.screen)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                        .accessibilityAddTraits(.updatesFrequently)
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.message).post()
                            try? await Task.sleep(for: .seconds(2.4))
                            if !Task.isCancelled {
                                withAnimation(.smooth) { self.toast = nil }
                            }
                        }
                }
            }
            .animation(.smooth, value: toast)
            .sensoryFeedback(trigger: toast) { _, new in
                guard let new else { return nil }
                return new.isError ? .error : .success
            }
    }
}
