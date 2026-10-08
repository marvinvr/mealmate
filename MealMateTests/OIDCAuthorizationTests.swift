import Foundation
import Testing
@testable import MealMate

struct OIDCAuthorizationTests {
    private let config = OIDCNativeConfig(
        authorizationEndpoint: URL(string: "https://idp.example.com/authorize")!,
        clientId: "mealmate-example-client",
        scope: "openid email profile"
    )

    private func makeRequest() -> OIDCAuthorizationRequest {
        OIDCAuthorizationRequest(config: config, pkce: PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                                 state: "state-123", nonce: "nonce-456")
    }

    @Test func authorizationURLContainsAllParameters() throws {
        let url = try #require(makeRequest().url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "idp.example.com")
        #expect(components.path == "/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "mealmate-example-client")
        #expect(items["redirect_uri"] == "mealmate://oauth/callback")
        #expect(items["scope"] == "openid email profile")
        #expect(items["state"] == "state-123")
        #expect(items["nonce"] == "nonce-456")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
    }

    @Test func keepsExistingQueryItemsOnEndpoint() throws {
        var config = config
        config.authorizationEndpoint = URL(string: "https://idp.example.com/authorize?tenant=home")!
        let url = try #require(OIDCAuthorizationRequest(config: config).url)
        #expect(url.absoluteString.contains("tenant=home"))
        #expect(url.absoluteString.contains("code_challenge_method=S256"))
    }

    @Test func randomStateAndNonceDiffer() {
        let a = OIDCAuthorizationRequest(config: config)
        let b = OIDCAuthorizationRequest(config: config)
        #expect(a.state != b.state)
        #expect(a.nonce != b.nonce)
        #expect(a.state.count >= 32)
    }

    @Test func validCallbackReturnsCode() throws {
        let code = try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?code=abc&state=state-123")!)
        #expect(code == "abc")
    }

    @Test func mismatchedStateIsRejected() {
        #expect(throws: OIDCError.stateMismatch) {
            try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?code=abc&state=evil")!)
        }
        #expect(throws: OIDCError.stateMismatch) {
            try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?code=abc")!)
        }
    }

    @Test func missingCodeIsRejected() {
        #expect(throws: OIDCError.missingCode) {
            try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?state=state-123")!)
        }
    }

    @Test func wrongSchemeIsRejected() {
        #expect(throws: OIDCError.invalidCallback) {
            try makeRequest().authorizationCode(from: URL(string: "https://evil.example.com/cb?code=abc&state=state-123")!)
        }
    }

    @Test func providerErrorsAreSurfaced() {
        #expect(throws: OIDCError.provider(error: "invalid_scope", description: "nope")) {
            try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?error=invalid_scope&error_description=nope&state=state-123")!)
        }
        #expect(throws: OIDCError.cancelled) {
            try makeRequest().authorizationCode(from: URL(string: "mealmate://oauth/callback?error=access_denied")!)
        }
    }

    @Test func tokenRequestUsesVerifierRedirectAndNonce() throws {
        let body = makeRequest().tokenRequest(code: "abc")
        let json = try #require(try JSONSerialization.jsonObject(with: MealieJSON.encoder.encode(body)) as? [String: String])
        #expect(json == [
            "code": "abc",
            "code_verifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            "redirect_uri": "mealmate://oauth/callback",
            "nonce": "nonce-456",
        ])
    }
}
