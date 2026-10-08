import CryptoKit
import Foundation

/// Tiny disk cache for "instant launch with last data".
///
/// Stores encoded API values as JSON files in `Caches/ResponseCache/<scope>/`.
/// Keys are free-form strings chosen by the caller (e.g. `"recipes.recent"`,
/// `"shopping.list.<id>"`); the scope is the server (`MealieService.cacheScope`).
///
/// Pattern for view models:
/// ```swift
/// if items.isEmpty, let cached = await mealie.cached([RecipeSummary].self, key: "recipes.recent") {
///     items = cached                       // show immediately
/// }
/// let fresh = try await mealie.recipes(RecipeQuery()).items
/// items = fresh
/// await mealie.storeInCache(fresh, key: "recipes.recent")
/// ```
/// The cache is best-effort: failures are ignored, and sign-out clears it.
actor ResponseCache {
    static let shared = ResponseCache()

    private let root: URL
    private var memory: [String: Data] = [:]

    init(directory: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = directory ?? caches.appending(path: "ResponseCache", directoryHint: .isDirectory)
    }

    func value<T: Decodable>(_ type: T.Type, key: String, scope: String) -> T? {
        let file = fileURL(key: key, scope: scope)
        let data = memory[file.path] ?? (try? Data(contentsOf: file))
        guard let data else { return nil }
        memory[file.path] = data
        return try? MealieJSON.decoder.decode(T.self, from: data)
    }

    func store<T: Encodable>(_ value: T, key: String, scope: String) {
        guard let data = try? MealieJSON.encoder.encode(value) else { return }
        let file = fileURL(key: key, scope: scope)
        memory[file.path] = data
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    func remove(key: String, scope: String) {
        let file = fileURL(key: key, scope: scope)
        memory[file.path] = nil
        try? FileManager.default.removeItem(at: file)
    }

    /// Removes everything (called on sign-out).
    func removeAll() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    private func fileURL(key: String, scope: String) -> URL {
        root
            .appending(path: Self.hash(scope), directoryHint: .isDirectory)
            .appending(path: Self.hash(key) + ".json", directoryHint: .notDirectory)
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
