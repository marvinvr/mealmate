import Foundation

// MARK: - Summary

/// A recipe as returned in lists (`RecipeSummary`): `GET /api/recipes`, meal
/// plan entries, shopping list recipe references.
struct RecipeSummary: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var slug: String
    var name: String?
    var userId: String?
    var householdId: String?
    var groupId: String?
    /// Image cache key (changes when the image changes). `nil` = no image.
    var image: FlexibleString?
    var recipeServings: Double?
    var recipeYieldQuantity: Double?
    var recipeYield: String?
    /// Free-form durations as entered/scraped (e.g. "45 minutes", "PT1H").
    var totalTime: String?
    var prepTime: String?
    var cookTime: String?
    var performTime: String?
    var description: String?
    var recipeCategory: [RecipeCategory]?
    var tags: [RecipeTag]?
    var tools: [RecipeTool]?
    /// Household/group average rating (1–5).
    var rating: Double?
    var orgURL: String?
    var dateAdded: MealieDay?
    var dateUpdated: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var lastMade: Date?

    var displayName: String { name?.isEmpty == false ? name! : slug }
    var imageKey: String? { image?.value }
    var hasImage: Bool { imageKey?.isEmpty == false }
    var categories: [RecipeCategory] { recipeCategory ?? [] }
    var tagList: [RecipeTag] { tags ?? [] }
    var toolList: [RecipeTool] { tools ?? [] }
}

// MARK: - Full recipe

/// A full recipe (`Recipe-Output`): `GET /api/recipes/{slug}`.
///
/// The summary fields are duplicated here on purpose (flat, synthesized
/// Codable both ways); use `summary` when a `RecipeSummary` is needed.
struct Recipe: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var slug: String
    var name: String?
    var userId: String?
    var householdId: String?
    var groupId: String?
    var image: FlexibleString?
    var recipeServings: Double?
    var recipeYieldQuantity: Double?
    var recipeYield: String?
    var totalTime: String?
    var prepTime: String?
    var cookTime: String?
    var performTime: String?
    var description: String?
    var recipeCategory: [RecipeCategory]?
    var tags: [RecipeTag]?
    var tools: [RecipeTool]?
    var rating: Double?
    var orgURL: String?
    var dateAdded: MealieDay?
    var dateUpdated: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var lastMade: Date?

    var recipeIngredient: [RecipeIngredient]?
    var recipeInstructions: [RecipeStep]?
    var nutrition: Nutrition?
    var settings: RecipeSettings?
    var assets: [RecipeAsset]?
    var notes: [RecipeNote]?
    var extras: [String: JSONValue]?
    var comments: [RecipeComment]?

    var displayName: String { name?.isEmpty == false ? name! : slug }
    var imageKey: String? { image?.value }
    var hasImage: Bool { imageKey?.isEmpty == false }
    var ingredients: [RecipeIngredient] { recipeIngredient ?? [] }
    var instructions: [RecipeStep] { recipeInstructions ?? [] }
    var noteList: [RecipeNote] { notes ?? [] }
    var categories: [RecipeCategory] { recipeCategory ?? [] }
    var tagList: [RecipeTag] { tags ?? [] }
    var toolList: [RecipeTool] { tools ?? [] }

    var summary: RecipeSummary {
        RecipeSummary(
            id: id, slug: slug, name: name, userId: userId, householdId: householdId, groupId: groupId,
            image: image, recipeServings: recipeServings, recipeYieldQuantity: recipeYieldQuantity,
            recipeYield: recipeYield, totalTime: totalTime, prepTime: prepTime, cookTime: cookTime,
            performTime: performTime, description: description, recipeCategory: recipeCategory,
            tags: tags, tools: tools, rating: rating, orgURL: orgURL, dateAdded: dateAdded,
            dateUpdated: dateUpdated, createdAt: createdAt, updatedAt: updatedAt, lastMade: lastMade
        )
    }
}

// MARK: - Parts

/// One ingredient line (`RecipeIngredient`). Also used by the parser and when
/// adding recipe ingredients to a shopping list.
struct RecipeIngredient: Codable, Hashable, Sendable {
    var quantity: Double?
    var unit: IngredientUnit?
    var food: IngredientFood?
    var note: String?
    /// Server-rendered line, e.g. "2 cups flour, sifted". Prefer it for display.
    var display: String?
    /// Section header: when set, this ingredient starts a new group titled `title`.
    var title: String?
    var originalText: String?
    /// Stable ID that steps reference via `RecipeStep.ingredientReferences`.
    var referenceId: String?
    var referencedRecipe: RecipeSummary?
    var substitutions: [JSONValue]?

    var displayText: String {
        if let display, !display.isEmpty { return display }
        if let originalText, !originalText.isEmpty { return originalText }
        return [quantity.map { $0.formatted() }, unit?.name, food?.name, note]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct RecipeStep: Codable, Hashable, Identifiable, Sendable {
    var id: String?
    var title: String?
    var summary: String?
    var text: String
    var ingredientReferences: [ReferenceID]?
    var noteReferences: [ReferenceID]?

    /// `{ "referenceId": "<uuid>" }` (ingredient or note reference).
    struct ReferenceID: Codable, Hashable, Sendable {
        var referenceId: String?
    }

    init(id: String? = UUID().uuidString.lowercased(), title: String? = nil, summary: String? = nil, text: String, ingredientReferences: [ReferenceID]? = [], noteReferences: [ReferenceID]? = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.text = text
        self.ingredientReferences = ingredientReferences
        self.noteReferences = noteReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        ingredientReferences = container.decodeLossyArrayIfPresent([ReferenceID].self, forKey: .ingredientReferences)
        noteReferences = container.decodeLossyArrayIfPresent([ReferenceID].self, forKey: .noteReferences)
    }
}

struct RecipeNote: Codable, Hashable, Sendable {
    var title: String
    var text: String
    var referenceId: String?
}

struct RecipeAsset: Codable, Hashable, Sendable {
    var name: String
    /// Material Design icon name, e.g. "mdi-file".
    var icon: String?
    var fileName: String?
}

struct RecipeSettings: Codable, Hashable, Sendable {
    var `public`: Bool?
    var showNutrition: Bool?
    var showAssets: Bool?
    var landscapeView: Bool?
    var disableComments: Bool?
    var locked: Bool?
}

/// Nutrition values are free-form strings (e.g. "320 kcal" or "320").
struct Nutrition: Codable, Hashable, Sendable {
    var calories: String?
    var carbohydrateContent: String?
    var cholesterolContent: String?
    var fatContent: String?
    var fiberContent: String?
    var proteinContent: String?
    var saturatedFatContent: String?
    var sodiumContent: String?
    var sugarContent: String?
    var transFatContent: String?
    var unsaturatedFatContent: String?

    /// Non-empty values in a sensible display order.
    var entries: [(label: String, value: String)] {
        let all: [(String, String?)] = [
            ("Calories", calories), ("Fat", fatContent), ("Saturated fat", saturatedFatContent),
            ("Trans fat", transFatContent), ("Unsaturated fat", unsaturatedFatContent),
            ("Cholesterol", cholesterolContent), ("Sodium", sodiumContent),
            ("Carbohydrates", carbohydrateContent), ("Fiber", fiberContent),
            ("Sugar", sugarContent), ("Protein", proteinContent),
        ]
        return all.compactMap { label, value in
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    var isEmpty: Bool { entries.isEmpty }
}

// MARK: - Comments

struct RecipeComment: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var recipeId: String?
    var text: String
    var createdAt: Date?
    var updatedAt: Date?
    var userId: String?
    var user: CommentUser?

    struct CommentUser: Codable, Hashable, Sendable {
        var id: String
        var username: String?
        var fullName: String?
        var admin: Bool?

        var displayName: String { fullName ?? username ?? "Someone" }
    }
}

struct RecipeCommentCreate: Codable, Hashable, Sendable {
    var recipeId: String
    var text: String
}

// MARK: - Timeline

/// `RecipeTimelineEventOut`: `GET /api/recipes/timeline/events`.
struct TimelineEvent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var recipeId: String
    var userId: String?
    var subject: String
    var eventType: TimelineEventType?
    var eventMessage: String?
    /// `"has image"` / `"does not have image"`.
    var image: String?
    var timestamp: Date?
    var groupId: String?
    var householdId: String?
    var createdAt: Date?
    var updatedAt: Date?

    var hasImage: Bool { image == "has image" }
}

struct TimelineEventType: OpenStringEnum {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    static let system: Self = "system"
    static let info: Self = "info"
    static let comment: Self = "comment"
}

/// Body of `POST /api/recipes/timeline/events`.
struct TimelineEventCreate: Codable, Hashable, Sendable {
    var recipeId: String
    var subject: String
    var eventType: TimelineEventType = .info
    var eventMessage: String?
    var timestamp: Date = Date()
    var userId: String?
}

// MARK: - Requests

/// Sort options for `GET /api/recipes`.
enum RecipeSort: String, CaseIterable, Sendable, Hashable {
    case recentlyAdded
    case recentlyUpdated
    case name
    case rating
    case lastMade
    case random

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .recentlyUpdated: "Recently Updated"
        case .name: "Name"
        case .rating: "Rating"
        case .lastMade: "Last Made"
        case .random: "Random"
        }
    }

    var orderBy: String {
        switch self {
        case .recentlyAdded: "created_at"
        case .recentlyUpdated: "updated_at"
        case .name: "name"
        case .rating: "rating"
        case .lastMade: "last_made"
        case .random: "random"
        }
    }

    var direction: PageQuery.SortDirection {
        self == .name ? .asc : .desc
    }
}

/// Filters for `GET /api/recipes`. Category/tag/tool/food filters accept IDs or slugs.
struct RecipeQuery: Sendable, Hashable {
    var search: String?
    var sort: RecipeSort = .recentlyAdded
    var categories: [String] = []
    var tags: [String] = []
    var tools: [String] = []
    var foods: [String] = []
    /// Cookbook ID or slug.
    var cookbook: String?
    var requireAllCategories = false
    var requireAllTags = false
    var requireAllTools = false
    var requireAllFoods = false
    var queryFilter: String?
    var page = 1
    var perPage = 30
    /// Needed for stable paging when `sort == .random`.
    var paginationSeed: String?

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(perPage)),
            URLQueryItem(name: "orderBy", value: sort.orderBy),
            URLQueryItem(name: "orderDirection", value: sort.direction.rawValue),
        ]
        if sort == .rating || sort == .lastMade {
            items.append(URLQueryItem(name: "orderByNullPosition", value: "last"))
        }
        if sort == .random {
            items.append(URLQueryItem(name: "paginationSeed", value: paginationSeed ?? UUID().uuidString))
        } else if let paginationSeed {
            items.append(URLQueryItem(name: "paginationSeed", value: paginationSeed))
        }
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        items += categories.map { URLQueryItem(name: "categories", value: $0) }
        items += tags.map { URLQueryItem(name: "tags", value: $0) }
        items += tools.map { URLQueryItem(name: "tools", value: $0) }
        items += foods.map { URLQueryItem(name: "foods", value: $0) }
        if let cookbook { items.append(URLQueryItem(name: "cookbook", value: cookbook)) }
        if requireAllCategories { items.append(URLQueryItem(name: "requireAllCategories", value: "true")) }
        if requireAllTags { items.append(URLQueryItem(name: "requireAllTags", value: "true")) }
        if requireAllTools { items.append(URLQueryItem(name: "requireAllTools", value: "true")) }
        if requireAllFoods { items.append(URLQueryItem(name: "requireAllFoods", value: "true")) }
        if let queryFilter { items.append(URLQueryItem(name: "queryFilter", value: queryFilter)) }
        return items
    }
}

/// Body of `POST /api/recipes/create/url`.
struct RecipeImportRequest: Codable, Hashable, Sendable {
    var url: String
    var includeTags = true
    var includeCategories = true
}

/// Body of `POST /api/recipes/create/ai` (only when `AIProviderSettings.isAIAvailable`).
struct RecipeAIImportRequest: Codable, Hashable, Sendable {
    var content: String?
    var url: String?
    var translateLanguage: String?
    var createNewOrganizers = false
}

/// Response of image upload / image-from-URL.
struct UpdateImageResponse: Codable, Hashable, Sendable {
    var image: String?
}
