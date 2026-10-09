import Foundation

/// Quantity formatting and ingredient display strings, with servings scaling.
///
/// Parsed ingredients (with a food or unit) are rebuilt from their parts so the quantity
/// can be scaled: `quantity × scale`, unit (plural / abbreviation as configured on the
/// unit), food (plural when it's counted without a unit), note. Unparsed ingredients
/// (free text in `note`, no food and no unit) are shown as entered and never scaled,
/// because their quantity isn't reliable.
enum IngredientFormatting {
    /// Unicode vulgar fractions that read well in a kitchen.
    private static let fractions: [(value: Double, glyph: String)] = [
        (1.0 / 8, "⅛"), (1.0 / 6, "⅙"), (1.0 / 5, "⅕"), (1.0 / 4, "¼"), (1.0 / 3, "⅓"),
        (3.0 / 8, "⅜"), (2.0 / 5, "⅖"), (1.0 / 2, "½"), (3.0 / 5, "⅗"), (5.0 / 8, "⅝"),
        (2.0 / 3, "⅔"), (3.0 / 4, "¾"), (4.0 / 5, "⅘"), (5.0 / 6, "⅚"), (7.0 / 8, "⅞"),
    ]

    /// "1½", "⅓", "2", "0.15", "250". Fractions only when `useFractions` and the value
    /// is close (±0.012) to a common fraction; large amounts are rounded to whole numbers.
    static func quantity(_ value: Double, useFractions: Bool = true, locale: Locale = .current) -> String {
        guard value.isFinite, value > 0 else { return "" }
        if value >= 20 {
            return Int(value.rounded()).formatted(.number.grouping(.never).locale(locale))
        }
        let whole = value.rounded(.down)
        let remainder = value - whole
        if remainder < 0.02 {
            return Int(whole).formatted(.number.grouping(.never).locale(locale))
        }
        if remainder > 0.98 {
            return Int(whole + 1).formatted(.number.grouping(.never).locale(locale))
        }
        if useFractions, let fraction = fractions.first(where: { abs($0.value - remainder) < 0.012 }) {
            return whole > 0 ? "\(Int(whole))\(fraction.glyph)" : fraction.glyph
        }
        let digits = value < 1 ? 2 : 1
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never).locale(locale))
    }

    /// Display parts of an ingredient line at `scale`.
    static func parts(for ingredient: RecipeIngredient, scale: Double = 1) -> IngredientDisplay {
        let note = ingredient.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard isParsed(ingredient) else {
            // Free text: as entered (server display, original text, or the note).
            let text = ingredient.display?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? ingredient.originalText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? [ingredient.quantity.flatMap { $0 > 0 ? quantity($0) : nil }, note]
                    .compactMap { $0 }.joined(separator: " ")
            return IngredientDisplay(amount: nil, food: nil, note: text.nilIfEmpty, isScaled: false)
        }

        let amountValue = ingredient.quantity.map { $0 * scale }
        let hasAmount = (amountValue ?? 0) > 0
        let plural = hasAmount && (amountValue ?? 0) > 1.0 + 0.0001
        let useFractions = ingredient.unit?.fraction ?? true

        var amountParts: [String] = []
        if hasAmount, let amountValue {
            amountParts.append(quantity(amountValue, useFractions: useFractions))
        }
        if let unit = ingredient.unit {
            amountParts.append(unitName(unit, plural: plural))
        }
        let amount = amountParts.filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty

        var foodName = ingredient.food?.name.nilIfEmpty ?? ingredient.linkedRecipe?.displayName
        if plural, ingredient.unit == nil, let pluralName = ingredient.food?.pluralName?.nilIfEmpty {
            foodName = pluralName
        }
        return IngredientDisplay(amount: amount, food: foodName, note: note, isScaled: hasAmount && scale != 1)
    }

    /// Single-line text, e.g. "1½ cups flour, sifted" → "1½ cups flour sifted".
    static func text(for ingredient: RecipeIngredient, scale: Double = 1) -> String {
        parts(for: ingredient, scale: scale).text
    }

    /// Parsed = the server knows the food, the unit or the linked recipe (so the quantity
    /// is meaningful).
    static func isParsed(_ ingredient: RecipeIngredient) -> Bool {
        ingredient.food != nil || ingredient.unit != nil || ingredient.linkedRecipe != nil
    }

    /// "or Pecorino, a little less" lines for an ingredient's substitutes.
    static func substituteText(_ substitute: RecipeIngredient.Substitute) -> String {
        guard let note = substitute.note else { return "or \(substitute.name)" }
        return "or \(substitute.name), \(note)"
    }

    private static func unitName(_ unit: IngredientUnit, plural: Bool) -> String {
        if unit.useAbbreviation == true {
            if plural, let abbreviation = unit.pluralAbbreviation?.nilIfEmpty { return abbreviation }
            if let abbreviation = unit.abbreviation?.nilIfEmpty { return abbreviation }
        }
        if plural, let pluralName = unit.pluralName?.nilIfEmpty { return pluralName }
        return unit.name
    }

    // MARK: Servings

    /// Scale factor for `servings` when the recipe is written for `baseServings`.
    static func scale(servings: Double, baseServings: Double?) -> Double {
        guard let baseServings, baseServings > 0, servings > 0 else { return 1 }
        return servings / baseServings
    }
}

/// An ingredient line split for typesetting: **amount** food *note*.
struct IngredientDisplay: Hashable, Sendable {
    /// Quantity and unit ("1½ cups"); `nil` for free text.
    var amount: String?
    var food: String?
    /// Note, or the whole line for free text.
    var note: String?
    /// The amount differs from the recipe because of servings scaling.
    var isScaled: Bool

    var text: String {
        [amount, food, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension String {
    /// `nil` when empty.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Sections

/// Ingredients or steps grouped under their section titles (Mealie marks the first item of
/// a section with `title`).
struct RecipeSection<Item: Hashable>: Hashable, Identifiable {
    var id: Int
    var title: String?
    /// Items with their index in the flat recipe list (stable ID for check-off).
    var items: [IndexedItem]

    struct IndexedItem: Hashable, Identifiable {
        var index: Int
        var item: Item
        var id: Int { index }
    }
}

enum RecipeSections {
    static func ingredients(_ ingredients: [RecipeIngredient]) -> [RecipeSection<RecipeIngredient>] {
        group(ingredients, title: { $0.title })
    }

    static func steps(_ steps: [RecipeStep]) -> [RecipeSection<RecipeStep>] {
        group(steps, title: { $0.title })
    }

    private static func group<Item: Hashable>(_ items: [Item], title: (Item) -> String?) -> [RecipeSection<Item>] {
        var sections: [RecipeSection<Item>] = []
        for (index, item) in items.enumerated() {
            let sectionTitle = title(item)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if sections.isEmpty || sectionTitle != nil {
                sections.append(RecipeSection(id: sections.count, title: sectionTitle, items: []))
            }
            sections[sections.count - 1].items.append(.init(index: index, item: item))
        }
        return sections
    }
}
