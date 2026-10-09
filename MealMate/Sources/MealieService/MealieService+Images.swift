import Foundation

/// Image variants Mealie generates for every recipe image (all WebP).
enum RecipeImageSize: String, Sendable, CaseIterable {
    /// Full size.
    case original
    /// ~600px wide; good for cards and the detail hero on phones.
    case min
    /// ~300px wide; list thumbnails.
    case tiny

    var fileName: String {
        switch self {
        case .original: "original.webp"
        case .min: "min-original.webp"
        case .tiny: "tiny-original.webp"
        }
    }
}

// Media URLs. Mealie serves media without auth, but `mediaRequest` adds the bearer token
// anyway so servers behind an auth proxy (or a future Mealie) still deliver the file.
extension MealieService {
    /// `GET` request for a media URL, carrying the bearer token when the service has one.
    func mediaRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// `/api/media/recipes/{id}/images/{size}.webp?version=<imageKey>`.
    /// The image key is appended so a changed image isn't served from cache.
    func recipeImageURL(recipeID: String, imageKey: String?, size: RecipeImageSize = .min) -> URL? {
        url(path: "/api/media/recipes/\(recipeID.pathSegment)/images/\(size.fileName)",
            query: imageKey.map { [URLQueryItem(name: "version", value: $0)] } ?? [])
    }

    /// `nil` when the recipe has no image.
    func imageURL(for recipe: RecipeSummary, size: RecipeImageSize = .min) -> URL? {
        guard recipe.hasImage else { return nil }
        return recipeImageURL(recipeID: recipe.id, imageKey: recipe.imageKey, size: size)
    }

    func imageURL(for recipe: Recipe, size: RecipeImageSize = .original) -> URL? {
        guard recipe.hasImage else { return nil }
        return recipeImageURL(recipeID: recipe.id, imageKey: recipe.imageKey, size: size)
    }

    /// Recipe asset file (`RecipeAsset.fileName`).
    func recipeAssetURL(recipeID: String, fileName: String) -> URL? {
        url(path: "/api/media/recipes/\(recipeID.pathSegment)/assets/\(fileName.pathSegment)")
    }
}
