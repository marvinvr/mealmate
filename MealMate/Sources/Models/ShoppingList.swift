import Foundation

/// A shopping list (`ShoppingListOut` / `ShoppingListSummary`).
///
/// The list endpoint (`GET /api/households/shopping/lists`) returns summaries
/// without `listItems`; `GET /api/households/shopping/lists/{id}` includes them.
struct ShoppingList: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String?
    var groupId: String?
    var userId: String?
    var householdId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var listItems: [ShoppingListItem]?
    var recipeReferences: [ShoppingListRecipeReference]?
    /// Label order for this list (drives section order when grouping by label).
    var labelSettings: [LabelSetting]?
    var extras: [String: JSONValue]?

    var displayName: String { name?.isEmpty == false ? name! : "Shopping list" }
    var items: [ShoppingListItem] { listItems ?? [] }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        groupId = try? container.decodeIfPresent(String.self, forKey: .groupId)
        userId = try? container.decodeIfPresent(String.self, forKey: .userId)
        householdId = try? container.decodeIfPresent(String.self, forKey: .householdId)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        listItems = container.decodeLossyArrayIfPresent([ShoppingListItem].self, forKey: .listItems)
        recipeReferences = container.decodeLossyArrayIfPresent([ShoppingListRecipeReference].self, forKey: .recipeReferences)
        labelSettings = container.decodeLossyArrayIfPresent([LabelSetting].self, forKey: .labelSettings)
        extras = try? container.decodeIfPresent([String: JSONValue].self, forKey: .extras)
    }

    struct LabelSetting: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var shoppingListId: String?
        var labelId: String
        var position: Int?
        var label: MultiPurposeLabel?
    }
}

/// `ShoppingListItemOut`.
struct ShoppingListItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var shoppingListId: String
    var quantity: Double?
    var unit: IngredientUnit?
    var food: IngredientFood?
    var note: String?
    /// Server-rendered line ("2 cups flour"). Prefer it for display.
    var display: String?
    var checked: Bool
    var position: Int?
    var foodId: String?
    var labelId: String?
    var unitId: String?
    var label: MultiPurposeLabel?
    var recipeReferences: [RecipeReference]?
    var extras: [String: JSONValue]?
    var groupId: String?
    var householdId: String?
    var createdAt: Date?
    var updatedAt: Date?

    var displayText: String {
        if let display, !display.isEmpty { return display }
        return [quantity.map { $0.formatted() }, unit?.name, food?.name, note]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Which recipe(s) this item came from (`ShoppingListItemRecipeRefOut`).
    struct RecipeReference: Codable, Hashable, Sendable {
        var id: String?
        var recipeId: String
        var recipeQuantity: Double?
        var recipeScale: Double?
        var recipeNote: String?
        var shoppingListItemId: String?
    }

    /// Payload for `PUT /api/households/shopping/items/{id}` with the fields Mealie expects.
    var update: ShoppingListItemUpdate {
        ShoppingListItemUpdate(
            id: id, shoppingListId: shoppingListId, quantity: quantity, note: note, display: display,
            checked: checked, position: position, foodId: foodId, labelId: labelId, unitId: unitId,
            extras: extras, recipeReferences: recipeReferences
        )
    }
}

/// A recipe added to a list (`ShoppingListRecipeRefOut`).
struct ShoppingListRecipeReference: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var shoppingListId: String?
    var recipeId: String
    var recipeQuantity: Double?
    var recipe: RecipeSummary?
}

/// Body of `POST /api/households/shopping/items` and `create-bulk`.
struct ShoppingListItemCreate: Codable, Hashable, Sendable {
    var shoppingListId: String
    var quantity: Double?
    var note: String?
    var display: String?
    var checked = false
    var position: Int?
    var foodId: String?
    var labelId: String?
    var unitId: String?
}

/// Body of `PUT /api/households/shopping/items/{id}` (and bulk `PUT .../items`, which needs `id`).
struct ShoppingListItemUpdate: Codable, Hashable, Sendable {
    var id: String
    var shoppingListId: String
    var quantity: Double?
    var note: String?
    var display: String?
    var checked: Bool
    var position: Int?
    var foodId: String?
    var labelId: String?
    var unitId: String?
    var extras: [String: JSONValue]?
    /// Must be sent back unchanged: an update without them drops the item's recipe
    /// references (and with them the list's "added from recipe" entry).
    /// Mealie removes them itself when an item is checked.
    var recipeReferences: [ShoppingListItem.RecipeReference]?
}

/// Body of `PUT /api/households/shopping/lists/{id}` (rename).
///
/// Mealie replaces the list's items with `listItems` (missing = all items deleted),
/// so a rename must send the current items back.
struct ShoppingListRename: Encodable, Sendable {
    var id: String
    var groupId: String
    var userId: String
    var name: String
    var extras: [String: JSONValue]?
    var listItems: [ShoppingListItem]
}

/// Response of item create/update/delete: Mealie merges duplicates server-side,
/// so a single change can create, update and delete several items.
struct ShoppingListItemsCollection: Codable, Hashable, Sendable {
    var createdItems: [ShoppingListItem]
    var updatedItems: [ShoppingListItem]
    var deletedItems: [ShoppingListItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdItems = container.decodeLossyArrayIfPresent([ShoppingListItem].self, forKey: .createdItems) ?? []
        updatedItems = container.decodeLossyArrayIfPresent([ShoppingListItem].self, forKey: .updatedItems) ?? []
        deletedItems = container.decodeLossyArrayIfPresent([ShoppingListItem].self, forKey: .deletedItems) ?? []
    }
}

/// Element of the body of `POST /api/households/shopping/lists/{id}/recipe`.
struct ShoppingListAddRecipe: Codable, Hashable, Sendable {
    var recipeId: String
    /// Multiplier for the recipe's ingredient quantities (servings scale).
    var recipeIncrementQuantity: Double = 1
    /// Optional subset of ingredients; `nil` adds all.
    var recipeIngredients: [RecipeIngredient]?
}
