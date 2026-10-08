import Foundation
import Observation

/// Categories, tags, tools and cookbooks, shared by the Library tab and the recipe filter
/// sheet. Cached-first (`library.<kind>`), refreshed at most every two minutes unless forced.
@MainActor
@Observable
final class OrganizerStore {
    static let shared = OrganizerStore()

    private(set) var categories: [Organizer] = []
    private(set) var tags: [Organizer] = []
    private(set) var tools: [Organizer] = []
    private(set) var cookbooks: [Cookbook] = []
    private(set) var hasLoaded = false
    /// Last refresh error (cached content stays visible).
    private(set) var error: String?

    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    func organizers(_ kind: OrganizerKind) -> [Organizer] {
        switch kind {
        case .category: categories
        case .tag: tags
        case .tool: tools
        }
    }

    func organizer(_ kind: OrganizerKind, slug: String) -> Organizer? {
        organizers(kind).first { $0.slug == slug }
    }

    var isEmpty: Bool { categories.isEmpty && tags.isEmpty && tools.isEmpty && cookbooks.isEmpty }

    func load(_ mealie: MealieService, force: Bool = false) async {
        if scope != mealie.cacheScope {
            scope = mealie.cacheScope
            categories = []; tags = []; tools = []; cookbooks = []
            hasLoaded = false
            lastRefresh = nil
        }
        if !hasLoaded {
            async let categories = mealie.cached([Organizer].self, key: "library.categories")
            async let tags = mealie.cached([Organizer].self, key: "library.tags")
            async let tools = mealie.cached([Organizer].self, key: "library.tools")
            async let cookbooks = mealie.cached([Cookbook].self, key: "library.cookbooks")
            let cached = await (categories, tags, tools, cookbooks)
            if let value = cached.0 { self.categories = value }
            if let value = cached.1 { self.tags = value }
            if let value = cached.2 { self.tools = value }
            if let value = cached.3 { self.cookbooks = value }
            if cached.0 != nil || cached.1 != nil || cached.2 != nil || cached.3 != nil { hasLoaded = true }
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 120 { return }
        if let inFlight { return await inFlight.value }

        let task = Task {
            async let categories = Result { try await mealie.categories() }
            async let tags = Result { try await mealie.tags() }
            async let tools = Result { try await mealie.tools() }
            async let cookbooks = Result { try await mealie.cookbooks() }
            let results = await (categories, tags, tools, cookbooks)
            var failure: Error?
            switch results.0 {
            case .success(let value): self.categories = value; await mealie.storeInCache(value, key: "library.categories")
            case .failure(let error): failure = error
            }
            switch results.1 {
            case .success(let value): self.tags = value; await mealie.storeInCache(value, key: "library.tags")
            case .failure(let error): failure = error
            }
            switch results.2 {
            case .success(let value): self.tools = value; await mealie.storeInCache(value, key: "library.tools")
            case .failure(let error): failure = error
            }
            switch results.3 {
            case .success(let value): self.cookbooks = value; await mealie.storeInCache(value, key: "library.cookbooks")
            case .failure(let error): failure = error
            }
            if let failure, !MealieError.wrap(failure).isCancelled {
                self.error = MealieError.wrap(failure).errorDescription
            } else {
                self.error = nil
                self.lastRefresh = Date()
            }
            self.hasLoaded = true
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
