import Foundation

// MARK: - Categories, tags, tools

/// A category, tag or tool. All three share the same shape in Mealie
/// (`RecipeCategory`, `RecipeTag`, `RecipeTool`, `CategoryOut`, `TagOut`,
/// `RecipeToolOut`); tools additionally carry `householdsWithTool`.
struct Organizer: Codable, Hashable, Identifiable, Sendable {
    /// Missing in some embedded payloads (e.g. organizers inside a scraped recipe).
    var id: String?
    var groupId: String?
    var name: String
    var slug: String
    var recipeCount: Int?
    /// Tools only: household slugs that own this tool ("on hand").
    var householdsWithTool: [String]?

    var stableID: String { id ?? slug }
}

typealias RecipeCategory = Organizer
typealias RecipeTag = Organizer
typealias RecipeTool = Organizer

/// Which organizer endpoint to talk to.
enum OrganizerKind: String, CaseIterable, Sendable, Hashable {
    case category, tag, tool

    var pathComponent: String {
        switch self {
        case .category: "categories"
        case .tag: "tags"
        case .tool: "tools"
        }
    }

    var title: String {
        switch self {
        case .category: "Categories"
        case .tag: "Tags"
        case .tool: "Tools"
        }
    }

    var systemImage: String {
        switch self {
        case .category: "square.grid.2x2"
        case .tag: "tag"
        case .tool: "frying.pan"
        }
    }
}

// MARK: - Cookbooks

/// `ReadCookBook`: `GET /api/households/cookbooks`.
struct Cookbook: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String?
    var slug: String?
    var position: Int?
    var `public`: Bool?
    /// Mealie query filter string selecting the cookbook's recipes.
    var queryFilterString: String?
    var groupId: String?
    var householdId: String?
    var household: Household?

    struct Household: Codable, Hashable, Sendable {
        var id: String
        var name: String
    }
}

// MARK: - Foods, units, labels

/// `IngredientFood`.
struct IngredientFood: Codable, Hashable, Sendable {
    /// `nil` for a food that does not exist on the server yet (create payloads).
    var id: String?
    var name: String
    var pluralName: String?
    var description: String?
    var labelId: String?
    var label: MultiPurposeLabel?
    var aliases: [Alias]?
    /// Household slugs that have this food on hand.
    var householdsWithIngredientFood: [String]?
    var extras: [String: JSONValue]?
    var createdAt: Date?
    var updatedAt: Date?

    struct Alias: Codable, Hashable, Sendable {
        var name: String
    }

    func isOnHand(householdSlug: String?) -> Bool {
        guard let householdSlug, let households = householdsWithIngredientFood else { return false }
        return households.contains(householdSlug)
    }
}

/// `IngredientUnit`.
struct IngredientUnit: Codable, Hashable, Sendable {
    var id: String?
    var name: String
    var pluralName: String?
    var description: String?
    var abbreviation: String?
    var pluralAbbreviation: String?
    var useAbbreviation: Bool?
    var fraction: Bool?
    var aliases: [Alias]?
    var standardQuantity: Double?
    var standardUnit: String?
    var extras: [String: JSONValue]?
    var createdAt: Date?
    var updatedAt: Date?

    struct Alias: Codable, Hashable, Sendable {
        var name: String
    }
}

/// Shopping / food label (`MultiPurposeLabelOut`). `color` is a hex string like `#959595`.
struct MultiPurposeLabel: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var color: String?
    var groupId: String?
}
