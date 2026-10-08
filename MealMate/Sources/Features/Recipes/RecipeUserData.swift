import Foundation
import Observation

/// The signed-in user's favorites and own ratings, shared by every recipe screen so a heart
/// toggled on the detail screen shows on the grid immediately.
///
/// Cached-first (`ResponseCache` key `recipes.userRatings`), refreshed at most every minute
/// unless forced. Writes are optimistic and roll back on failure. Scoped to the server: a
/// different `MealieService` (sign-out / other server) starts empty.
@MainActor
@Observable
final class RecipeUserData {
    static let shared = RecipeUserData()

    private(set) var favoriteIDs: Set<String> = []
    /// recipe ID → the user's own rating (1–5).
    private(set) var ratings: [String: Double] = [:]
    private(set) var hasLoaded = false

    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private static let cacheKey = "recipes.userRatings"

    func isFavorite(_ recipeID: String) -> Bool { favoriteIDs.contains(recipeID) }
    func rating(for recipeID: String) -> Double? { ratings[recipeID] }

    /// Loads cached state, then refreshes from the server (at most once a minute unless `force`).
    func load(_ mealie: MealieService, force: Bool = false) async {
        resetIfNeeded(for: mealie)
        if !hasLoaded, let cached = await mealie.cached([UserRating].self, key: Self.cacheKey) {
            apply(cached)
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        if let loadTask { return await loadTask.value }
        let task = Task {
            if let fresh = try? await mealie.myRatings() {
                apply(fresh)
                lastRefresh = Date()
                await mealie.storeInCache(fresh, key: Self.cacheKey)
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Optimistically toggles the favorite; rolls back and rethrows on failure.
    func setFavorite(_ isFavorite: Bool, recipeID: String, slug: String, mealie: MealieService, userID: String?) async throws {
        resetIfNeeded(for: mealie)
        let previous = favoriteIDs
        if isFavorite { favoriteIDs.insert(recipeID) } else { favoriteIDs.remove(recipeID) }
        do {
            let user = try await resolveUserID(mealie, userID)
            try await mealie.setFavorite(isFavorite, slug: slug, userID: user)
            await persist(mealie)
        } catch {
            favoriteIDs = previous
            throw MealieError.wrap(error)
        }
    }

    /// Optimistically sets (or clears with `nil`) the user's rating.
    func setRating(_ rating: Double?, recipeID: String, slug: String, mealie: MealieService, userID: String?) async throws {
        resetIfNeeded(for: mealie)
        let previous = ratings[recipeID]
        ratings[recipeID] = rating
        do {
            let user = try await resolveUserID(mealie, userID)
            try await mealie.setRating(rating, slug: slug, userID: user)
            await persist(mealie)
        } catch {
            ratings[recipeID] = previous
            throw MealieError.wrap(error)
        }
    }

    // MARK: Private

    private func apply(_ list: [UserRating]) {
        favoriteIDs = Set(list.filter { $0.isFavorite == true }.map(\.recipeId))
        var ratings: [String: Double] = [:]
        for entry in list {
            if let rating = entry.rating, rating > 0 { ratings[entry.recipeId] = rating }
        }
        self.ratings = ratings
        hasLoaded = true
    }

    private func persist(_ mealie: MealieService) async {
        let ids = favoriteIDs.union(ratings.keys)
        let list = ids.map { UserRating(recipeId: $0, rating: ratings[$0], isFavorite: favoriteIDs.contains($0)) }
        await mealie.storeInCache(list, key: Self.cacheKey)
    }

    private func resolveUserID(_ mealie: MealieService, _ given: String?) async throws -> String {
        if let given { userID = given; return given }
        if let userID { return userID }
        let user = try await mealie.currentUser()
        userID = user.id
        return user.id
    }

    private func resetIfNeeded(for mealie: MealieService) {
        let newScope = mealie.cacheScope + "|" + String((mealie.token ?? "").hashValue)
        guard scope != newScope else { return }
        scope = newScope
        favoriteIDs = []
        ratings = [:]
        hasLoaded = false
        lastRefresh = nil
        userID = nil
    }
}
