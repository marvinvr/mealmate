import Foundation

/// Result of `POST /api/parser/ingredient(s)`.
struct ParsedIngredient: Codable, Hashable, Sendable {
    var input: String?
    var confidence: Confidence?
    var ingredient: RecipeIngredient

    /// 0...1 per part; `nil` when the parser does not report it.
    struct Confidence: Codable, Hashable, Sendable {
        var average: Double?
        var comment: Double?
        var name: Double?
        var unit: Double?
        var quantity: Double?
        var food: Double?
    }
}

struct IngredientParser: OpenStringEnum {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    static let nlp: Self = "nlp"
    static let brute: Self = "brute"
    /// Uses the server's AI provider; only when configured.
    static let openai: Self = "openai"
}

struct IngredientParseRequest: Codable, Hashable, Sendable {
    var parser: IngredientParser = .nlp
    var ingredient: String
}

struct IngredientsParseRequest: Codable, Hashable, Sendable {
    var parser: IngredientParser = .nlp
    var ingredients: [String]
}
