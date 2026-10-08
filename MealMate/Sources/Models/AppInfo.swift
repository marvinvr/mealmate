import Foundation

/// `GET /api/app/about` (unauthenticated). Used to validate a server URL and to
/// decide which sign-in methods to offer.
struct AppInfo: Codable, Hashable, Sendable {
    var production: Bool?
    /// e.g. `"v3.28.0"`.
    var version: String
    var demoStatus: Bool?
    var allowSignup: Bool?
    var allowPasswordLogin: Bool?
    var defaultGroupSlug: String?
    var defaultHouseholdSlug: String?
    var enableOidc: Bool?
    var oidcRedirect: Bool?
    /// Shown on the primary sign-in button ("Sign in with <name>").
    var oidcProviderName: String?
    var tokenTime: Int?
    var allowedIframeHosts: [String]?

    var isOIDCEnabled: Bool { enableOidc ?? false }
    /// Older servers omit the flag; password login was always available there.
    var isPasswordLoginAllowed: Bool { allowPasswordLogin ?? true }
    var oidcButtonTitle: String {
        if let name = oidcProviderName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return "Sign in with \(name)"
        }
        return "Sign in with SSO"
    }
    /// Version without the leading "v", e.g. `"3.28.0"`.
    var displayVersion: String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}

/// `GET /api/groups/ai-providers/settings`: whether the group has an AI provider
/// configured (drives the "Import with AI" option).
struct AIProviderSettings: Codable, Hashable, Sendable {
    var defaultProviderId: String?
    var audioProviderId: String?
    var imageProviderId: String?
    var aiEnabled: Bool?
    var audioProviderEnabled: Bool?
    var imageProviderEnabled: Bool?

    var isAIAvailable: Bool { aiEnabled ?? false }
    /// Recipe-from-photo import needs an AI provider that can read images.
    var isImageImportAvailable: Bool { isAIAvailable && (imageProviderEnabled ?? false) }
}
