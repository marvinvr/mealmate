import Foundation

// Recipes: list/search, detail, create/import, edit, images, favorites,
// ratings, last made, timeline, comments, recipe actions.
extension MealieService {
    // MARK: List & detail

    /// `GET /api/recipes` with search, filters and sort.
    func recipes(_ query: RecipeQuery = RecipeQuery()) async throws -> Page<RecipeSummary> {
        try await send(.get("/api/recipes", query: query.queryItems))
    }

    /// `GET /api/recipes/{slug}` (slug or ID).
    func recipe(slug: String) async throws -> Recipe {
        try await send(.get("/api/recipes/\(slug.pathSegment)"))
    }

    // MARK: Create / import

    /// `POST /api/recipes`: creates an empty recipe and returns its slug.
    func createRecipe(name: String) async throws -> String {
        struct Body: Encodable { let name: String }
        return try await send(.json(.post, "/api/recipes", body: Body(name: name)), as: String.self)
    }

    /// `POST /api/recipes/create/url`: scrapes a recipe URL and returns the new recipe's slug.
    /// Scraping can be slow, so the timeout is generous.
    func createRecipe(fromURL url: String, includeTags: Bool = true, includeCategories: Bool = true) async throws -> String {
        var request = try MealieRequest.json(.post, "/api/recipes/create/url",
                                             body: RecipeImportRequest(url: url, includeTags: includeTags, includeCategories: includeCategories))
        request.timeout = 120
        return try await send(request, as: String.self)
    }

    /// `POST /api/recipes/create/ai` (multipart form). Only when `aiProviderSettings().isAIAvailable`.
    /// `images` are JPEG data (photos of a cookbook page, a handwritten card, ...); they
    /// need the group's image provider (`AIProviderSettings.isImageImportAvailable`).
    func createRecipeWithAI(_ body: RecipeAIImportRequest, images: [Data] = []) async throws -> String {
        var parts: [MultipartPart] = []
        if let content = body.content { parts.append(.field("content", content)) }
        if let url = body.url { parts.append(.field("url", url)) }
        if let language = body.translateLanguage { parts.append(.field("translateLanguage", language)) }
        parts.append(.field("createNewOrganizers", body.createNewOrganizers ? "true" : "false"))
        for (index, image) in images.enumerated() {
            parts.append(.file("images", data: image, fileName: "image-\(index + 1).jpg", mimeType: "image/jpeg"))
        }
        var request = MealieRequest.multipart(.post, "/api/recipes/create/ai", parts: parts)
        request.timeout = 180
        return try await send(request, as: String.self)
    }

    // MARK: Update

    /// `PUT /api/recipes/{slug}` with a full recipe (fetch → modify → send back).
    @discardableResult
    func updateRecipe(_ recipe: Recipe) async throws -> Recipe {
        try await send(.json(.put, "/api/recipes/\(recipe.slug.pathSegment)", body: recipe))
    }

    /// `PATCH /api/recipes/{slug}` with only the given fields (any `Encodable`, nil fields omitted).
    @discardableResult
    func patchRecipe(slug: String, fields: some Encodable & Sendable) async throws -> Recipe {
        try await send(.json(.patch, "/api/recipes/\(slug.pathSegment)", body: fields))
    }

    /// `DELETE /api/recipes/{slug}`.
    func deleteRecipe(slug: String) async throws {
        try await perform(.delete("/api/recipes/\(slug.pathSegment)"))
    }

    /// `POST /api/recipes/{slug}/duplicate` → the new recipe. Without a name Mealie
    /// picks one (the original name with a number appended).
    func duplicateRecipe(slug: String, name: String? = nil) async throws -> Recipe {
        struct Body: Encodable { let name: String? }
        return try await send(.json(.post, "/api/recipes/\(slug.pathSegment)/duplicate", body: Body(name: name)))
    }

    // MARK: Images

    /// `PUT /api/recipes/{slug}/image` (multipart: `image` file + `extension`).
    @discardableResult
    func uploadRecipeImage(slug: String, imageData: Data, fileExtension: String = "jpg") async throws -> UpdateImageResponse {
        let mime = fileExtension == "png" ? "image/png" : fileExtension == "webp" ? "image/webp" : "image/jpeg"
        var request = MealieRequest.multipart(.put, "/api/recipes/\(slug.pathSegment)/image", parts: [
            .file("image", data: imageData, fileName: "image.\(fileExtension)", mimeType: mime),
            .field("extension", fileExtension),
        ])
        request.timeout = 120
        return try await send(request)
    }

    /// `POST /api/recipes/{slug}/image` with `{ "url": ... }`: server downloads the image.
    @discardableResult
    func setRecipeImage(slug: String, fromURL url: String) async throws -> UpdateImageResponse {
        struct Body: Encodable { let url: String; let includeTags = false; let includeCategories = false }
        var request = try MealieRequest.json(.post, "/api/recipes/\(slug.pathSegment)/image", body: Body(url: url))
        request.timeout = 60
        return try await send(request)
    }

    // MARK: Favorites & ratings (per user)

    /// `GET /api/users/self/favorites`: the current user's favorites (`isFavorite == true`).
    func favorites() async throws -> [UserRating] {
        try await send(.get("/api/users/self/favorites"), as: UserRatings.self).ratings
    }

    /// `GET /api/users/self/ratings`: the current user's ratings and favorites.
    func myRatings() async throws -> [UserRating] {
        try await send(.get("/api/users/self/ratings"), as: UserRatings.self).ratings
    }

    /// `POST`/`DELETE /api/users/{userID}/favorites/{slug}`.
    func setFavorite(_ isFavorite: Bool, slug: String, userID: String) async throws {
        let path = "/api/users/\(userID.pathSegment)/favorites/\(slug.pathSegment)"
        try await perform(isFavorite ? .empty(.post, path) : .delete(path))
    }

    /// `POST /api/users/{userID}/ratings/{slug}` with `{ rating }` (1–5).
    /// Quirk: Mealie ignores `"rating": null`, so clearing sends `0`.
    func setRating(_ rating: Double?, slug: String, userID: String) async throws {
        struct Body: Encodable { let rating: Double }
        try await perform(.json(.post, "/api/users/\(userID.pathSegment)/ratings/\(slug.pathSegment)", body: Body(rating: rating ?? 0)))
    }

    // MARK: Made it / timeline

    /// `PATCH /api/recipes/{slug}/last-made` → updated recipe. Does NOT create a
    /// timeline event; call `createTimelineEvent` too for "Made it".
    @discardableResult
    func markLastMade(slug: String, at date: Date = Date()) async throws -> Recipe {
        struct Body: Encodable { let timestamp: Date }
        return try await send(.json(.patch, "/api/recipes/\(slug.pathSegment)/last-made", body: Body(timestamp: date)))
    }

    /// `GET /api/recipes/timeline/events` filtered to one recipe, newest first.
    func timelineEvents(recipeID: String, page: Int = 1, perPage: Int = 50) async throws -> Page<TimelineEvent> {
        var query = PageQuery(page: page, perPage: perPage, orderBy: "timestamp", orderDirection: .desc)
        query.queryFilter = "recipe_id=\"\(recipeID)\""
        return try await send(.get("/api/recipes/timeline/events", query: query.queryItems))
    }

    /// `POST /api/recipes/timeline/events`.
    @discardableResult
    func createTimelineEvent(_ event: TimelineEventCreate) async throws -> TimelineEvent {
        try await send(.json(.post, "/api/recipes/timeline/events", body: event))
    }

    /// `DELETE /api/recipes/timeline/events/{id}`.
    func deleteTimelineEvent(id: String) async throws {
        try await perform(.delete("/api/recipes/timeline/events/\(id.pathSegment)"))
    }

    /// `PUT /api/recipes/timeline/events/{id}/image` (multipart: `image` file + `extension`).
    @discardableResult
    func uploadTimelineImage(eventID: String, imageData: Data) async throws -> UpdateImageResponse {
        var request = MealieRequest.multipart(.put, "/api/recipes/timeline/events/\(eventID.pathSegment)/image", parts: [
            .file("image", data: imageData, fileName: "image.jpg", mimeType: "image/jpeg"),
            .field("extension", "jpg"),
        ])
        request.timeout = 120
        return try await send(request)
    }

    /// Image of a timeline event (when `TimelineEvent.hasImage`).
    func timelineImageURL(recipeID: String, eventID: String, size: RecipeImageSize = .min) -> URL? {
        url(path: "/api/media/recipes/\(recipeID.pathSegment)/images/timeline/\(eventID.pathSegment)/\(size.fileName)")
    }

    // MARK: Comments

    /// `GET /api/recipes/{slug}/comments`.
    func comments(slug: String) async throws -> [RecipeComment] {
        try await send(.get("/api/recipes/\(slug.pathSegment)/comments"), as: LossyArray<RecipeComment>.self).elements
    }

    /// `POST /api/comments`.
    @discardableResult
    func addComment(recipeID: String, text: String) async throws -> RecipeComment {
        try await send(.json(.post, "/api/comments", body: RecipeCommentCreate(recipeId: recipeID, text: text)))
    }

    /// `DELETE /api/comments/{id}`.
    func deleteComment(id: String) async throws {
        try await perform(.delete("/api/comments/\(id.pathSegment)"))
    }

    // MARK: Public links (share tokens)

    /// `GET /api/shared/recipes?recipe_id=`: the recipe's public links (not paginated).
    func shareTokens(recipeID: String) async throws -> [RecipeShareToken] {
        try await send(.get("/api/shared/recipes", query: [URLQueryItem(name: "recipe_id", value: recipeID)]),
                       as: LossyArray<RecipeShareToken>.self).elements
    }

    /// `POST /api/shared/recipes`: a link anyone can open without an account, until `expiresAt`.
    @discardableResult
    func createShareToken(recipeID: String, expiresAt: Date) async throws -> RecipeShareToken {
        struct Body: Encodable { let recipeId: String; let expiresAt: Date }
        return try await send(.json(.post, "/api/shared/recipes", body: Body(recipeId: recipeID, expiresAt: expiresAt)))
    }

    /// `DELETE /api/shared/recipes/{id}`: revokes a public link.
    func deleteShareToken(id: String) async throws {
        try await perform(.delete("/api/shared/recipes/\(id.pathSegment)"))
    }

    // MARK: Recipe actions

    /// `GET /api/households/recipe-actions` (all of them; households rarely have many).
    func recipeActions() async throws -> [RecipeAction] {
        try await send(.get("/api/households/recipe-actions", query: PageQuery.all.queryItems), as: Page<RecipeAction>.self).items
    }

    /// `POST /api/households/recipe-actions/{id}/trigger/{slug}` (for `post` actions; 202 Accepted).
    func triggerRecipeAction(id: String, slug: String, scale: Double = 1) async throws {
        try await perform(.json(.post, "/api/households/recipe-actions/\(id.pathSegment)/trigger/\(slug.pathSegment)",
                                body: RecipeActionTrigger(recipeScale: scale)))
    }
}
