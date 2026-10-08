import Foundation
import Testing
@testable import MealMate

struct DateParsingTests {
    /// 2026-10-08T18:36:03.240153Z
    private let reference = Date(timeIntervalSince1970: 1_791_484_563.240153)

    @Test(arguments: [
        "2026-10-08T18:36:03.240153Z",
        "2026-10-08T18:36:03.240153+00:00",
        "2026-10-08T20:36:03.240153+02:00",
        "2026-10-08T13:36:03.240153-0500",
        "2026-10-08T18:36:03.240153",
        "2026-10-08 18:36:03.240153",
    ])
    func parsesMealieTimestampVariants(_ string: String) throws {
        let date = try #require(MealieDateParser.date(from: string))
        #expect(abs(date.timeIntervalSince(reference)) < 0.000_01)
    }

    @Test func parsesWithoutFractionAndSeconds() throws {
        let noFraction = try #require(MealieDateParser.date(from: "2026-10-08T18:36:03Z"))
        #expect(noFraction.timeIntervalSince1970 == 1_791_484_563)
        let noSeconds = try #require(MealieDateParser.date(from: "2026-10-08T18:36Z"))
        #expect(noSeconds.timeIntervalSince1970 == 1_791_484_560)
        let millis = try #require(MealieDateParser.date(from: "2026-10-08T18:36:03.240Z"))
        #expect(abs(millis.timeIntervalSince1970 - 1_791_484_563.24) < 0.000_1)
    }

    @Test func dateOnlyIsLocalMidnight() throws {
        let date = try #require(MealieDateParser.date(from: "2026-10-08"))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(components == DateComponents(year: 2026, month: 10, day: 8, hour: 0, minute: 0))
    }

    @Test(arguments: ["", "yesterday", "2026-13-01", "2026-10-08T18", "2026-10-08T18:36:03Zjunk", "08.10.2026"])
    func rejectsGarbage(_ string: String) {
        #expect(MealieDateParser.date(from: string) == nil)
    }

    @Test func roundTripsThroughEncoder() throws {
        struct Box: Codable { let date: Date }
        let data = try MealieJSON.encoder.encode(Box(date: reference))
        let string = try #require(String(data: data, encoding: .utf8))
        #expect(string.contains("2026-10-08T18:36:03.240Z"))
        let decoded = try MealieJSON.decoder.decode(Box.self, from: data)
        #expect(abs(decoded.date.timeIntervalSince(reference)) < 0.001)
    }

    @Test func mealieDayParsesAndFormats() throws {
        let day = try #require(MealieDay(string: "2030-01-07"))
        #expect(day == MealieDay(year: 2030, month: 1, day: 7))
        #expect(day.description == "2030-01-07")
        #expect(MealieDay(string: "2030-01-07T00:00:00") == day)
        #expect(day.adding(days: 1) == MealieDay(year: 2030, month: 1, day: 8))
        #expect(day.adding(days: -7) == MealieDay(year: 2029, month: 12, day: 31))
        #expect(MealieDay(string: "nope") == nil)
    }
}
