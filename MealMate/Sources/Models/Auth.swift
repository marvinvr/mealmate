import Foundation

/// `GET /api/auth/oauth/native/config`: what a native client needs to build its
/// own OIDC authorization request (PKCE + state + nonce are owned by the app).
struct OIDCNativeConfig: Codable, Hashable, Sendable {
    var authorizationEndpoint: URL
    var clientId: String
    /// Space separated, e.g. `"openid email profile"`.
    var scope: String

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case clientId = "client_id"
        case scope
    }
}

/// Body of `POST /api/auth/oauth/native/token`.
struct OIDCNativeTokenRequest: Codable, Hashable, Sendable {
    var code: String
    var codeVerifier: String
    var redirectURI: String
    var nonce: String?

    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
        case nonce
    }
}

/// Session token returned by `POST /api/auth/token` and
/// `POST /api/auth/oauth/native/token` (`{"access_token": "...", "token_type": "bearer"}`).
struct AuthTokenResponse: Codable, Hashable, Sendable {
    var accessToken: String
    var tokenType: String?
    /// Seconds (native OIDC returns 172800 = 48 h, matching `AppInfo.tokenTime`).
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}
