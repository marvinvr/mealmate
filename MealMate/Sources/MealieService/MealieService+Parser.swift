import Foundation

// Ingredient parsing (free text → quantity/unit/food).
extension MealieService {
    /// `POST /api/parser/ingredient`.
    func parseIngredient(_ text: String, parser: IngredientParser = .nlp) async throws -> ParsedIngredient {
        try await send(.json(.post, "/api/parser/ingredient", body: IngredientParseRequest(parser: parser, ingredient: text)))
    }

    /// `POST /api/parser/ingredients`.
    func parseIngredients(_ lines: [String], parser: IngredientParser = .nlp) async throws -> [ParsedIngredient] {
        try await send(.json(.post, "/api/parser/ingredients", body: IngredientsParseRequest(parser: parser, ingredients: lines)))
    }
}
