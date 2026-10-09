import Foundation
import Observation

/// App-wide signal that the set of recipes changed on another screen (created, imported,
/// duplicated, deleted), so recipe lists reload and drop deleted recipes right away instead
/// of waiting for a pull-to-refresh.
@MainActor
@Observable
final class RecipeChanges {
    static let shared = RecipeChanges()

    /// Bumped on every change; lists reload when it changes.
    private(set) var revision = 0
    /// Recipes deleted in this app session; lists hide them before the reload lands.
    private(set) var deletedIDs: Set<String> = []

    /// A recipe was created, imported, duplicated or edited.
    func recipesChanged() {
        revision += 1
    }

    func recipeDeleted(id: String) {
        deletedIDs.insert(id)
        revision += 1
    }
}
