import Foundation

// Categories, tags, tools, cookbooks, foods, units, labels.
extension MealieService {
    /// `GET /api/organizers/{categories|tags|tools}` (all, sorted by name).
    func organizers(_ kind: OrganizerKind) async throws -> [Organizer] {
        try await fetchAllPages("/api/organizers/\(kind.pathComponent)",
                                query: [URLQueryItem(name: "orderBy", value: "name"),
                                        URLQueryItem(name: "orderDirection", value: "asc")])
    }

    func categories() async throws -> [RecipeCategory] { try await organizers(.category) }
    func tags() async throws -> [RecipeTag] { try await organizers(.tag) }
    func tools() async throws -> [RecipeTool] { try await organizers(.tool) }

    /// `GET /api/organizers/{kind}/slug/{slug}`.
    func organizer(_ kind: OrganizerKind, slug: String) async throws -> Organizer {
        try await send(.get("/api/organizers/\(kind.pathComponent)/slug/\(slug.pathSegment)"))
    }

    /// `POST /api/organizers/{kind}` with `{ name }`.
    @discardableResult
    func createOrganizer(_ kind: OrganizerKind, name: String) async throws -> Organizer {
        struct Body: Encodable { let name: String }
        return try await send(.json(.post, "/api/organizers/\(kind.pathComponent)", body: Body(name: name)))
    }

    /// `GET /api/households/cookbooks` (sorted by position).
    func cookbooks() async throws -> [Cookbook] {
        try await fetchAllPages("/api/households/cookbooks",
                                query: [URLQueryItem(name: "orderBy", value: "position"),
                                        URLQueryItem(name: "orderDirection", value: "asc")])
    }

    /// `GET /api/households/cookbooks/{id or slug}`.
    func cookbook(id: String) async throws -> Cookbook {
        try await send(.get("/api/households/cookbooks/\(id.pathSegment)"))
    }

    /// `GET /api/foods` (paginated; use `search` for pickers).
    func foods(search: String? = nil, page: Int = 1, perPage: Int = 50) async throws -> Page<IngredientFood> {
        var query = PageQuery(page: page, perPage: perPage, orderBy: "name", orderDirection: .asc).queryItems
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        return try await send(.get("/api/foods", query: query))
    }

    /// `GET /api/units` (all; usually a few dozen).
    func units() async throws -> [IngredientUnit] {
        try await fetchAllPages("/api/units", query: [URLQueryItem(name: "orderBy", value: "name"),
                                                      URLQueryItem(name: "orderDirection", value: "asc")])
    }

    /// `GET /api/groups/labels` (all).
    func labels() async throws -> [MultiPurposeLabel] {
        try await fetchAllPages("/api/groups/labels", query: [URLQueryItem(name: "orderBy", value: "name"),
                                                              URLQueryItem(name: "orderDirection", value: "asc")])
    }
}
