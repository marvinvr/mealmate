import Foundation

/// Persisted sign-in shared by the app and the share extension.
///
/// - Server URL, token ID and cached user/app info: App Group `UserDefaults`
///   (`group.com.mealmate-app.ios`).
/// - Token: Keychain (shared access group, see `KeychainStore`).
struct StoredCredentials: Codable, Hashable, Sendable {
    var serverURL: URL
    var token: String
    /// ID of the API token MealMate minted (so sign-out can revoke it). `nil`
    /// when the user pasted their own token or minting failed.
    var mintedTokenID: Int?
}

enum CredentialStore {
    static let appGroupID = "group.com.mealmate-app.ios"

    /// App Group defaults; falls back to `.standard` if the group isn't available.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: appGroupID) ?? .standard

    private static let serverURLKey = "serverURL"
    private static let tokenIDKey = "mintedTokenID"
    private static let userKey = "cachedUser"
    private static let appInfoKey = "cachedAppInfo"
    private static let tokenAccount = "mealie-token"

    static func load() -> StoredCredentials? {
        guard let string = defaults.string(forKey: serverURLKey),
              let url = URL(string: string),
              let token = KeychainStore.shared.string(for: tokenAccount), !token.isEmpty else { return nil }
        let tokenID = defaults.object(forKey: tokenIDKey) as? Int
        return StoredCredentials(serverURL: url, token: token, mintedTokenID: tokenID)
    }

    static func save(_ credentials: StoredCredentials) {
        KeychainStore.shared.set(credentials.token, for: tokenAccount)
        defaults.set(credentials.serverURL.absoluteString, forKey: serverURLKey)
        if let id = credentials.mintedTokenID {
            defaults.set(id, forKey: tokenIDKey)
        } else {
            defaults.removeObject(forKey: tokenIDKey)
        }
    }

    static func clear() {
        KeychainStore.shared.delete(tokenAccount)
        for key in [serverURLKey, tokenIDKey, userKey, appInfoKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Last known server URL, kept after sign-out to prefill onboarding.
    static var lastServerURL: URL? {
        get { defaults.string(forKey: "lastServerURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "lastServerURL") }
    }

    static var cachedUser: User? {
        get { decode(User.self, key: userKey) }
        set { encode(newValue, key: userKey) }
    }

    static var cachedAppInfo: AppInfo? {
        get { decode(AppInfo.self, key: appInfoKey) }
        set { encode(newValue, key: appInfoKey) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? MealieJSON.decoder.decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? MealieJSON.encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
