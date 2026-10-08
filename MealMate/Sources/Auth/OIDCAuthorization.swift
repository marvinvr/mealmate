import Foundation

/// Builds the OIDC authorization request for Mealie's native flow and validates
/// the redirect. Pure value logic (unit tested); the browser part lives in `SignInFlow`.
///
/// Flow: `GET /api/auth/oauth/native/config` → this request (PKCE S256 + state +
/// nonce) in `ASWebAuthenticationSession` → redirect to
/// `mealmate://oauth/callback?code=…&state=…` → `POST /api/auth/oauth/native/token`.
struct OIDCAuthorizationRequest: Sendable, Hashable {
    /// Must be registered as an allowed redirect URI at the identity provider.
    static let redirectURI = "mealmate://oauth/callback"
    static let callbackScheme = "mealmate"

    let config: OIDCNativeConfig
    let pkce: PKCE
    let state: String
    let nonce: String

    init(
        config: OIDCNativeConfig,
        pkce: PKCE = .generate(),
        state: String = PKCE.randomURLSafeString(byteCount: 24),
        nonce: String = PKCE.randomURLSafeString(byteCount: 24)
    ) {
        self.config = config
        self.pkce = pkce
        self.state = state
        self.nonce = nonce
    }

    /// The authorization URL (existing query items on the endpoint are preserved).
    var url: URL? {
        guard var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        components.queryItems = items
        // Keep "+" literal-safe in scope/state values.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Validates the redirect and returns the authorization code.
    func authorizationCode(from callbackURL: URL) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.callbackScheme else {
            throw OIDCError.invalidCallback
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            if error == "access_denied" { throw OIDCError.cancelled }
            throw OIDCError.provider(error: error, description: value("error_description"))
        }
        guard value("state") == state else { throw OIDCError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw OIDCError.missingCode }
        return code
    }

    /// Body for `POST /api/auth/oauth/native/token`.
    func tokenRequest(code: String) -> OIDCNativeTokenRequest {
        OIDCNativeTokenRequest(code: code, codeVerifier: pkce.verifier, redirectURI: Self.redirectURI, nonce: nonce)
    }
}

enum OIDCError: LocalizedError, Equatable, Sendable {
    case invalidAuthorizationEndpoint
    case invalidCallback
    case stateMismatch
    case missingCode
    case cancelled
    /// ASWebAuthenticationSession couldn't be shown (no window yet, already running, ...).
    case browserUnavailable
    case provider(error: String, description: String?)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationEndpoint:
            "The server’s sign-in configuration is invalid (authorization endpoint)."
        case .invalidCallback, .missingCode:
            "Sign-in didn’t return to MealMate correctly. Please try again."
        case .stateMismatch:
            "Sign-in response didn’t match the request. Please try again."
        case .cancelled:
            "Sign-in was cancelled."
        case .browserUnavailable:
            "The sign-in page couldn’t be opened. Please try again."
        case .provider(let error, let description):
            if error == "invalid_request", description?.localizedCaseInsensitiveContains("redirect") == true {
                "Your identity provider rejected MealMate’s redirect address. Ask your admin to allow \(OIDCAuthorizationRequest.redirectURI)."
            } else {
                "Your identity provider reported an error: \(description ?? error)"
            }
        }
    }
}
