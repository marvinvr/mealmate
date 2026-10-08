import AuthenticationServices
import UIKit

/// Async wrapper around `ASWebAuthenticationSession` that anchors to the key
/// window itself (SwiftUI's `webAuthenticationSession` environment action can
/// fail with "presentation context not provided" when called early).
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Opens `url` and returns the callback URL with the custom `callbackScheme`.
    /// Throws `OIDCError.cancelled` when the user closes the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OIDCError.cancelled)
                } else {
                    continuation.resume(throwing: OIDCError.browserUnavailable)
                }
            }
            session.presentationContextProvider = self
            // Shared session: reuse the user's IdP login (passkeys, SSO cookies).
            session.prefersEphemeralWebBrowserSession = Self.prefersEphemeralSession
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OIDCError.browserUnavailable)
            }
        }
    }

    /// DEBUG: `MEALMATE_OIDC_EPHEMERAL=1` skips the "wants to use … to sign in"
    /// consent alert so the harness can run the whole flow unattended.
    private static var prefersEphemeralSession: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MEALMATE_OIDC_EPHEMERAL"] == "1"
        #else
        false
        #endif
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
