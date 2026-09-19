import Testing
import Foundation
@testable import OnBoard

struct LocalDateTests {
    // MARK: - Parsing pins the API's zone

    @Test func parsingUsesStockholmZoneNotDeviceZone() throws {
        // Given: a timestamp as the API sends it — local Swedish time with no
        // zone designator. 12:00 in Stockholm is 11:00 UTC (CET, UTC+1) in
        // January, regardless of the device's zone.
        let date = try LocalDate(string: "2099-01-01T12:00:00")

        // Then: the same wall-clock string decodes to the Stockholm instant,
        // not an instant relative to the device's zone.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date.date
        )
        #expect(components.year == 2099)
        #expect(components.month == 1)
        #expect(components.day == 1)
        #expect(components.hour == 11)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test func summerTimestampUsesStockholmSummerTime() throws {
        // Given: Sweden is on summer time (CEST, UTC+2) in June, so 08:30 in
        // Stockholm is 06:30 UTC.
        let date = try LocalDate(string: "2099-06-15T08:30:00")

        // Then: the parsed instant reflects the Stockholm offset in effect on
        // that date, not the device's zone or a fixed offset.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents(
            [.hour, .minute],
            from: date.date
        )
        #expect(components.hour == 6)
        #expect(components.minute == 30)
    }

    @Test func encodeDecodeRoundTripKeepsWallClockString() throws {
        // Given: a timestamp parsed from the API's format.
        let date = try LocalDate(string: "2099-06-15T08:30:00")

        // When: encoded as the API's format, the wall-clock string matches.
        let encoded = try JSONEncoder().encode(date)
        #expect(String(data: encoded, encoding: .utf8) == "\"2099-06-15T08:30:00\"")

        // Then: decoding it back yields an equal value.
        let decoded = try JSONDecoder().decode(LocalDate.self, from: encoded)
        #expect(decoded == date)
    }

    // MARK: - Truncation

    @Test func truncatesFractionalSeconds() {
        // Given: an instant with sub-second precision.
        let date = LocalDate(date: Date(timeIntervalSinceReferenceDate: 100.75))

        // Then: the stored instant is truncated to whole seconds.
        #expect(date.date.timeIntervalSinceReferenceDate == 100)
    }

    // MARK: - Error cases

    @Test func emptyStringThrowsFromDecoder() async {
        // Given: the wire format can carry an empty string for an absent time.
        let data = Data("\"\"".utf8)

        // Then: decoding surfaces the guard's DecodingError rather than a
        // crash or a sentinel date.
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(LocalDate.self, from: data)
        }
    }

    @Test func malformedStringThrows() async {
        #expect(throws: (any Error).self) {
            _ = try LocalDate(string: "not-a-date")
        }
    }
}
