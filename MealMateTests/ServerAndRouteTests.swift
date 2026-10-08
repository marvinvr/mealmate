import Foundation
import Testing
@testable import MealMate

struct ServerAddressTests {
    @Test func bareHostTriesHTTPSThenHTTP() {
        #expect(ServerAddress.candidates(for: "mealie.local").map(\.absoluteString) == ["https://mealie.local", "http://mealie.local"])
    }

    @Test(arguments: [
        ("http://mealie.local", "http://mealie.local"),
        ("http://mealie.local/", "http://mealie.local"),
        ("  https://mealie.example.com///  ", "https://mealie.example.com"),
        ("http://192.168.1.20:9000", "http://192.168.1.20:9000"),
        ("https://mealie.example.com/g/home/r/soup?x=1#top", "https://mealie.example.com"),
        ("https://example.com/mealie/api/app/about", "https://example.com/mealie"),
        ("HTTPS://Mealie.Example.com/login", "https://Mealie.Example.com"),
    ])
    func explicitSchemeIsKept(_ input: String, _ expected: String) {
        #expect(ServerAddress.candidates(for: input).map(\.absoluteString) == [expected])
    }

    @Test(arguments: ["", "   ", "ftp://mealie.local", "not a url", "http://"])
    func rejectsInvalidInput(_ input: String) {
        #expect(ServerAddress.candidates(for: input).isEmpty)
    }
}

struct MealieServiceURLTests {
    private let service = MealieService(baseURL: URL(string: "https://example.com/mealie/")!, token: "t")

    @Test func joinsPathsAndEscapesQuery() throws {
        let url = try #require(service.url(path: "/api/recipes", query: [URLQueryItem(name: "search", value: "mac+cheese")]))
        #expect(url.absoluteString == "https://example.com/mealie/api/recipes?search=mac%2Bcheese")
    }

    @Test func imageURLsUseVersionKey() throws {
        let url = try #require(service.recipeImageURL(recipeID: "abc", imageKey: "aB3x", size: .min))
        #expect(url.absoluteString == "https://example.com/mealie/api/media/recipes/abc/images/min-original.webp?version=aB3x")
    }

    @Test func requestCarriesBearerToken() throws {
        let request = try service.makeURLRequest(.get("/api/users/self"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        var unauthenticated = MealieRequest.get("/api/app/about")
        unauthenticated.authenticated = false
        #expect(try service.makeURLRequest(unauthenticated).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func formBodyIsEncoded() throws {
        let request = MealieRequest.form("/api/auth/token", fields: [("username", "jane@example.com"), ("password", "a&b=c d")])
        #expect(String(data: try #require(request.body), encoding: .utf8) == "username=jane%40example.com&password=a%26b%3Dc%20d")
        #expect(request.contentType == "application/x-www-form-urlencoded")
    }

    @Test func recipeQueryItems() {
        var query = RecipeQuery(search: " soup ", sort: .name)
        query.tags = ["vegetarian"]
        let items = Dictionary(query.queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(items["search"] == "soup")
        #expect(items["orderBy"] == "name")
        #expect(items["orderDirection"] == "asc")
        #expect(items["tags"] == "vegetarian")
    }
}

struct AppRouteTests {
    @Test func parsesRegisteredRoutes() {
        #expect(AppRoute(string: "recipes") == .tab(.recipes))
        #expect(AppRoute(string: "mealplan") == .tab(.mealPlan))
        #expect(AppRoute(string: "settings") == .settings)
        #expect(AppRoute(string: "login") == .login)
        #expect(AppRoute(string: "recipe/lemon-herb-chicken") == .push(.recipe(slug: "lemon-herb-chicken"), tab: .recipes))
        #expect(AppRoute(string: "cook/lemon-herb-chicken") == .present(.cookMode(slug: "lemon-herb-chicken")))
        #expect(AppRoute(string: "shopping/abc") == .push(.shoppingList(id: "abc"), tab: .shopping))
        #expect(AppRoute(string: "nope") == nil)
        #expect(AppRoute(string: "recipe") == nil)
    }

    @Test func parsesDeepLinksButNotOAuthCallback() {
        #expect(AppRoute(url: URL(string: "mealmate://recipe/soup")!) == .push(.recipe(slug: "soup"), tab: .recipes))
        #expect(AppRoute(url: URL(string: "mealmate://shopping")!) == .tab(.shopping))
        #expect(AppRoute(url: URL(string: "mealmate://oauth/callback?code=x")!) == nil)
        #expect(AppRoute(url: URL(string: "https://example.com/recipe/soup")!) == nil)
    }
}
