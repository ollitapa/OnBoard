import Testing
import Foundation
@testable import OnBoard

@MainActor
struct RouteDetailsModelTests {

    @Test func loadTripSuccess() async throws {
        // Given: a canned trip keyed by the same trip id / start date the model
        // requests. The expected stops are decoded from the service's stored
        // fixture so the comparison isn't affected by the fixture's relative
        // timestamps being re-evaluated.
        let network = MockTrafiklabService(tripsByKey: MockTrafiklabService.defaultTripsByKeyJSON)
        let fixture = try #require(network.tripsByKey["900001/2099-01-01"])
        let trip = try JSONDecoder().decode(Trip.self, from: Data(fixture.utf8))
        let model = RouteDetailsModel()
        // When
        await model.loadTrip(network: network, tripId: "900001", startDate: "2099-01-01")
        // Then
        #expect(model.stops == trip.stops)
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func loadTripEmptyWhenResponseHasNoTrip() async throws {
        // Given: a service whose trips dict has no entry for the requested key,
        // so the mock returns an empty trip and the model surfaces an empty list.
        let network = MockTrafiklabService(tripsByKey: [:])
        let model = RouteDetailsModel()
        // When
        await model.loadTrip(network: network, tripId: "900001", startDate: "2099-01-01")
        // Then
        #expect(model.stops == [])
        #expect(model.failure == nil)
    }

    @Test func loadTripNetworkError() async throws {
        // Given: a network with no handlers throws NoResponseConfigured, which
        // surfaces as a failure rather than an empty success.
        let network = MockNetwork()
        let model = RouteDetailsModel()
        // When
        await model.loadTrip(network: network, tripId: "900001", startDate: "2099-01-01")
        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
        #expect(model.isLoading == false)
    }

    @Test func loadTripInvalidJSON() async throws {
        // Given: a handler that returns non-matching JSON for the trips path.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.contains("/trips/") == true {
                return MockNetwork.makeResponse(json: #"{"invalid":"json"}"#, statusCode: 200)
            }
            return nil
        }
        let model = RouteDetailsModel()
        // When
        await model.loadTrip(network: network, tripId: "900001", startDate: "2099-01-01")
        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
    }

    // MARK: - RouteDetails bridge

    @Test func routeDetailsNilWithoutTrip() {
        let departure = StopDetailsModelTests.departure(scheduled: "2099-01-01T12:00:00")
        #expect(departure.routeDetails == nil)
    }

    @Test func routeDetailsCarriesTripRefAndPresentation() throws {
        let departure = StopDetailsModelTests.departure(
            tripId: "900001",
            scheduled: "2099-01-01T12:00:00",
            designation: "3",
            direction: "Ropsten",
            isRealtime: true,
            delay: 180
        )
        let route = try #require(departure.routeDetails)
        #expect(route.tripId == "900001")
        #expect(route.startDate == "2099-01-01")
        #expect(route.lineLabel == "3")
        #expect(route.direction == "Ropsten")
        #expect(route.delayMinutes?.minutes == 3)
    }

    // MARK: - TripStop presentation

    @Test func tripStopDatePrefersRealtime() throws {
        let stop = Self.stop(
            scheduled: "2099-01-01T12:00:00",
            realtime: "2099-01-01T12:03:00"
        )
        let date = try #require(stop.date)
        let calendar = Calendar(identifier: .gregorian)
        let minute = calendar.dateComponents([.minute], from: date).minute
        #expect(minute == 3)
    }

    @Test func tripStopDelayMinutesNilWithoutRealtime() {
        let stop = Self.stop(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: false,
            delay: 180
        )
        #expect(stop.delayMinutes == nil)
    }

    @Test func tripStopDelayMinutesRoundsPositiveUp() {
        let stop = Self.stop(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: true,
            delay: 181
        )
        #expect(stop.delayMinutes?.minutes == 4)
    }

    // MARK: - Schedule helpers

    @Test func currentStopIndexIsFirstUnpassedStop() {
        let now = Date()
        let stops = [
            Self.stop(scheduled: Self.past(now, minutes: 10)),
            Self.stop(scheduled: Self.past(now, minutes: 2)),
            Self.stop(scheduled: Self.future(now, minutes: 6)),
            Self.stop(scheduled: Self.future(now, minutes: 13))
        ]
        #expect(stops.currentStopIndex(now: now) == .betweenStops(before: 1, after: 2))
        #expect(stops.isPassed(at: 0, now: now) == true)
        #expect(stops.isPassed(at: 1, now: now) == true)
        #expect(stops.isPassed(at: 2, now: now) == false)
        #expect(stops.isPassed(at: 3, now: now) == false)
    }

    @Test func currentStopIndexNilWhenAllPassed() {
        let now = Date()
        let stops = [
            Self.stop(scheduled: Self.past(now, minutes: 10)),
            Self.stop(scheduled: Self.past(now, minutes: 2))
        ]
        #expect(stops.currentStopIndex(now: now) == nil)
        #expect(stops.isPassed(at: 0, now: now) == true)
    }

    @Test func currentStopIndexNilForEmptySchedule() {
        let stops: [TripStop] = []
        #expect(stops.currentStopIndex() == nil)
    }

    // MARK: - Helpers

    /// Builds a `TripStop` with sensible defaults for tests.
    static func stop(
        id: String = "1",
        name: String? = "Test",
        scheduled: String? = "2099-01-01T12:00:00",
        realtime: String? = nil,
        isRealtime: Bool? = nil,
        delay: Int? = nil,
        canceled: Bool? = nil
    ) -> TripStop {
        TripStop(
            id: id,
            name: name,
            lat: nil,
            lon: nil,
            scheduled: try! scheduled.map(LocalDate.init(string:)),
            realtime: try! realtime.map(LocalDate.init(string:)),
            delay: delay,
            canceled: canceled,
            is_realtime: isRealtime
        )
    }

    /// A timestamp `minutes` before `now`, formatted as Trafiklab realtime.
    static func past(_ now: Date, minutes: Int) -> String {
        timestamp(now.addingTimeInterval(TimeInterval(-minutes) * 60))
    }

    /// A timestamp `minutes` after `now`, formatted as Trafiklab realtime.
    static func future(_ now: Date, minutes: Int) -> String {
        timestamp(now.addingTimeInterval(TimeInterval(minutes) * 60))
    }

    /// Formats a `Date` as the Trafiklab realtime format `YYYY-MM-DDTHH:mm:ss`:
    /// local wall-clock time with no time-zone designator, mirroring the format
    /// style `LocalDate` parses with. Emitting UTC (`...Z`) here would be
    /// re-read as local time and shift every stop by the UTC offset.
    static func timestamp(_ date: Date) -> String {
        date.formatted(formatStyle)
    }

    /// The same ISO8601 configuration `LocalDate` uses: current time zone,
    /// full date, whole-second time, no zone designator.
    private static let formatStyle = Date.ISO8601FormatStyle
        .iso8601(timeZone: .current)
        .year()
        .month()
        .day()
        .time(includingFractionalSeconds: false)
}
