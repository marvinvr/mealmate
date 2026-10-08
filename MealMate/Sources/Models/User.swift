import Foundation

/// `GET /api/users/self` (`UserOut`).
struct User: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var username: String?
    var fullName: String?
    var email: String?
    var authMethod: AuthMethod?
    var admin: Bool?
    var group: String?
    var groupId: String?
    var groupSlug: String?
    var household: String?
    var householdId: String?
    var householdSlug: String?
    var advanced: Bool?
    var canInvite: Bool?
    var canManage: Bool?
    var canManageHousehold: Bool?
    var canOrganize: Bool?
    var tokens: [APITokenInfo]?
    /// Changes when the avatar changes; append to the avatar URL for cache busting.
    var cacheKey: String?

    var displayName: String {
        if let fullName, !fullName.trimmingCharacters(in: .whitespaces).isEmpty { return fullName }
        if let username, !username.isEmpty { return username }
        return email ?? "Mealie user"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    struct AuthMethod: OpenStringEnum {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        static let mealie: Self = "Mealie"
        static let ldap: Self = "LDAP"
        static let oidc: Self = "OIDC"
    }
}

/// A long-lived API token as listed in `User.tokens` (`LongLiveTokenOut`).
struct APITokenInfo: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var name: String
    var createdAt: Date?
}

/// `POST /api/users/api-tokens` response (`LongLiveTokenCreateResponse`).
/// `token` is shown exactly once by the server.
struct APITokenCreated: Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var token: String
    var createdAt: Date?
}

/// Response of `GET /api/users/self/ratings` and `/favorites`.
struct UserRatings: Codable, Hashable, Sendable {
    var ratings: [UserRating]

    init(ratings: [UserRating] = []) { self.ratings = ratings }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratings = container.decodeLossyArrayIfPresent([UserRating].self, forKey: .ratings) ?? []
    }
}

/// Per-user rating / favorite state of one recipe (`UserRatingSummary`).
struct UserRating: Codable, Hashable, Sendable {
    var recipeId: String
    var rating: Double?
    var isFavorite: Bool?
}
