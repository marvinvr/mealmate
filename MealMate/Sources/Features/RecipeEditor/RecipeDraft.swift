import Foundation

/// The editor's form state: an editable copy of a recipe's basic fields.
///
/// Mapping rules (so editing never loses data):
/// - Saving sends a `RecipePatch` (`PATCH /api/recipes/{slug}`) with only the
///   fields that changed. Mealie merges it into the stored recipe, so nutrition,
///   settings, assets, extras, tools, ratings, ... are never touched.
/// - Ingredient, step and note lines remember the object they were loaded from.
///   While a line's text is unchanged the original object is sent back verbatim
///   (food/unit/quantity, `referenceId`, step `ingredientReferences`).
/// - Edited ingredient lines keep their `referenceId` (steps keep pointing at
///   them) and section title; their text is either parsed into
///   amount/unit/food (`parsesIngredients`) or stored as a plain note.
struct RecipeDraft: Equatable, Sendable {
    var name = ""
    var description = ""
    /// `recipeServings`; `nil` = not set (Mealie stores 0).
    var servings: Double?
    /// `recipeYieldQuantity`, e.g. 1 in "1 loaf".
    var yieldQuantity: Double?
    /// `recipeYield`, e.g. "loaf".
    var yieldText = ""
    var prepTime = ""
    /// Mealie's "Cook time" is `performTime` (the scraper writes it there).
    var cookTime = ""
    var totalTime = ""
    var ingredients: [IngredientLine] = []
    /// Split edited/new ingredient lines into amount, unit and food via the
    /// server's parser (needed for scaling and shopping lists).
    var parsesIngredients = false
    var steps: [StepLine] = []
    var notes: [NoteLine] = []
    var categories: [Organizer] = []
    var tags: [Organizer] = []
    var sourceURL = ""

    // MARK: Lines

    struct IngredientLine: Identifiable, Equatable, Sendable {
        let id: UUID
        var text: String
        /// Ingredient as loaded from the server (`nil` for new lines).
        var original: RecipeIngredient?
        /// Section header (Mealie's `title` on the first ingredient of a group).
        var sectionTitle: String?

        init(id: UUID = UUID(), text: String, original: RecipeIngredient? = nil, sectionTitle: String? = nil) {
            self.id = id
            self.text = text
            self.original = original
            self.sectionTitle = sectionTitle
        }

        init(_ ingredient: RecipeIngredient) {
            self.init(text: Self.editableText(for: ingredient), original: ingredient,
                      sectionTitle: ingredient.title.flatMap { $0.draftTrimmed.isEmpty ? nil : $0 })
        }

        /// The text shown in the editor for a stored ingredient.
        static func editableText(for ingredient: RecipeIngredient) -> String {
            ingredient.displayText.draftTrimmed
        }

        var trimmedText: String { text.draftTrimmed }

        /// True while the line still shows exactly what was loaded.
        var isUnchanged: Bool {
            guard let original else { return false }
            return trimmedText == Self.editableText(for: original)
        }
    }

    struct StepLine: Identifiable, Equatable, Sendable {
        let id: UUID
        var text: String
        var original: RecipeStep?

        init(id: UUID = UUID(), text: String, original: RecipeStep? = nil) {
            self.id = id
            self.text = text
            self.original = original
        }
    }

    struct NoteLine: Identifiable, Equatable, Sendable {
        let id: UUID
        var title: String
        var text: String
        var original: RecipeNote?

        init(id: UUID = UUID(), title: String = "", text: String = "", original: RecipeNote? = nil) {
            self.id = id
            self.title = title
            self.text = text
            self.original = original
        }

        var isEmpty: Bool { title.draftTrimmed.isEmpty && text.draftTrimmed.isEmpty }
    }

    // MARK: Init

    /// Empty draft for a new recipe.
    init() {}

    /// Draft showing `recipe`'s current values.
    init(recipe: Recipe) {
        name = recipe.name ?? ""
        description = recipe.description ?? ""
        servings = recipe.recipeServings.flatMap { $0 > 0 ? $0 : nil }
        yieldQuantity = recipe.recipeYieldQuantity.flatMap { $0 > 0 ? $0 : nil }
        yieldText = recipe.recipeYield ?? ""
        prepTime = recipe.prepTime ?? ""
        cookTime = Self.cookTime(of: recipe)
        totalTime = recipe.totalTime ?? ""
        ingredients = recipe.ingredients.map(IngredientLine.init)
        parsesIngredients = recipe.ingredients.contains { $0.food != nil || $0.unit != nil }
        steps = recipe.instructions.map { StepLine(text: $0.text, original: $0) }
        notes = recipe.noteList.map { NoteLine(title: $0.title, text: $0.text, original: $0) }
        categories = recipe.categories
        tags = recipe.tagList
        sourceURL = recipe.orgURL ?? ""
    }

    private static func cookTime(of recipe: Recipe) -> String {
        if let perform = recipe.performTime, !perform.draftTrimmed.isEmpty { return perform }
        return recipe.cookTime ?? ""
    }

    var trimmedName: String { name.draftTrimmed }

    /// Yield as one editable line, e.g. "1 loaf" or "Makes 12".
    var yieldLine: String {
        let quantity = yieldQuantity.map { $0.formatted(.number.precision(.fractionLength(0...2))) }
        return [quantity, yieldText.draftTrimmed.draftNilIfEmpty].compactMap { $0 }.joined(separator: " ")
    }

    /// Parses a typed yield line: a leading number becomes `yieldQuantity`, the rest `yieldText`.
    mutating func setYield(fromLine line: String) {
        let trimmed = line.draftTrimmed
        if let match = trimmed.firstMatch(of: /^(\d+(?:[.,]\d+)?)\s*(.*)$/),
           let quantity = Double(match.1.replacingOccurrences(of: ",", with: ".")), quantity > 0 {
            yieldQuantity = quantity
            yieldText = String(match.2)
        } else {
            yieldQuantity = nil
            yieldText = trimmed
        }
    }
    var canSave: Bool { !trimmedName.isEmpty }

    // MARK: Ingredient parsing

    /// Texts of new/edited ingredient lines that should go through the parser.
    var ingredientTextsToParse: [String] {
        guard parsesIngredients else { return [] }
        var seen = Set<String>()
        return ingredients
            .filter { !$0.isUnchanged && !$0.trimmedText.isEmpty }
            .map(\.trimmedText)
            .filter { seen.insert($0).inserted }
    }

    /// Turns a parser result into something safe to save: foods/units the server
    /// doesn't know yet (no `id`) are folded back into the note instead of being
    /// created as new foods.
    static func savableIngredient(fromParsed parsed: RecipeIngredient, text: String) -> RecipeIngredient {
        var result = parsed
        var noteParts: [String] = []
        if let unit = result.unit, unit.id == nil {
            noteParts.append(unit.name)
            result.unit = nil
        }
        if let food = result.food, food.id == nil {
            noteParts.append(food.name)
            result.food = nil
        }
        if let note = result.note?.draftTrimmed, !note.isEmpty { noteParts.append(note) }
        result.note = noteParts.filter { !$0.draftTrimmed.isEmpty }.joined(separator: " ")
        result.originalText = text
        if result.food == nil && result.unit == nil && (result.quantity ?? 0) == 0 {
            // Nothing structured recognised: keep the line exactly as typed.
            return freeTextIngredient(text)
        }
        result.display = text
        return result
    }

    static func freeTextIngredient(_ text: String) -> RecipeIngredient {
        RecipeIngredient(quantity: 0, unit: nil, food: nil, note: text, display: text, title: nil,
                         originalText: nil, referenceId: nil, referencedRecipe: nil, substitutions: nil)
    }

    // MARK: Output

    /// Ingredients to save. `parsed` maps line text → parser result (see
    /// `ingredientTextsToParse`); lines without a result are stored as plain text.
    func outputIngredients(parsed: [String: RecipeIngredient] = [:]) -> [RecipeIngredient] {
        ingredients.compactMap { line in
            let text = line.trimmedText
            if line.isUnchanged, var original = line.original {
                if original.title?.draftTrimmed.draftNilIfEmpty != line.sectionTitle {
                    original.title = line.sectionTitle
                }
                return original
            }
            guard !text.isEmpty else { return nil }
            var ingredient = parsed[text].map { Self.savableIngredient(fromParsed: $0, text: text) }
                ?? Self.freeTextIngredient(text)
            ingredient.title = line.sectionTitle
            ingredient.referenceId = line.original?.referenceId ?? UUID().uuidString.lowercased()
            ingredient.substitutions = line.original?.substitutions
            return ingredient
        }
    }

    var outputSteps: [RecipeStep] {
        steps.compactMap { line in
            let text = line.text.draftTrimmed
            guard !text.isEmpty else { return nil }
            if var original = line.original {
                if original.text.draftTrimmed != text { original.text = text }
                return original
            }
            return RecipeStep(title: "", summary: "", text: text)
        }
    }

    var outputNotes: [RecipeNote] {
        notes.compactMap { line in
            guard !line.isEmpty else { return nil }
            let title = line.title.draftTrimmed
            let text = line.text.draftTrimmed
            if var original = line.original {
                if original.title.draftTrimmed != title { original.title = title }
                if original.text.draftTrimmed != text { original.text = text }
                return original
            }
            return RecipeNote(title: title, text: text, referenceId: UUID().uuidString.lowercased())
        }
    }

    /// The fields that differ from `original` (all fields when `original` is
    /// `nil`, i.e. a freshly created recipe whose server defaults are replaced).
    func patch(against original: Recipe?, parsedIngredients: [String: RecipeIngredient] = [:]) -> RecipePatch {
        var patch = RecipePatch()
        let base = original.map(RecipeDraft.init(recipe:))

        if let original {
            if trimmedName != (original.name ?? "").draftTrimmed { patch.name = trimmedName }
        } else {
            patch.name = trimmedName
        }
        if base == nil || description.draftTrimmed != base!.description.draftTrimmed {
            patch.description = .some(description.draftTrimmed.draftNilIfEmpty)
        }
        if base == nil || servings != base!.servings { patch.recipeServings = servings ?? 0 }
        if base == nil || yieldQuantity != base!.yieldQuantity { patch.recipeYieldQuantity = yieldQuantity ?? 0 }
        if base == nil || yieldText.draftTrimmed != base!.yieldText.draftTrimmed {
            patch.recipeYield = .some(yieldText.draftTrimmed.draftNilIfEmpty)
        }
        if base == nil || prepTime.draftTrimmed != base!.prepTime.draftTrimmed { patch.prepTime = .some(prepTime.draftTrimmed.draftNilIfEmpty) }
        if base == nil || cookTime.draftTrimmed != base!.cookTime.draftTrimmed { patch.performTime = .some(cookTime.draftTrimmed.draftNilIfEmpty) }
        if base == nil || totalTime.draftTrimmed != base!.totalTime.draftTrimmed { patch.totalTime = .some(totalTime.draftTrimmed.draftNilIfEmpty) }

        let ingredients = outputIngredients(parsed: parsedIngredients)
        if original == nil || ingredients != original!.ingredients { patch.recipeIngredient = ingredients }
        let steps = outputSteps
        if original == nil || steps != original!.instructions { patch.recipeInstructions = steps }
        let notes = outputNotes
        if original == nil || notes != original!.noteList { patch.notes = notes }

        if original == nil || categories.map(\.stableID) != original!.categories.map(\.stableID) {
            patch.recipeCategory = categories
        }
        if original == nil || tags.map(\.stableID) != original!.tagList.map(\.stableID) {
            patch.tags = tags
        }
        if base == nil || sourceURL.draftTrimmed != base!.sourceURL.draftTrimmed {
            patch.orgURL = .some(sourceURL.draftTrimmed.draftNilIfEmpty)
        }
        return patch
    }
}

// MARK: - Patch

/// Body of `PATCH /api/recipes/{slug}`: only the set fields are sent.
/// Double optionals: `.some(nil)` sends an explicit `null` (clears the field).
struct RecipePatch: Encodable, Equatable, Sendable {
    var name: String?
    var description: String??
    var recipeServings: Double?
    var recipeYieldQuantity: Double?
    var recipeYield: String??
    var prepTime: String??
    var performTime: String??
    var totalTime: String??
    var recipeIngredient: [RecipeIngredient]?
    var recipeInstructions: [RecipeStep]?
    var notes: [RecipeNote]?
    var recipeCategory: [Organizer]?
    var tags: [Organizer]?
    var orgURL: String??

    var isEmpty: Bool { self == RecipePatch() }

    /// Keys this patch will send (for tests and logging).
    var fieldNames: [String] {
        var names: [String] = []
        if name != nil { names.append("name") }
        if description != nil { names.append("description") }
        if recipeServings != nil { names.append("recipeServings") }
        if recipeYieldQuantity != nil { names.append("recipeYieldQuantity") }
        if recipeYield != nil { names.append("recipeYield") }
        if prepTime != nil { names.append("prepTime") }
        if performTime != nil { names.append("performTime") }
        if totalTime != nil { names.append("totalTime") }
        if recipeIngredient != nil { names.append("recipeIngredient") }
        if recipeInstructions != nil { names.append("recipeInstructions") }
        if notes != nil { names.append("notes") }
        if recipeCategory != nil { names.append("recipeCategory") }
        if tags != nil { names.append("tags") }
        if orgURL != nil { names.append("orgURL") }
        return names
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, recipeServings, recipeYieldQuantity, recipeYield, prepTime, performTime,
             totalTime, recipeIngredient, recipeInstructions, notes, recipeCategory, tags, orgURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        if let description { try container.encode(description, forKey: .description) }
        try container.encodeIfPresent(recipeServings, forKey: .recipeServings)
        try container.encodeIfPresent(recipeYieldQuantity, forKey: .recipeYieldQuantity)
        if let recipeYield { try container.encode(recipeYield, forKey: .recipeYield) }
        if let prepTime { try container.encode(prepTime, forKey: .prepTime) }
        if let performTime { try container.encode(performTime, forKey: .performTime) }
        if let totalTime { try container.encode(totalTime, forKey: .totalTime) }
        try container.encodeIfPresent(recipeIngredient, forKey: .recipeIngredient)
        try container.encodeIfPresent(recipeInstructions, forKey: .recipeInstructions)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(recipeCategory, forKey: .recipeCategory)
        try container.encodeIfPresent(tags, forKey: .tags)
        if let orgURL { try container.encode(orgURL, forKey: .orgURL) }
    }

    /// `recipe` with this patch applied locally (mirrors the server's merge).
    func applied(to recipe: Recipe) -> Recipe {
        var result = recipe
        if let name { result.name = name }
        if let description { result.description = description }
        if let recipeServings { result.recipeServings = recipeServings }
        if let recipeYieldQuantity { result.recipeYieldQuantity = recipeYieldQuantity }
        if let recipeYield { result.recipeYield = recipeYield }
        if let prepTime { result.prepTime = prepTime }
        if let performTime { result.performTime = performTime }
        if let totalTime { result.totalTime = totalTime }
        if let recipeIngredient { result.recipeIngredient = recipeIngredient }
        if let recipeInstructions { result.recipeInstructions = recipeInstructions }
        if let notes { result.notes = notes }
        if let recipeCategory { result.recipeCategory = recipeCategory }
        if let tags { result.tags = tags }
        if let orgURL { result.orgURL = orgURL }
        return result
    }
}

// MARK: - Helpers

extension String {
    fileprivate var draftTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var draftNilIfEmpty: String? { isEmpty ? nil : self }
}
