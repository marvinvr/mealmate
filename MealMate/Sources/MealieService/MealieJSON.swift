import Foundation

/// JSON coding configured for Mealie.
///
/// Dates: Mealie returns several formats, sometimes for the same field on
/// different endpoints (`2026-10-08T18:36:03.240153+00:00` in lists,
/// `...240153Z` in details, naive `2026-10-08T18:36:03` from older versions,
/// date-only `2026-10-08`). `MealieDateParser` accepts all of them; naive
/// timestamps are treated as UTC (Mealie stores UTC).
enum MealieJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try container.decode(String.self)
            guard let date = MealieDateParser.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
            }
            return date
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(MealieDateParser.string(from: date))
        }
        return encoder
    }()
}

enum MealieDateParser {
    /// Parses ISO 8601 date-times with optional fractional seconds (any number
    /// of digits), optional `T`/space separator, optional `Z`/`±HH:MM`/`±HHMM`
    /// offset (missing → UTC) and date-only strings (→ local midnight).
    static func date(from string: String) -> Date? {
        let chars = Array(string.trimmingCharacters(in: .whitespaces).utf8)
        func digits(_ start: Int, _ count: Int) -> Int? {
            guard start + count <= chars.count else { return nil }
            var value = 0
            for index in start..<(start + count) {
                let char = chars[index]
                guard char >= 48, char <= 57 else { return nil }
                value = value * 10 + Int(char - 48)
            }
            return value
        }
        guard chars.count >= 10,
              let year = digits(0, 4), chars[4] == UInt8(ascii: "-"),
              let month = digits(5, 2), chars[7] == UInt8(ascii: "-"),
              let day = digits(8, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        if chars.count == 10 {
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        }

        guard chars[10] == UInt8(ascii: "T") || chars[10] == UInt8(ascii: " "),
              let hour = digits(11, 2), chars.count > 13, chars[13] == UInt8(ascii: ":"),
              let minute = digits(14, 2) else { return nil }

        var index = 16
        var second = 0
        if index < chars.count, chars[index] == UInt8(ascii: ":") {
            guard let value = digits(17, 2) else { return nil }
            second = value
            index = 19
        }

        var fraction = 0.0
        if index < chars.count, chars[index] == UInt8(ascii: ".") || chars[index] == UInt8(ascii: ",") {
            index += 1
            var scale = 0.1
            while index < chars.count, chars[index] >= 48, chars[index] <= 57 {
                fraction += Double(chars[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }

        var offsetSeconds = 0
        if index < chars.count {
            let sign = chars[index]
            if sign == UInt8(ascii: "Z") || sign == UInt8(ascii: "z") {
                index += 1
            } else if sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                guard let offsetHours = digits(index + 1, 2) else { return nil }
                var offsetMinutes = 0
                var next = index + 3
                if next < chars.count, chars[next] == UInt8(ascii: ":") { next += 1 }
                if let minutes = digits(next, 2) {
                    offsetMinutes = minutes
                    next += 2
                }
                offsetSeconds = (offsetHours * 3600 + offsetMinutes * 60) * (sign == UInt8(ascii: "-") ? -1 : 1)
                index = next
            } else {
                return nil
            }
        }
        guard index == chars.count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// `2026-10-08T18:36:03.240Z` (UTC, milliseconds), accepted by Mealie.
    /// Milliseconds are rounded (not truncated) so decode → encode is stable.
    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let base = Date(timeIntervalSince1970: seconds).formatted(Date.ISO8601FormatStyle()) // ...:SSZ
        return String(base.dropLast()) + String(format: ".%03dZ", fraction)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
