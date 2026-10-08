import Foundation
@testable import MealMate

/// Loads recorded (anonymized) Mealie responses from `Fixtures/`.
enum Fixture {
    private final class BundleToken {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try MealieJSON.decoder.decode(T.self, from: data(name))
    }

    enum FixtureError: Error { case missing(String) }
}
