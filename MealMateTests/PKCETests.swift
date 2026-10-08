import Foundation
import Testing
@testable import MealMate

struct PKCETests {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    @Test func generatedVerifierHasValidLengthAndCharset() {
        for _ in 0..<50 {
            let pkce = PKCE.generate()
            #expect((43...128).contains(pkce.verifier.count))
            #expect(pkce.verifier.unicodeScalars.allSatisfy { Self.unreserved.contains($0) })
            #expect(pkce.method == "S256")
        }
    }

    @Test func largerVerifierStaysWithinLimit() {
        let pkce = PKCE.generate(byteCount: 96)
        #expect(pkce.verifier.count == 128)
    }

    @Test func verifiersAreUnique() {
        let verifiers = Set((0..<100).map { _ in PKCE.generate().verifier })
        #expect(verifiers.count == 100)
    }

    /// RFC 7636, Appendix B.
    @Test func s256ChallengeMatchesRFCTestVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE(verifier: verifier).challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func base64URLHasNoPaddingOrUnsafeCharacters() {
        let encoded = Data([0xfb, 0xff, 0xfe, 0x00]).base64URLEncodedString()
        #expect(encoded == "-__-AA")
    }
}
