import Foundation

// Meal planner (household-scoped).
extension MealieService {
    /// `GET /api/households/mealplans?start_date=&end_date=` (inclusive), sorted by date.
    func mealPlan(from start: MealieDay, to end: MealieDay) async throws -> [MealPlanEntry] {
        try await fetchAllPages("/api/households/mealplans", query: [
            URLQueryItem(name: "start_date", value: start.description),
            URLQueryItem(name: "end_date", value: end.description),
            URLQueryItem(name: "orderBy", value: "date"),
            URLQueryItem(name: "orderDirection", value: "asc"),
        ])
    }

    /// `GET /api/households/mealplans/today`.
    func mealPlanToday() async throws -> [MealPlanEntry] {
        try await send(.get("/api/households/mealplans/today"), as: LossyArray<MealPlanEntry>.self).elements
    }

    /// `GET /api/households/mealplans/{id}`.
    func mealPlanEntry(id: Int) async throws -> MealPlanEntry {
        try await send(.get("/api/households/mealplans/\(id)"))
    }

    /// `POST /api/households/mealplans`.
    @discardableResult
    func createMealPlanEntry(_ entry: MealPlanEntryCreate) async throws -> MealPlanEntry {
        try await send(.json(.post, "/api/households/mealplans", body: entry))
    }

    /// `PUT /api/households/mealplans/{id}`.
    @discardableResult
    func updateMealPlanEntry(_ entry: MealPlanEntryUpdate) async throws -> MealPlanEntry {
        try await send(.json(.put, "/api/households/mealplans/\(entry.id)", body: entry))
    }

    /// `DELETE /api/households/mealplans/{id}`.
    func deleteMealPlanEntry(id: Int) async throws {
        try await perform(.delete("/api/households/mealplans/\(id)"))
    }

    /// `POST /api/households/mealplans/random`: CREATES an entry with a random
    /// recipe (respecting the household's meal plan rules) and returns it.
    /// For a "suggestion" UI, delete the entry again if the user rejects it.
    @discardableResult
    func createRandomMealPlanEntry(date: MealieDay, entryType: PlanEntryType = .dinner) async throws -> MealPlanEntry {
        try await send(.json(.post, "/api/households/mealplans/random", body: MealPlanRandomRequest(date: date, entryType: entryType)))
    }
}
