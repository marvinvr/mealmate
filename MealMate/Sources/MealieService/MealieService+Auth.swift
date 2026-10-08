import Foundation

// Server info, sign-in and the current user.
extension MealieService {
    /// `GET /api/app/about` (unauthenticated). Throws `.notMealie` if the
    /// address answers with something that isn't Mealie's about payload.
    func appInfo() async throws -> AppInfo {
        var request = MealieRequest.get("/api/app/about")
        request.authenticated = false
        request.timeout = 10
        do {
            return try await send(request)
        } catch let error as MealieError {
            switch error {
            case .decoding, .notFound: throw MealieError.notMealie
            default: throw error
            }
        }
    }

    /// `GET /api/auth/oauth/native/config` (unauthenticated).
    func oidcNativeConfig() async throws -> OIDCNativeConfig {
        var request = MealieRequest.get("/api/auth/oauth/native/config")
        request.authenticated = false
        return try await send(request)
    }

    /// `POST /api/auth/oauth/native/token`: exchanges an authorization code (PKCE) for a session token.
    func exchangeOIDCCode(_ body: OIDCNativeTokenRequest) async throws -> AuthTokenResponse {
        var request = try MealieRequest.json(.post, "/api/auth/oauth/native/token", body: body)
        request.authenticated = false
        return try await send(request)
    }

    /// `POST /api/auth/token` (form-encoded username/password) → session token.
    func passwordLogin(username: String, password: String, rememberMe: Bool = true) async throws -> AuthTokenResponse {
        var request = MealieRequest.form("/api/auth/token", fields: [
            ("username", username),
            ("password", password),
            ("remember_me", rememberMe ? "true" : "false"),
        ])
        request.authenticated = false
        return try await send(request)
    }

    /// `GET /api/users/self`. Also the canonical "is this token valid?" check.
    func currentUser() async throws -> User {
        try await send(.get("/api/users/self"))
    }

    /// `POST /api/users/api-tokens`: mints a long-lived API token for the current user.
    func createAPIToken(name: String) async throws -> APITokenCreated {
        struct Body: Encodable { let name: String }
        return try await send(.json(.post, "/api/users/api-tokens", body: Body(name: name)))
    }

    /// `DELETE /api/users/api-tokens/{id}`.
    func deleteAPIToken(id: Int) async throws {
        try await perform(.delete("/api/users/api-tokens/\(id)"))
    }

    /// `GET /api/groups/ai-providers/settings`: whether AI import / AI parsing are available.
    func aiProviderSettings() async throws -> AIProviderSettings {
        try await send(.get("/api/groups/ai-providers/settings"))
    }

    /// Avatar image URL (`/api/media/users/{id}/profile.webp`, no auth needed).
    func userAvatarURL(userID: String, cacheKey: String? = nil) -> URL? {
        url(path: "/api/media/users/\(userID.pathSegment)/profile.webp",
            query: cacheKey.map { [URLQueryItem(name: "cacheKey", value: $0)] } ?? [])
    }
}
