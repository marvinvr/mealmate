import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
///
/// Items live in the shared access group (`MealMateKeychainAccessGroup` in
/// Info.plist → `<TeamID>.com.mealmate-app.ios.shared`) so the share extension
/// can read the token. If the group isn't usable (unsigned simulator builds,
/// missing entitlement) it transparently falls back to the app's default group.
struct KeychainStore: Sendable {
    let service: String
    let accessGroup: String?

    static let shared = KeychainStore(
        service: "com.mealmate-app.ios",
        accessGroup: KeychainStore.configuredAccessGroup
    )

    /// Shared group from Info.plist; `nil` if the build variable wasn't expanded.
    static var configuredAccessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MealMateKeychainAccessGroup") as? String,
              !group.isEmpty, !group.contains("$("), !group.hasPrefix(".") else { return nil }
        return group
    }

    func string(for account: String) -> String? {
        data(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    func data(for account: String) -> Data? {
        for group in groupsToTry {
            var query = baseQuery(account: account, group: group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data { return data }
        }
        return nil
    }

    @discardableResult
    func set(_ value: String?, for account: String) -> Bool {
        guard let value else {
            delete(account)
            return true
        }
        return set(Data(value.utf8), for: account)
    }

    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        delete(account)
        for group in groupsToTry {
            var query = baseQuery(account: account, group: group)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess { return true }
            if status != errSecMissingEntitlement && status != errSecNoAccessForItem { return false }
            // Group not available in this build: retry with the default group.
        }
        return false
    }

    func delete(_ account: String) {
        for group in groupsToTry {
            SecItemDelete(baseQuery(account: account, group: group) as CFDictionary)
        }
    }

    private var groupsToTry: [String?] {
        accessGroup.map { [$0, nil] } ?? [nil]
    }

    private func baseQuery(account: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}
