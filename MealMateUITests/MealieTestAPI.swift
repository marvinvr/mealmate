import Foundation
import XCTest

/// Minimal Mealie client for UI-test setup/teardown: creates and deletes "MealMate Test …"
/// data only. Uses untyped JSON on purpose (independent of the app's models).
/// Calls are synchronous (see `send`).
struct MealieTestAPI {
    let baseURL: URL
    let token: String

    struct Failure: Error, CustomStringConvertible {
        let status: Int
        let path: String
        var description: String { "HTTP \(status) for \(path)" }
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], json body: Any? = nil) throws -> Any? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        // Synchronous on purpose: async UI tests deadlock when XCTest interrupts a failing
        // test and runs tearDown on the main thread. Completions arrive off the main thread.
        var data = Data(), status = 0, transportError: Error?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { body, response, error in
            data = body ?? Data()
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            transportError = error
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + 60) == .timedOut { throw Failure(status: 0, path: path) }
        if let transportError { throw transportError }
        guard (200..<300).contains(status) else { throw Failure(status: status, path: path) }
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func object(_ path: String, query: [URLQueryItem] = []) throws -> [String: Any] {
        try send("GET", path, query: query) as? [String: Any] ?? [:]
    }

    func items(_ path: String, query: [URLQueryItem] = []) throws -> [[String: Any]] {
        let page = try object(path, query: query + [URLQueryItem(name: "perPage", value: "500")])
        return page["items"] as? [[String: Any]] ?? []
    }

    // MARK: Account

    func currentUser() throws -> [String: Any] { try object("/api/users/self") }

    /// Names of the user's API tokens (never their values).
    func apiTokenNames() throws -> [String] {
        (try currentUser()["tokens"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.sorted()
    }

    func appInfo() throws -> [String: Any] { try object("/api/app/about") }

    // MARK: Recipes

    /// Creates a recipe and fills it with `fields` (merged into the full recipe). Returns the slug.
    func createRecipe(named name: String, fields: [String: Any] = [:]) throws -> String {
        precondition(name.hasPrefix("MealMate Test"))
        guard let slug = try send("POST", "/api/recipes", json: ["name": name]) as? String else {
            throw Failure(status: 0, path: "/api/recipes")
        }
        if !fields.isEmpty {
            var recipe = try object("/api/recipes/\(slug)")
            recipe.merge(fields) { _, new in new }
            try send("PUT", "/api/recipes/\(slug)", json: recipe)
        }
        return slug
    }

    func recipe(_ slug: String) throws -> [String: Any] { try object("/api/recipes/\(slug)") }

    func recipes(named prefix: String) throws -> [[String: Any]] {
        try items("/api/recipes", query: [URLQueryItem(name: "search", value: prefix)])
            .filter { ($0["name"] as? String)?.hasPrefix(prefix) == true }
    }

    func deleteRecipe(_ slug: String) {
        _ = try? send("DELETE", "/api/recipes/\(slug)")
    }

    /// Deletes every recipe whose name starts with `prefix` (must be a "MealMate Test" name).
    func deleteRecipes(named prefix: String) {
        precondition(prefix.hasPrefix("MealMate Test"))
        for recipe in (try? recipes(named: prefix)) ?? [] {
            if let slug = recipe["slug"] as? String { deleteRecipe(slug) }
        }
    }

    // MARK: Shopping

    func shoppingLists(named prefix: String) throws -> [[String: Any]] {
        try items("/api/households/shopping/lists").filter { ($0["name"] as? String)?.hasPrefix(prefix) == true }
    }

    func shoppingList(_ id: String) throws -> [String: Any] {
        try object("/api/households/shopping/lists/\(id)")
    }

    func deleteShoppingLists(named prefix: String) {
        precondition(prefix.hasPrefix("MealMate Test"))
        for list in (try? shoppingLists(named: prefix)) ?? [] {
            if let id = list["id"] as? String { _ = try? send("DELETE", "/api/households/shopping/lists/\(id)") }
        }
    }

    // MARK: Meal plan

    func mealPlanEntries(from start: String, to end: String) throws -> [[String: Any]] {
        try items("/api/households/mealplans", query: [
            URLQueryItem(name: "start_date", value: start), URLQueryItem(name: "end_date", value: end),
        ])
    }

    /// Deletes entries in the range whose title (or recipe name) starts with `prefix`.
    func deleteMealPlanEntries(named prefix: String, from start: String, to end: String) {
        precondition(prefix.hasPrefix("MealMate Test"))
        for entry in (try? mealPlanEntries(from: start, to: end)) ?? [] {
            let title = entry["title"] as? String ?? ""
            let recipeName = (entry["recipe"] as? [String: Any])?["name"] as? String ?? ""
            guard title.hasPrefix(prefix) || recipeName.hasPrefix(prefix), let id = entry["id"] else { continue }
            _ = try? send("DELETE", "/api/households/mealplans/\(id)")
        }
    }

    // MARK: Organizers

    /// Deletes the given categories/tags/tools (created by a test import).
    func deleteOrganizers(_ kind: String, ids: [String]) {
        for id in ids { _ = try? send("DELETE", "/api/organizers/\(kind)/\(id)") }
    }

    func organizerIDs(_ kind: String) throws -> Set<String> {
        Set(try items("/api/organizers/\(kind)").compactMap { $0["id"] as? String })
    }
}
