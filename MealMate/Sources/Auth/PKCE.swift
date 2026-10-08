import CryptoKit
import Foundation
import Security

/// PKCE (RFC 7636) with the S256 method.
struct PKCE: Sendable, Hashable {
    /// 43–128 chars from the unreserved set `[A-Za-z0-9-._~]` (we produce base64url).
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    /// Fresh random verifier: 32 random bytes → 43 base64url characters.
    static func generate(byteCount: Int = 32) -> PKCE {
        PKCE(verifier: randomURLSafeString(byteCount: byteCount))
    }

    /// `BASE64URL(SHA256(ASCII(verifier)))`.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    /// Cryptographically random base64url string (no padding). Also used for `state` and `nonce`.
    static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // Practically unreachable; SystemRandomNumberGenerator is also a CSPRNG.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// RFC 4648 §5 base64url without padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
