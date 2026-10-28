import Foundation

/// Which recipes a list shows before search and filters: everything, favorites, a cookbook
/// or one category / tag / tool. Library screens reuse the recipe list with a preset.
enum RecipeCollectionPreset: Hashable, Sendable {
    case all
    case favorites
    case cookbook(id: String)
    case organizer(OrganizerKind, slug: String)

    /// Cache key component for the first page.
    var cacheKey: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .cookbook(let id): "cookbook.\(id)"
        case .organizer(let kind, let slug): "\(kind.rawValue).\(slug)"
        }
    }
}

/// A selectable food in the filter sheet (only what the chip needs).
struct FoodFilter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// User-chosen filters on top of a preset (multi-select per kind, "any of" within a kind).
struct RecipeFilters: Codable, Hashable, Sendable {
    var categories: [Organizer] = []
    var tags: [Organizer] = []
    var tools: [Organizer] = []
    var foods: [FoodFilter] = []
    var favoritesOnly = false

    var isEmpty: Bool { count == 0 }

    /// Number of active filters (for the toolbar badge).
    var count: Int {
        categories.count + tags.count + tools.count + foods.count + (favoritesOnly ? 1 : 0)
    }

    func organizers(_ kind: OrganizerKind) -> [Organizer] {
        switch kind {
        case .category: categories
        case .tag: tags
        case .tool: tools
        }
    }

    func contains(_ organizer: Organizer, kind: OrganizerKind) -> Bool {
        organizers(kind).contains { $0.slug == organizer.slug }
    }

    mutating func toggle(_ organizer: Organizer, kind: OrganizerKind) {
        func toggle(in list: inout [Organizer]) {
            if let index = list.firstIndex(where: { $0.slug == organizer.slug }) {
                list.remove(at: index)
            } else {
                list.append(organizer)
            }
        }
        switch kind {
        case .category: toggle(in: &categories)
        case .tag: toggle(in: &tags)
        case .tool: toggle(in: &tools)
        }
    }

    mutating func toggle(_ food: FoodFilter) {
        if let index = foods.firstIndex(where: { $0.id == food.id }) {
            foods.remove(at: index)
        } else {
            foods.append(food)
        }
    }
}

/// Builds the `GET /api/recipes` query for a list state. Pure, so it's unit-tested.
enum RecipeListQueryBuilder {
    /// `nil` means the result is known to be empty without asking the server
    /// (favorites requested but the user has none).
    static func query(
        preset: RecipeCollectionPreset,
        search: String,
        sort: RecipeSort,
        filters: RecipeFilters,
        favoriteIDs: Set<String>,
        page: Int = 1,
        perPage: Int = 30,
        seed: String? = nil
    ) -> RecipeQuery? {
        var query = RecipeQuery()
        query.page = page
        // Today's Picks is ordered on the device, so it needs the whole result set at once.
        query.perPage = sort == .todaysPicks ? -1 : perPage
        query.sort = sort
        query.paginationSeed = sort == .random ? (seed ?? UUID().uuidString) : nil

        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        query.search = trimmed.isEmpty ? nil : trimmed

        // Organizer filters accept slugs; prefer IDs when known (unambiguous).
        query.categories = filters.categories.map { $0.id ?? $0.slug }
        query.tags = filters.tags.map { $0.id ?? $0.slug }
        query.tools = filters.tools.map { $0.id ?? $0.slug }
        query.foods = filters.foods.map(\.id)

        switch preset {
        case .all, .favorites:
            break
        case .cookbook(let id):
            query.cookbook = id
        case .organizer(let kind, let slug):
            switch kind {
            case .category: if !query.categories.contains(slug) { query.categories.insert(slug, at: 0) }
            case .tag: if !query.tags.contains(slug) { query.tags.insert(slug, at: 0) }
            case .tool: if !query.tools.contains(slug) { query.tools.insert(slug, at: 0) }
            }
            // The preset must always apply, other selections narrow it further.
            switch kind {
            case .category: query.requireAllCategories = query.categories.count > 1
            case .tag: query.requireAllTags = query.tags.count > 1
            case .tool: query.requireAllTools = query.tools.count > 1
            }
        }

        if preset == .favorites || filters.favoritesOnly {
            guard !favoriteIDs.isEmpty else { return nil }
            let ids = favoriteIDs.sorted().map { "\"\($0)\"" }.joined(separator: ",")
            query.queryFilter = "id IN [\(ids)]"
        }
        return query
    }
}

/// "Today's Picks": recipes ordered by a stable hash of (recipe ID, local day), so the
/// order is the same all day and changes daily. Pure, so it's unit-tested.
enum RecipeDailyOrder {
    /// Local calendar day as `yyyy-MM-dd`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// FNV-1a (stable across launches, unlike `Hasher`) plus a fmix64 finalizer, so a
    /// one-digit change in the date reshuffles everything.
    static func rank(id: String, day: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(id)|\(day)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        hash ^= hash >> 33
        hash &*= 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        hash &*= 0xc4ce_b9fe_1a85_ec53
        hash ^= hash >> 33
        return hash
    }

    static func sorted(_ recipes: [RecipeSummary], day: String) -> [RecipeSummary] {
        recipes
            .map { (rank: rank(id: $0.id, day: day), recipe: $0) }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.recipe.id < $1.recipe.id }
            .map(\.recipe)
    }
}
