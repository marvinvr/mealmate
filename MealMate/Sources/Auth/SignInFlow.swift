import AuthenticationServices
import UIKit

/// Result of any sign-in method: the token to store and the validated user.
struct SignInResult: Sendable {
    var serverURL: URL
    var token: String
    /// Set when MealMate minted a long-lived API token (revoked on sign-out).
    var mintedTokenID: Int?
    var user: User
    var appInfo: AppInfo?
}

/// The three sign-in methods. Each ends by validating the token with
/// `GET /api/users/self`; OIDC and password additionally swap the short-lived
/// session token for a long-lived API token ("MealMate on <device>").
@MainActor
struct SignInFlow {
    let server: MealieService
    var appInfo: AppInfo?

    init(serverURL: URL, appInfo: AppInfo? = nil) {
        self.server = MealieService(baseURL: serverURL)
        self.appInfo = appInfo
    }

    // MARK: OIDC (primary)

    /// Runs Mealie's native OIDC flow in an `ASWebAuthenticationSession`
    /// (shared browser session, so existing IdP logins/passkeys are reused).
    func signInWithOIDC() async throws -> SignInResult {
        let config = try await server.oidcNativeConfig()
        let request = OIDCAuthorizationRequest(config: config)
        guard let url = request.url else { throw OIDCError.invalidAuthorizationEndpoint }

        let callbackURL = try await WebAuthenticator().authenticate(
            url: url,
            callbackScheme: OIDCAuthorizationRequest.callbackScheme
        )

        let code = try request.authorizationCode(from: callbackURL)
        let session = try await server.exchangeOIDCCode(request.tokenRequest(code: code))
        return try await finish(sessionToken: session.accessToken, mintLongLivedToken: true)
    }

    // MARK: Username & password

    func signIn(username: String, password: String) async throws -> SignInResult {
        let session: AuthTokenResponse
        do {
            session = try await server.passwordLogin(username: username, password: password)
        } catch MealieError.unauthorized {
            throw SignInError.wrongCredentials
        }
        return try await finish(sessionToken: session.accessToken, mintLongLivedToken: true)
    }

    // MARK: API token

    func signIn(apiToken: String) async throws -> SignInResult {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Bearer ", with: "")
        guard !token.isEmpty else { throw SignInError.emptyToken }
        do {
            return try await finish(sessionToken: token, mintLongLivedToken: false)
        } catch MealieError.unauthorized {
            throw SignInError.invalidToken
        }
    }

    // MARK: Shared tail

    /// Mints a long-lived token (if requested) and validates it. If minting
    /// fails the session token is kept; it simply expires sooner.
    func finish(sessionToken: String, mintLongLivedToken: Bool) async throws -> SignInResult {
        var token = sessionToken
        var mintedID: Int?
        if mintLongLivedToken {
            do {
                let created = try await server.withToken(sessionToken).createAPIToken(name: Self.tokenName)
                token = created.token
                mintedID = created.id
            } catch {
                mealieLogger.notice("Minting an API token failed, keeping the session token: \(error.localizedDescription, privacy: .public)")
            }
        }
        let user = try await server.withToken(token).currentUser()
        return SignInResult(serverURL: server.baseURL, token: token, mintedTokenID: mintedID, user: user, appInfo: appInfo)
    }

    /// e.g. "MealMate on iPhone". (Since iOS 16 the device name is generic
    /// without a special entitlement; Mealie allows duplicate names.)
    static var tokenName: String {
        "MealMate on \(UIDevice.current.name)"
    }
}

enum SignInError: LocalizedError, Equatable {
    case wrongCredentials
    case invalidToken
    case emptyToken

    var errorDescription: String? {
        switch self {
        case .wrongCredentials: "Wrong username or password."
        case .invalidToken: "This API token isn’t valid on this server."
        case .emptyToken: "Paste an API token first."
        }
    }
}
