import Foundation

/// A household recipe action (`GroupRecipeActionOut`), e.g. a "Send to Bring"
/// webhook (`post`) or a link template (`link`).
struct RecipeAction: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// For `link`: URL template; for `post`: the endpoint Mealie posts the recipe to.
    var url: String
    var actionType: RecipeActionType
    var groupId: String?
    var householdId: String?

    var isLink: Bool { actionType == .link }
}

struct RecipeActionType: OpenStringEnum {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    /// Opens `url` in the browser (the web UI substitutes recipe placeholders).
    static let link: Self = "link"
    /// Mealie POSTs the recipe JSON to `url` server-side (trigger endpoint).
    static let post: Self = "post"
}

/// Body of `POST /api/households/recipe-actions/{id}/trigger/{slug}`.
struct RecipeActionTrigger: Codable, Hashable, Sendable {
    var recipeScale: Double = 1

    enum CodingKeys: String, CodingKey {
        case recipeScale = "recipe_scale"
    }
}
