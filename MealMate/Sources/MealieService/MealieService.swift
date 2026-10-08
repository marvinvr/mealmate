import Foundation
import OSLog

let mealieLogger = Logger(subsystem: "com.mealmate-app.ios", category: "Mealie")

/// The Mealie API client: base URL + bearer token, async/await, typed errors.
///
/// A value type: it is cheap to copy and safe to use from any task. The
/// signed-in instance lives on `AppSession.service` and is injected into the
/// SwiftUI environment as `\.mealie`. Area endpoints live in
/// `MealieService+<Area>.swift`; add new ones there (see docs).
struct MealieService: Sendable {
    /// Server root, e.g. `https://mealie.example.com` (may contain a sub-path).
    let baseURL: URL
    /// Bearer token (API token or session token). `nil` for unauthenticated calls.
    let token: String?
    let session: URLSession
    /// Called (from any thread) when an authenticated request gets a 401.
    let onUnauthorized: (@Sendable () -> Void)?

    init(
        baseURL: URL,
        token: String? = nil,
        session: URLSession = .mealie,
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.onUnauthorized = onUnauthorized
    }

    /// Placeholder used as the SwiftUI environment default before sign-in.
    static let unconfigured = MealieService(baseURL: URL(string: "https://mealie.invalid")!)

    /// Same server, different token (e.g. after minting a long-lived API token).
    func withToken(_ token: String?, onUnauthorized: (@Sendable () -> Void)? = nil) -> MealieService {
        MealieService(baseURL: baseURL, token: token, session: session, onUnauthorized: onUnauthorized)
    }

    /// Scope for `ResponseCache` keys so different servers never share cached data.
    var cacheScope: String { baseURL.absoluteString }

    // MARK: - Sending

    /// Sends a request and decodes the JSON response.
    func send<T: Decodable>(_ request: MealieRequest, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await data(for: request)
        do {
            return try MealieJSON.decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            let description = MealieError.describe(error)
            mealieLogger.error("Decoding \(String(describing: T.self), privacy: .public) from \(request.path, privacy: .public) failed: \(description, privacy: .public)")
            throw MealieError.decoding(description)
        }
    }

    /// Sends a request and ignores the response body.
    func perform(_ request: MealieRequest) async throws {
        _ = try await data(for: request)
    }

    /// Sends a request and returns the raw body for 2xx responses.
    func data(for request: MealieRequest) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try makeURLRequest(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            let wrapped = MealieError.wrap(error)
            if !wrapped.isCancelled {
                mealieLogger.notice("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            throw wrapped
        }
        guard let http = response as? HTTPURLResponse else {
            throw MealieError.unreachable("Unexpected response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = MealieError(status: http.statusCode, body: data)
            mealieLogger.notice("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) → \(http.statusCode)")
            if error.isUnauthorized, request.authenticated, token != nil {
                onUnauthorized?()
            }
            throw error
        }
        return (data, http)
    }

    func makeURLRequest(_ request: MealieRequest) throws -> URLRequest {
        guard let url = url(path: request.path, query: request.query) else {
            throw MealieError.invalidServerURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType = request.contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if request.authenticated, let token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    /// Absolute URL for an API path such as `/api/recipes/{slug}`.
    /// The path must already be percent-encoded (use `String.pathSegment` for slugs/IDs).
    func url(path: String, query: [URLQueryItem] = []) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(string: base + "/" + trimmed) else { return nil }
        guard !query.isEmpty else { return components.url }
        components.queryItems = query
        // URLComponents leaves "+" alone, but the server decodes it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    // MARK: - Pagination

    /// Fetches every page of a paginated endpoint (`page`/`perPage` are managed here).
    func fetchAllPages<Item: Codable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        perPage: Int = 100,
        maxPages: Int = 50,
        as type: Item.Type = Item.self
    ) async throws -> [Item] {
        var items: [Item] = []
        var page = 1
        while page <= maxPages {
            let pageQuery = query.filter { $0.name != "page" && $0.name != "perPage" } + [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(perPage)),
            ]
            let result: Page<Item> = try await send(.get(path, query: pageQuery))
            items += result.items
            guard result.page < result.totalPages, !result.items.isEmpty else { break }
            page += 1
        }
        return items
    }

    // MARK: - Cache convenience

    /// Last cached value for `key` on this server (see `ResponseCache`).
    func cached<T: Decodable & Sendable>(_ type: T.Type, key: String) async -> T? {
        await ResponseCache.shared.value(type, key: key, scope: cacheScope)
    }

    /// Stores `value` for instant display on next launch.
    func storeInCache<T: Encodable & Sendable>(_ value: T, key: String) async {
        await ResponseCache.shared.store(value, key: key, scope: cacheScope)
    }
}

// MARK: - Request

/// One HTTP request against the Mealie API.
struct MealieRequest: Sendable {
    enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    var method: Method = .get
    /// API path starting with `/api/...`.
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
    var contentType: String?
    /// Sends the bearer token when `true` and the service has one.
    var authenticated = true
    /// Overrides the session's request timeout.
    var timeout: TimeInterval?

    static func get(_ path: String, query: [URLQueryItem] = []) -> MealieRequest {
        MealieRequest(method: .get, path: path, query: query)
    }

    static func delete(_ path: String, query: [URLQueryItem] = []) -> MealieRequest {
        MealieRequest(method: .delete, path: path, query: query)
    }

    /// Request with a JSON body encoded by `MealieJSON.encoder`.
    static func json(_ method: Method, _ path: String, body: some Encodable, query: [URLQueryItem] = []) throws -> MealieRequest {
        let data: Data
        do {
            data = try MealieJSON.encoder.encode(body)
        } catch {
            throw MealieError.decoding("Could not encode request body: \(error.localizedDescription)")
        }
        return MealieRequest(method: method, path: path, query: query, body: data, contentType: "application/json")
    }

    /// Request without body (e.g. `POST /api/users/{id}/favorites/{slug}`).
    static func empty(_ method: Method, _ path: String, query: [URLQueryItem] = []) -> MealieRequest {
        MealieRequest(method: method, path: path, query: query)
    }

    /// `application/x-www-form-urlencoded` body (used by `POST /api/auth/token`).
    static func form(_ path: String, fields: [(String, String)]) -> MealieRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return MealieRequest(method: .post, path: path, body: Data(body.utf8), contentType: "application/x-www-form-urlencoded")
    }

    /// `multipart/form-data` body (image and asset uploads).
    static func multipart(_ method: Method, _ path: String, parts: [MultipartPart]) -> MealieRequest {
        let boundary = "MealMate-\(UUID().uuidString)"
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            if let fileName = part.fileName {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(fileName)\"\r\n".utf8))
                body.append(Data("Content-Type: \(part.mimeType ?? "application/octet-stream")\r\n\r\n".utf8))
            } else {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n".utf8))
            }
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return MealieRequest(method: method, path: path, body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }
}

struct MultipartPart: Sendable {
    var name: String
    var data: Data
    var fileName: String?
    var mimeType: String?

    static func field(_ name: String, _ value: String) -> MultipartPart {
        MultipartPart(name: name, data: Data(value.utf8))
    }

    static func file(_ name: String, data: Data, fileName: String, mimeType: String) -> MultipartPart {
        MultipartPart(name: name, data: data, fileName: fileName, mimeType: mimeType)
    }
}

// MARK: - Path helpers

extension String {
    /// Escapes a value for use as a single path segment (slugs, IDs).
    var pathSegment: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

extension URLSession {
    /// Session used for all API calls. Image loading uses `URLSession.shared`
    /// with the enlarged `URLCache.shared` (see `MealMateApp`).
    static let mealie: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "MealMate-iOS"]
        return URLSession(configuration: configuration)
    }()
}
