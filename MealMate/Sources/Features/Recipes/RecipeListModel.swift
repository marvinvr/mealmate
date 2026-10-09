import Foundation
import Observation

/// State of one recipe list (Recipes tab, favorites, a cookbook, a category/tag/tool):
/// search, sort, filters, paging, cached first page.
@MainActor
@Observable
final class RecipeListModel {
    let preset: RecipeCollectionPreset

    var search = ""
    var sort: RecipeSort {
        didSet { if sort != oldValue { seed = UUID().uuidString } }
    }
    var filters = RecipeFilters()

    private(set) var items: [RecipeSummary] = []
    private(set) var total: Int?
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    /// Set once the first server response (or cache) arrived.
    private(set) var hasLoaded = false
    /// First load failed and there's nothing to show.
    private(set) var loadError: String?
    /// A refresh failed while cached content is shown.
    private(set) var refreshError: String?

    @ObservationIgnored private let mealie: MealieService
    @ObservationIgnored private let userData: RecipeUserData
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var seed = UUID().uuidString
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastSearch = ""
    static let perPage = 30

    init(preset: RecipeCollectionPreset, sort: RecipeSort = .recentlyAdded, mealie: MealieService, userData: RecipeUserData = .shared) {
        self.preset = preset
        self.sort = sort
        self.mealie = mealie
        self.userData = userData
    }

    /// Everything that changes the result set; drive `.task(id:)` with it.
    struct Key: Hashable {
        var search: String
        var sort: RecipeSort
        var filters: RecipeFilters
        var favorites: Set<String>?
    }

    var key: Key {
        let needsFavorites = preset == .favorites || filters.favoritesOnly
        return Key(search: search.trimmingCharacters(in: .whitespacesAndNewlines), sort: sort, filters: filters,
                   favorites: needsFavorites ? userData.favoriteIDs : nil)
    }

    var isSearching: Bool { !key.search.isEmpty }
    var isFiltered: Bool { !filters.isEmpty }

    private var cacheKey: String? {
        guard !isSearching, filters.isEmpty, sort != .random, preset != .favorites else { return nil }
        return "recipes.list.\(preset.cacheKey).\(sort.rawValue)"
    }

    // MARK: Loading

    /// Reloads page 1 for the current key. Debounces search typing.
    func keyChanged() async {
        let search = key.search
        if hasLoaded, search != lastSearch, !search.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
        }
        lastSearch = search
        await reload()
    }

    func reload() async {
        generation += 1
        let generation = self.generation
        loadError = nil

        if preset == .favorites || filters.favoritesOnly {
            await userData.load(mealie)
        }

        if !hasLoaded, let cacheKey, let cached = await mealie.cached([RecipeSummary].self, key: cacheKey), items.isEmpty {
            items = cached
            hasLoaded = true
        }

        guard let query = makeQuery(page: 1) else {
            items = []
            total = 0
            hasMore = false
            hasLoaded = true
            return
        }

        isLoading = true
        defer { if generation == self.generation { isLoading = false } }
        do {
            let result = try await mealie.recipes(query)
            guard generation == self.generation else { return }
            items = result.items
            total = result.total
            page = 1
            hasMore = result.hasMore && !result.items.isEmpty
            hasLoaded = true
            refreshError = nil
            if let cacheKey { await mealie.storeInCache(result.items, key: cacheKey) }
        } catch {
            let error = MealieError.wrap(error)
            guard !error.isCancelled, generation == self.generation else { return }
            if items.isEmpty || isSearching || isFiltered {
                if isSearching || isFiltered { items = [] }
                loadError = error.errorDescription
            } else {
                refreshError = error.errorDescription
            }
            hasLoaded = true
        }
    }

    /// Call from each item's `onAppear`; fetches the next page near the end.
    func itemAppeared(_ recipe: RecipeSummary) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard let index = items.firstIndex(where: { $0.id == recipe.id }), index >= items.count - 8 else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let query = makeQuery(page: page + 1) else { return }
        let generation = self.generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await mealie.recipes(query)
            guard generation == self.generation else { return }
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            page = result.page
            hasMore = result.hasMore && !result.items.isEmpty
            total = result.total
        } catch {
            let error = MealieError.wrap(error)
            guard !error.isCancelled else { return }
            refreshError = error.errorDescription
        }
    }

    /// Pull-to-refresh: also refreshes favorites/ratings.
    func refresh() async {
        await userData.load(mealie, force: true)
        if sort == .random { seed = UUID().uuidString }
        await reload()
    }

    /// Hides recipes deleted elsewhere until the next reload confirms it.
    func removeDeleted(_ ids: Set<String>) {
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        if let total, items.count < before { self.total = max(0, total - (before - items.count)) }
    }

    func clearFilters() {
        filters = RecipeFilters()
    }

    #if DEBUG
    /// Debug route `recipes-error`: show the first-load error state.
    func simulateError() {
        items = []
        hasLoaded = true
        loadError = MealieError.unreachable("The request timed out.").errorDescription
    }
    #endif

    private func makeQuery(page: Int) -> RecipeQuery? {
        RecipeListQueryBuilder.query(preset: preset, search: search, sort: sort, filters: filters,
                                     favoriteIDs: userData.favoriteIDs, page: page, perPage: Self.perPage, seed: seed)
    }
}
