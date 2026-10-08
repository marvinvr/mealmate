import Foundation

// URL import shared by the app (`ImportRecipeView`) and the share extension
// (`ShareImportView`). Keep this file free of app-only code: the MealMateShare
// target compiles it too (see project.yml).

// MARK: - URL extraction

/// Finds the recipe link in what the user typed, pasted or shared.
enum RecipeURLExtractor {
    /// The first `http(s)` link in free text, e.g. "Look at this: https://example.com/soup".
    /// Bare `www.` hosts are accepted; mail and phone links are ignored.
    static func firstWebURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in detector.matches(in: trimmed, options: [], range: range) {
            guard let url = match.url, let web = webURL(url) else { continue }
            return web
        }
        return nil
    }

    /// Normalizes the import field: trims, adds `https://` when the scheme is
    /// missing and rejects anything that isn't a web address with a dotted host.
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return firstWebURL(in: trimmed) }
        let lowercased = trimmed.lowercased()
        let hasWebScheme = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
        // Another scheme ("mailto:", "file://", ...) but not "host:port".
        if !hasWebScheme, trimmed.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:(?!\d)/) != nil { return nil }
        let candidate = hasWebScheme ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate) else { return firstWebURL(in: trimmed) }
        return webURL(url)
    }

    /// `url` if it is an http(s) URL with a plausible host.
    static func webURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url
    }
}

// MARK: - Import

/// Imports recipes from websites through Mealie's scraper.
struct RecipeImporter: Sendable {
    let service: MealieService

    /// A recipe that was already imported from exactly this URL (Mealie keeps
    /// it in `orgURL`), so the user can open it instead of importing a copy.
    /// Best effort: `nil` on any error.
    func existingRecipe(importedFrom url: URL) async -> RecipeSummary? {
        var query = RecipeQuery()
        query.perPage = 1
        let escaped = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        query.queryFilter = "orgURL = \"\(escaped)\""
        return try? await service.recipes(query).items.first
    }

    /// `POST /api/recipes/create/url`, then loads the new recipe (for its name).
    /// Throws `RecipeImportProblem`.
    func importRecipe(from url: URL, includeOrganizers: Bool) async throws -> Recipe {
        let slug: String
        do {
            slug = try await service.createRecipe(fromURL: url.absoluteString,
                                                  includeTags: includeOrganizers,
                                                  includeCategories: includeOrganizers)
        } catch {
            throw RecipeImportProblem(MealieError.wrap(error))
        }
        do {
            return try await service.recipe(slug: slug)
        } catch {
            // Imported, but the follow-up fetch failed: still a success.
            return Recipe(id: slug, slug: slug, name: nil)
        }
    }
}

/// A failed import, phrased for people (title + what to do next).
struct RecipeImportProblem: Error, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The page loaded but has no recipe Mealie can read.
        case noRecipeFound
        /// Mealie couldn't download the page.
        case pageUnavailable
        /// The app can't reach the Mealie server.
        case serverUnreachable
        case timedOut
        case other
    }

    var kind: Kind
    var title: String
    var message: String
    /// Underlying error, `nil` for problems built by hand (previews).
    var error: MealieError?

    init(kind: Kind, title: String, message: String, error: MealieError? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.error = error
    }

    init(_ error: MealieError) {
        switch error {
        case .server(_, let message?) where message.uppercased().contains("BAD_RECIPE_DATA") || message.lowercased().contains("no recipe"):
            self.init(kind: .noRecipeFound, title: "No Recipe Found",
                      message: "Mealie couldn’t find a recipe on this page. Not every website is supported: try the recipe’s own page, or add it by hand.",
                      error: error)
        case .server(let status, _) where status == 400 || status == 422:
            // Mealie answers 400 "Something went wrong while creating the recipe" when
            // the site can't be downloaded (unknown host, blocked, 404).
            self.init(kind: .pageUnavailable, title: "Couldn’t Open the Page",
                      message: "Mealie couldn’t load this page. Check the link, or try again later.",
                      error: error)
        case .timedOut:
            self.init(kind: .timedOut, title: "Import Timed Out",
                      message: "The website or your server took too long. Try again in a moment.",
                      error: error)
        case .unreachable, .insecureConnection, .invalidServerURL, .notMealie:
            self.init(kind: .serverUnreachable, title: "Can’t Reach Your Server",
                      message: error.errorDescription ?? "Check your connection and try again.",
                      error: error)
        default:
            self.init(kind: .other, title: "Import Failed",
                      message: error.errorDescription ?? "Something went wrong. Try again.",
                      error: error)
        }
    }
}

// MARK: - Preferences

/// Import options remembered across imports (also read by the share extension
/// through the App Group defaults).
enum ImportPreferences {
    static let includeOrganizersKey = "import.includeOrganizers"

    /// Import the website's keywords as tags/categories. Off by default: it
    /// creates new tags and categories in Mealie for every site's vocabulary.
    static var includeOrganizers: Bool {
        get { CredentialStore.defaults.bool(forKey: includeOrganizersKey) }
        set { CredentialStore.defaults.set(newValue, forKey: includeOrganizersKey) }
    }
}
