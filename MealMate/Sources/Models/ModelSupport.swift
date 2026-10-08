import Foundation

// Small decoding building blocks shared by all Mealie DTOs.
//
// Mealie's responses vary between versions and between endpoints (the same
// schema is sometimes returned with `null` lists, numbers as strings, extra
// enum values, ...). DTOs therefore use optionals generously and these helpers
// where a single bad value must not break a whole screen.

// MARK: - JSONValue

/// Arbitrary JSON, used for free-form fields such as `extras` so they survive a
/// decode → encode round trip (e.g. when a recipe is sent back with PUT).
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: - FlexibleString

/// A value that is normally a string but that some Mealie versions return as a
/// number or bool (e.g. the recipe `image` cache key). Anything non-string is
/// converted to its textual form; `false`/`null` become `nil`.
struct FlexibleString: Codable, Hashable, Sendable {
    let value: String?

    init(_ value: String?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : nil
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

// MARK: - Lossy arrays

/// Decodes an array element by element and drops elements that fail to decode,
/// so one malformed recipe or item never empties a whole list.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(DiscardedValue.self)
            }
        }
        elements = result
    }

    private struct DiscardedValue: Decodable {}
}

extension LossyArray: Sendable where Element: Sendable {}

extension KeyedDecodingContainer {
    /// Decodes an optional array leniently: missing key / `null` → `nil`,
    /// undecodable elements are dropped.
    func decodeLossyArrayIfPresent<T: Decodable>(_ type: [T].Type, forKey key: Key) -> [T]? {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return nil }
        return (try? decode(LossyArray<T>.self, forKey: key))?.elements
    }
}

// MARK: - Open string enums

/// String-backed "enum" that tolerates unknown values from newer servers.
/// Conformers are tiny structs with `static let` known cases, e.g.
/// `struct PlanEntryType: OpenStringEnum { let rawValue: String; static let dinner = Self("dinner") }`.
protocol OpenStringEnum: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral
where RawValue == String {
    init(rawValue: String)
}

extension OpenStringEnum {
    init(_ rawValue: String) { self.init(rawValue: rawValue) }
    init(stringLiteral value: String) { self.init(rawValue: value) }
    // Codable comes from the standard library's RawRepresentable<String> support;
    // because `init(rawValue:)` never fails, unknown values decode fine.
}

// MARK: - MealieDay

/// A calendar day without time or time zone (`"2026-10-08"`), as Mealie uses for
/// meal plan dates and `dateAdded`. Kept separate from `Date` so a day never
/// shifts when displayed in another time zone.
struct MealieDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local calendar day containing `date`.
    init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    static var today: MealieDay { MealieDay(Date()) }

    /// Parses `yyyy-MM-dd`; also accepts a full timestamp and keeps its date part.
    init?(string: String) {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = MealieDay(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day: \(string)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Local midnight of this day.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    func adding(days: Int, calendar: Calendar = .current) -> MealieDay {
        MealieDay(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar), calendar: calendar)
    }

    static func < (lhs: MealieDay, rhs: MealieDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
