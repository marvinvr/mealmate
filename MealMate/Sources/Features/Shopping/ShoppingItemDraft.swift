import Foundation

/// Turns what the user typed into the add bar into a shopping item (unit tested).
enum ShoppingItemDraft {
    /// Builds the create payload from Mealie's parser result.
    ///
    /// Only foods and units that exist on the server are linked (by id); the parser
    /// also returns unknown ones (id `nil`), which become part of the note so nothing
    /// the user typed is lost and no foods are created behind their back. Without a
    /// known food or unit the item is the typed text as a note. Without a typed quantity
    /// the quantity is 0, which Mealie displays without a number ("milk", not "1 milk").
    static func item(from parsed: ParsedIngredient?, input: String, listID: String) -> ShoppingListItemCreate {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = ShoppingListItemCreate(shoppingListId: listID, quantity: 0, note: text)
        guard let ingredient = parsed?.ingredient else { return item }

        let food = ingredient.food.flatMap { $0.id == nil ? nil : $0 }
        let unit = ingredient.unit.flatMap { $0.id == nil ? nil : $0 }
        guard food != nil || unit != nil else { return item }

        let quantity = ingredient.quantity ?? 0
        item.quantity = quantity > 0 ? quantity : 0
        item.foodId = food?.id
        item.unitId = unit?.id
        item.labelId = food?.labelId ?? food?.label?.id

        var noteParts: [String] = []
        if unit == nil, let unitName = ingredient.unit?.name.trimmed, !unitName.isEmpty {
            noteParts.append(unitName)
        }
        if food == nil, let foodName = ingredient.food?.name.trimmed, !foodName.isEmpty {
            noteParts.append(foodName)
        }
        var note = noteParts.joined(separator: " ")
        if let comment = ingredient.note?.trimmed, !comment.isEmpty {
            note = note.isEmpty ? comment : "\(note), \(comment)"
        }
        item.note = note
        return item
    }

    /// Local stand-in shown while the item is being parsed and created.
    static func placeholder(for input: String, listID: String) -> ShoppingListItem {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return ShoppingListItem(
            id: pendingPrefix + UUID().uuidString, shoppingListId: listID, quantity: nil,
            note: text, display: text, checked: false, createdAt: .now
        )
    }

    static let pendingPrefix = "pending-"
}

extension ShoppingListItem {
    /// Optimistic placeholder that doesn't exist on the server yet.
    var isPending: Bool { id.hasPrefix(ShoppingItemDraft.pendingPrefix) }

    init(id: String, shoppingListId: String, quantity: Double?, note: String?, display: String?,
         checked: Bool, createdAt: Date?) {
        self.id = id
        self.shoppingListId = shoppingListId
        self.quantity = quantity
        self.note = note
        self.display = display
        self.checked = checked
        self.createdAt = createdAt
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
