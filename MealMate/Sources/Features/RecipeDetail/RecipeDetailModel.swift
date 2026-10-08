import Foundation
import Observation

/// Recipe detail: the recipe (cached-first), comments, timeline, household recipe actions,
/// and the writes the screen offers (made it, comments, actions).
@MainActor
@Observable
final class RecipeDetailModel {
    /// Changes when the recipe is renamed in the editor.
    private(set) var slug: String

    private(set) var recipe: Recipe?
    private(set) var loadError: String?
    private(set) var refreshError: String?
    private(set) var isLoading = false
    private(set) var comments: [RecipeComment] = []
    private(set) var timeline: [TimelineEvent] = []
    private(set) var hasLoadedTimeline = false
    private(set) var actions: [RecipeAction] = []
    /// Action currently being triggered (for a progress indicator).
    private(set) var runningActionID: String?

    @ObservationIgnored let mealie: MealieService
    @ObservationIgnored let cooking: CookingSessionStore

    init(slug: String, mealie: MealieService, cooking: CookingSessionStore = .shared) {
        self.slug = slug
        self.mealie = mealie
        self.cooking = cooking
    }

    private var cacheKey: String { "recipes.detail.\(slug)" }

    // MARK: Servings & check-off

    /// The recipe's own servings (falls back to the yield quantity).
    var baseServings: Double? {
        guard let recipe else { return nil }
        if let servings = recipe.recipeServings, servings > 0 { return servings }
        if let quantity = recipe.recipeYieldQuantity, quantity > 0 { return quantity }
        return nil
    }

    var session: CookingSessionStore.Session {
        recipe.map { cooking.session(for: $0.id) } ?? .init()
    }

    /// Chosen servings (or the recipe's own).
    var servings: Double {
        session.servings ?? baseServings ?? 1
    }

    /// Multiplier applied to parsed quantities.
    var scale: Double {
        guard baseServings != nil else { return session.servings ?? 1 }
        return IngredientFormatting.scale(servings: servings, baseServings: baseServings)
    }

    var isScaled: Bool { abs(scale - 1) > 0.0001 }

    func setServings(_ value: Double) {
        guard let recipe else { return }
        let base = baseServings ?? 1
        cooking.update(recipe.id) { $0.servings = abs(value - base) < 0.0001 ? nil : max(value, 0.5) }
    }

    func isChecked(_ index: Int) -> Bool { session.checkedIngredients.contains(index) }

    func toggleIngredient(_ index: Int) {
        guard let recipe else { return }
        cooking.toggleIngredient(index, recipeID: recipe.id)
    }

    func resetCooking() {
        guard let recipe else { return }
        cooking.reset(recipe.id)
    }

    var checkedCount: Int { session.checkedIngredients.count }

    /// Ingredients a step references (Mealie `ingredientReferences`), in recipe order.
    func referencedIngredients(for step: RecipeStep) -> [(index: Int, ingredient: RecipeIngredient)] {
        guard let recipe else { return [] }
        let ids = Set((step.ingredientReferences ?? []).compactMap(\.referenceId))
        guard !ids.isEmpty else { return [] }
        return recipe.ingredients.enumerated().compactMap { index, ingredient in
            guard let id = ingredient.referenceId, ids.contains(id) else { return nil }
            return (index, ingredient)
        }
    }

    // MARK: Loading

    func load() async {
        if recipe == nil, let cached = await mealie.cached(Recipe.self, key: cacheKey) {
            recipe = cached
            comments = cached.comments ?? []
        }
        if recipe == nil, let cachedActions = await mealie.cached([RecipeAction].self, key: "recipes.actions") {
            actions = cachedActions
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await mealie.recipe(slug: slug)
            recipe = fresh
            loadError = nil
            refreshError = nil
            if let embedded = fresh.comments { comments = embedded }
            await mealie.storeInCache(fresh, key: cacheKey)
        } catch {
            let error = MealieError.wrap(error)
            guard !error.isCancelled else { return }
            if recipe == nil { loadError = error.errorDescription } else { refreshError = error.errorDescription }
            return
        }
        async let comments: Void = loadComments()
        async let timeline: Void = loadTimeline()
        async let actions: Void = loadActions()
        _ = await (comments, timeline, actions)
    }

    func loadComments() async {
        if let fresh = try? await mealie.comments(slug: slug) {
            comments = fresh.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    func loadTimeline() async {
        guard let recipe else { return }
        if let page = try? await mealie.timelineEvents(recipeID: recipe.id) {
            timeline = page.items
        }
        hasLoadedTimeline = true
    }

    func loadActions() async {
        if let fresh = try? await mealie.recipeActions() {
            actions = fresh
            await mealie.storeInCache(fresh, key: "recipes.actions")
        }
    }

    /// Shows a recipe saved elsewhere (editor) without a round trip.
    func apply(_ updated: Recipe) {
        slug = updated.slug
        recipe = updated
        Task { await mealie.storeInCache(updated, key: cacheKey) }
    }

    // MARK: Writes

    /// "I made this": sets last made and adds a timeline event.
    func markMade(at date: Date, note: String, userName: String?, userID: String?) async throws {
        guard let recipe else { return }
        do {
            let updated = try await mealie.markLastMade(slug: recipe.slug, at: date)
            self.recipe?.lastMade = updated.lastMade ?? date
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = userName.map { "\($0) made this" } ?? "Made this"
            let event = TimelineEventCreate(recipeId: recipe.id, subject: subject, eventType: .comment,
                                            eventMessage: trimmed.isEmpty ? nil : trimmed, timestamp: date, userId: userID)
            let created = try await mealie.createTimelineEvent(event)
            timeline.insert(created, at: 0)
            timeline.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            if let current = self.recipe { await mealie.storeInCache(current, key: cacheKey) }
        } catch {
            throw MealieError.wrap(error)
        }
    }

    func addComment(_ text: String) async throws {
        guard let recipe else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let comment = try await mealie.addComment(recipeID: recipe.id, text: trimmed)
            comments.insert(comment, at: 0)
            await loadComments()
        } catch {
            throw MealieError.wrap(error)
        }
    }

    /// Optimistic delete with rollback.
    func deleteComment(_ comment: RecipeComment) async throws {
        let previous = comments
        comments.removeAll { $0.id == comment.id }
        do {
            try await mealie.deleteComment(id: comment.id)
        } catch {
            comments = previous
            throw MealieError.wrap(error)
        }
    }

    func deleteTimelineEvent(_ event: TimelineEvent) async throws {
        let previous = timeline
        timeline.removeAll { $0.id == event.id }
        do {
            try await mealie.deleteTimelineEvent(id: event.id)
        } catch {
            timeline = previous
            throw MealieError.wrap(error)
        }
    }

    /// Triggers a `post` action server-side with the current servings scale.
    func trigger(_ action: RecipeAction) async throws {
        guard let recipe else { return }
        runningActionID = action.id
        defer { runningActionID = nil }
        do {
            try await mealie.triggerRecipeAction(id: action.id, slug: recipe.slug, scale: scale)
        } catch {
            throw MealieError.wrap(error)
        }
    }

    /// URL for a `link` action with Mealie's placeholders filled in.
    func linkURL(for action: RecipeAction, recipeURL: URL?) -> URL? {
        guard let recipe else { return nil }
        return RecipeActionLink.url(template: action.url, recipe: recipe, recipeURL: recipeURL, scale: scale, servings: servings)
    }
}

/// Fills the placeholders of a `link` recipe action, like the Mealie web UI does
/// (`${url}`, `${id}`, `${slug}`, `${name}`, `${scale}`/`${recipe_scale}`, `${servings}`).
enum RecipeActionLink {
    static func url(template: String, recipe: Recipe, recipeURL: URL?, scale: Double, servings: Double) -> URL? {
        func encoded(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? value
        }
        let number: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) }
        let replacements: [String: String] = [
            "url": recipeURL?.absoluteString ?? "",
            "id": recipe.id,
            "slug": recipe.slug,
            "name": recipe.displayName,
            "scale": number(scale),
            "recipe_scale": number(scale),
            "servings": number(servings),
        ]
        var result = template
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: "${\(key)}", with: encoded(value))
        }
        return URL(string: result)
    }
}
