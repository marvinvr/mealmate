import SwiftUI

/// Renders an `AppDestination`. Each feature replaces its placeholder case
/// with the real screen (keep this file a thin switch).
struct AppDestinationView: View {
    let destination: AppDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch destination {
        case .recipe(let slug):
            RecipeDetailView(slug: slug)
        case .cookMode(let slug):
            CookModeView(slug: slug)
        case .shoppingList(let id):
            ShoppingListView(listID: id)
        case .cookbook(let id):
            RecipeCollectionScreen(preset: .cookbook(id: id))
        case .organizer(let kind, let slug):
            RecipeCollectionScreen(preset: .organizer(kind, slug: slug))
        }
    }

    private func placeholder(_ title: String, systemImage: String, detail: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .navigationTitle(title)
    }
}
