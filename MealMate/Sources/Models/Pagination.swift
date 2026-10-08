import Foundation

/// Mealie's pagination wrapper (`PaginationBase_*`).
///
/// `items` is decoded leniently: undecodable elements are dropped instead of
/// failing the whole page.
struct Page<Item: Codable & Sendable>: Codable, Sendable {
    var page: Int
    var perPage: Int
    var total: Int
    var totalPages: Int
    var items: [Item]
    var next: String?
    var previous: String?

    var hasMore: Bool { next != nil || page < totalPages }

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case total
        case totalPages = "total_pages"
        case items, next, previous
    }

    init(page: Int = 1, perPage: Int = 0, total: Int = 0, totalPages: Int = 0, items: [Item] = [], next: String? = nil, previous: String? = nil) {
        self.page = page
        self.perPage = perPage
        self.total = total
        self.totalPages = totalPages
        self.items = items
        self.next = next
        self.previous = previous
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.decodeLossyArrayIfPresent([Item].self, forKey: .items) ?? []
        page = (try? container.decodeIfPresent(Int.self, forKey: .page)) ?? 1
        perPage = (try? container.decodeIfPresent(Int.self, forKey: .perPage)) ?? items.count
        total = (try? container.decodeIfPresent(Int.self, forKey: .total)) ?? items.count
        totalPages = (try? container.decodeIfPresent(Int.self, forKey: .totalPages)) ?? 1
        next = try? container.decodeIfPresent(String.self, forKey: .next)
        previous = try? container.decodeIfPresent(String.self, forKey: .previous)
    }
}

/// Common query parameters for paginated Mealie list endpoints.
struct PageQuery: Sendable, Hashable {
    var page: Int = 1
    /// Mealie accepts `-1` for "all items".
    var perPage: Int = 50
    var orderBy: String?
    var orderDirection: SortDirection?
    /// Mealie query filter syntax, e.g. `name LIKE "%soup%"`.
    var queryFilter: String?
    /// Required by Mealie when `orderBy` is `random`.
    var paginationSeed: String?

    enum SortDirection: String, Sendable {
        case asc, desc
    }

    static let all = PageQuery(page: 1, perPage: -1)

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(perPage)),
        ]
        if let orderBy { items.append(URLQueryItem(name: "orderBy", value: orderBy)) }
        if let orderDirection { items.append(URLQueryItem(name: "orderDirection", value: orderDirection.rawValue)) }
        if let queryFilter { items.append(URLQueryItem(name: "queryFilter", value: queryFilter)) }
        if let paginationSeed { items.append(URLQueryItem(name: "paginationSeed", value: paginationSeed)) }
        return items
    }
}
