import Foundation

// Shopping lists and items (household-scoped).
extension MealieService {
    /// `GET /api/households/shopping/lists`: summaries without items.
    func shoppingLists() async throws -> [ShoppingList] {
        try await fetchAllPages("/api/households/shopping/lists",
                                query: [URLQueryItem(name: "orderBy", value: "name"),
                                        URLQueryItem(name: "orderDirection", value: "asc")])
    }

    /// `GET /api/households/shopping/lists/{id}` including items, label settings and recipe references.
    func shoppingList(id: String) async throws -> ShoppingList {
        try await send(.get("/api/households/shopping/lists/\(id.pathSegment)"))
    }

    /// `POST /api/households/shopping/lists`.
    @discardableResult
    func createShoppingList(name: String) async throws -> ShoppingList {
        struct Body: Encodable { let name: String }
        return try await send(.json(.post, "/api/households/shopping/lists", body: Body(name: name)))
    }

    /// `PUT /api/households/shopping/lists/{id}`: renames a list.
    ///
    /// Mealie replaces the list's items with the body's `listItems`, so this fetches the
    /// current list first and sends its items back unchanged.
    @discardableResult
    func renameShoppingList(id: String, to name: String) async throws -> ShoppingList {
        let current = try await shoppingList(id: id)
        guard let groupId = current.groupId, let userId = current.userId else {
            throw MealieError.decoding("The shopping list is missing its owner.")
        }
        let body = ShoppingListRename(id: id, groupId: groupId, userId: userId, name: name,
                                      extras: current.extras, listItems: current.items)
        return try await send(.json(.put, "/api/households/shopping/lists/\(id.pathSegment)", body: body))
    }

    /// `PUT /api/households/shopping/lists/{id}/label-settings`: the list's section (label)
    /// order. Returns the list with its items and the saved settings.
    @discardableResult
    func updateShoppingListLabelSettings(listID: String, settings: [ShoppingListLabelSettingUpdate]) async throws -> ShoppingList {
        try await send(.json(.put, "/api/households/shopping/lists/\(listID.pathSegment)/label-settings", body: settings))
    }

    /// `DELETE /api/households/shopping/lists/{id}`.
    func deleteShoppingList(id: String) async throws {
        try await perform(.delete("/api/households/shopping/lists/\(id.pathSegment)"))
    }

    /// `POST /api/households/shopping/items`. Mealie may merge with an existing item.
    @discardableResult
    func addShoppingItem(_ item: ShoppingListItemCreate) async throws -> ShoppingListItemsCollection {
        try await send(.json(.post, "/api/households/shopping/items", body: item))
    }

    /// `POST /api/households/shopping/items/create-bulk`.
    @discardableResult
    func addShoppingItems(_ items: [ShoppingListItemCreate]) async throws -> ShoppingListItemsCollection {
        try await send(.json(.post, "/api/households/shopping/items/create-bulk", body: items))
    }

    /// `PUT /api/households/shopping/items/{id}` (check/uncheck, edit). Send `item.update` with changes.
    @discardableResult
    func updateShoppingItem(_ update: ShoppingListItemUpdate) async throws -> ShoppingListItemsCollection {
        try await send(.json(.put, "/api/households/shopping/items/\(update.id.pathSegment)", body: update))
    }

    /// `PUT /api/households/shopping/items` (bulk update, e.g. reorder or check many).
    @discardableResult
    func updateShoppingItems(_ updates: [ShoppingListItemUpdate]) async throws -> ShoppingListItemsCollection {
        try await send(.json(.put, "/api/households/shopping/items", body: updates))
    }

    /// `DELETE /api/households/shopping/items/{id}`.
    func deleteShoppingItem(id: String) async throws {
        try await perform(.delete("/api/households/shopping/items/\(id.pathSegment)"))
    }

    /// `DELETE /api/households/shopping/items?ids=...` (e.g. "clear checked").
    func deleteShoppingItems(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await perform(.delete("/api/households/shopping/items", query: ids.map { URLQueryItem(name: "ids", value: $0) }))
    }

    /// `POST /api/households/shopping/lists/{id}/recipe`: adds recipe ingredients (scaled) to a list.
    @discardableResult
    func addRecipesToShoppingList(listID: String, recipes: [ShoppingListAddRecipe]) async throws -> ShoppingList {
        try await send(.json(.post, "/api/households/shopping/lists/\(listID.pathSegment)/recipe", body: recipes))
    }

    /// `POST /api/households/shopping/lists/{id}/recipe/{recipeID}/delete`: removes a recipe's items again.
    @discardableResult
    func removeRecipeFromShoppingList(listID: String, recipeID: String, quantity: Double = 1) async throws -> ShoppingList {
        struct Body: Encodable { let recipeDecrementQuantity: Double }
        return try await send(.json(.post, "/api/households/shopping/lists/\(listID.pathSegment)/recipe/\(recipeID.pathSegment)/delete",
                                    body: Body(recipeDecrementQuantity: quantity)))
    }
}
