import SwiftUI

/// One label group of unchecked items in a shopping list.
struct ShoppingSection: Identifiable, Hashable {
    /// The label id, or `ShoppingSection.noLabelID`.
    let id: String
    let label: MultiPurposeLabel?
    var items: [ShoppingListItem]

    static let noLabelID = "no-label"

    var title: String { label?.name ?? "No Label" }
}

/// Pure grouping and sorting rules for the shopping list screen (unit tested).
enum ShoppingListLayout {
    /// The label an item is filed under: its own label, else its food's label.
    static func label(of item: ShoppingListItem) -> MultiPurposeLabel? {
        item.label ?? item.food?.label
    }

    /// Unchecked items grouped by label.
    ///
    /// Sections follow the list's label order (`labelSettings.position`, as arranged in
    /// Mealie), labels without a setting come after them by name, "No Label" is last.
    /// `keepInPlace` holds ids of items that were just checked: they stay in their section
    /// for a moment so the check-off animation is visible before they move away.
    static func sections(
        for items: [ShoppingListItem],
        labelSettings: [ShoppingList.LabelSetting]? = nil,
        keepInPlace: Set<String> = []
    ) -> [ShoppingSection] {
        let open = items.filter { !$0.checked || keepInPlace.contains($0.id) }
        var groups: [String: ShoppingSection] = [:]
        for item in open {
            let label = label(of: item)
            let key = label?.id ?? ShoppingSection.noLabelID
            groups[key, default: ShoppingSection(id: key, label: label, items: [])].items.append(item)
        }

        var positions: [String: Int] = [:]
        for setting in labelSettings ?? [] {
            positions[setting.labelId] = setting.position ?? Int.max
        }

        return groups.values
            .map { section in
                var section = section
                section.items.sort(by: itemOrder)
                return section
            }
            .sorted { lhs, rhs in
                sectionOrder(lhs, rhs, positions: positions)
            }
    }

    /// Checked items, most recently checked first.
    static func checkedItems(_ items: [ShoppingListItem], excluding keepInPlace: Set<String> = []) -> [ShoppingListItem] {
        items
            .filter { $0.checked && !keepInPlace.contains($0.id) }
            .sorted { lhs, rhs in
                let left = lhs.updatedAt ?? .distantPast
                let right = rhs.updatedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.displayText.localizedStandardCompare(rhs.displayText) == .orderedAscending
            }
    }

    static func uncheckedCount(_ items: [ShoppingListItem]) -> Int {
        items.count(where: { !$0.checked })
    }

    /// Items in a section: Mealie's `position`, then oldest first (new items land at the
    /// bottom of their group), then alphabetically.
    static func itemOrder(_ lhs: ShoppingListItem, _ rhs: ShoppingListItem) -> Bool {
        let leftPosition = lhs.position ?? 0
        let rightPosition = rhs.position ?? 0
        if leftPosition != rightPosition { return leftPosition < rightPosition }
        let leftDate = lhs.createdAt ?? .distantFuture
        let rightDate = rhs.createdAt ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return lhs.displayText.localizedStandardCompare(rhs.displayText) == .orderedAscending
    }

    /// A list's label settings in section order: by position, then by name (what
    /// `sections(for:labelSettings:)` uses), for the "Reorder Sections" sheet.
    static func orderedLabelSettings(_ settings: [ShoppingList.LabelSetting]) -> [ShoppingList.LabelSetting] {
        settings.sorted { lhs, rhs in
            let left = lhs.position ?? Int.max
            let right = rhs.position ?? Int.max
            if left != right { return left < right }
            return (lhs.label?.name ?? "").localizedStandardCompare(rhs.label?.name ?? "") == .orderedAscending
        }
    }

    /// `settings` in their new order with consecutive positions (0, 1, 2, …).
    static func renumbered(_ settings: [ShoppingList.LabelSetting]) -> [ShoppingList.LabelSetting] {
        settings.enumerated().map { index, setting in
            var setting = setting
            setting.position = index
            return setting
        }
    }

    /// Body of `PUT …/lists/{id}/label-settings` for settings in their new order.
    static func labelSettingUpdates(_ settings: [ShoppingList.LabelSetting], listID: String) -> [ShoppingListLabelSettingUpdate] {
        renumbered(settings).map {
            ShoppingListLabelSettingUpdate(id: $0.id, shoppingListId: $0.shoppingListId ?? listID,
                                           labelId: $0.labelId, position: $0.position ?? 0)
        }
    }

    private static func sectionOrder(_ lhs: ShoppingSection, _ rhs: ShoppingSection, positions: [String: Int]) -> Bool {
        let leftIsNone = lhs.label == nil
        let rightIsNone = rhs.label == nil
        if leftIsNone != rightIsNone { return rightIsNone }
        let left = positions[lhs.id] ?? Int.max
        let right = positions[rhs.id] ?? Int.max
        if left != right { return left < right }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

// MARK: - Recipe references

extension ShoppingList {
    /// Recipe names by recipe id, for the "from <recipe>" caption on items.
    var recipeNamesByID: [String: String] {
        var names: [String: String] = [:]
        for reference in recipeReferences ?? [] {
            if let recipe = reference.recipe { names[reference.recipeId] = recipe.displayName }
        }
        return names
    }
}

extension ShoppingListItem {
    /// Recipe ids this item was added from (deduplicated, in order).
    var recipeIDs: [String] {
        var seen = Set<String>()
        return (recipeReferences ?? []).map(\.recipeId).filter { seen.insert($0).inserted }
    }
}

// MARK: - Label colour

extension MultiPurposeLabel {
    /// Mealie's default label colour; every seeded label has it, so it carries no meaning.
    static let defaultColorHex = "#959595"

    /// The label's colour when the user picked one (not Mealie's default grey).
    var customColor: Color? {
        guard let color, color.caseInsensitiveCompare(Self.defaultColorHex) != .orderedSame else { return nil }
        return Color(mealieHex: color)
    }
}

extension Color {
    /// `#RRGGBB` / `RRGGBB` / `#RRGGBBAA` from Mealie labels.
    init?(mealieHex: String) {
        var hex = mealieHex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
