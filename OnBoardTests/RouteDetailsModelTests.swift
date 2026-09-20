import Testing
import Foundation
@testable import OnBoard

@MainActor
struct RouteDetailsModelTests {

    @Test func loadTripSuccess() async throws {
        // Given: a canned trip keyed by the same trip id / start date the model
        // requests. The expected calls are decoded from the service's stored
        // fixture so the comparison isn't affected by the fixture's relative
        // timestamps being re-evaluated.
        let network = MockTrafiklabService(tripsByKey: MockTrafiklabService.defaultTripsByKeyJSON)
        let fixture = try #require(network.tripsByKey["900001/2099-01-01"])
        let response = try JSONDecoder().decode(TripResponse.self, from: Data(fixture.utf8))
        let model = RouteDetailsModel()
        // When
        await model.loadTrip(network: network, tripId: "900001", startDate: "2099-01-01")
        // Then
        #expect(model.calls == response.calls)
        #expect(model.rows == model.calls.stopRows())
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
        #expect(model.calls == [])
        #expect(model.rows == [])
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
        #expect(model.calls == [])
        #expect(model.rows == [])
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
        #expect(model.calls == [])
        #expect(model.rows == [])
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

    // MARK: - TripCall presentation

    @Test func tripCallDatePrefersRealtimeDeparture() throws {
        let call = Self.call(
            scheduledDeparture: "2099-01-01T12:00:00",
            realtimeDeparture: "2099-01-01T12:03:00"
        )
        let date = try #require(call.date)
        let calendar = Calendar(identifier: .gregorian)
        let minute = calendar.dateComponents([.minute], from: date).minute
        #expect(minute == 3)
    }

    @Test func tripCallDateFallsBackToArrivalAtFinalStop() throws {
        let call = Self.call(
            scheduledArrival: "2099-01-01T12:00:00",
            realtimeArrival: "2099-01-01T12:05:00",
            scheduledDeparture: nil,
        )
        let date = try #require(call.date)
        let calendar = Calendar(identifier: .gregorian)
        let minute = calendar.dateComponents([.minute], from: date).minute
        #expect(minute == 5)
    }

    @Test func tripCallDelayMinutesNilWithoutRealtime() {
        let call = Self.call(
            scheduledDeparture: "2099-01-01T12:00:00",
            departureDelay: 180,
            isRealtime: false,
        )
        #expect(call.delayMinutes == nil)
    }

    @Test func tripCallDelayMinutesRoundsPositiveUp() {
        let call = Self.call(
            scheduledDeparture: "2099-01-01T12:00:00",
            departureDelay: 181,
            isRealtime: true,
        )
        #expect(call.delayMinutes?.minutes == 4)
    }

    @Test func tripCallCanceledFlagsEitherHalf() {
        #expect(Self.call(departureCanceled: true).isCanceled)
        #expect(Self.call(arrivalCanceled: true).isCanceled)
        #expect(!Self.call().isCanceled)
    }

    // MARK: - Schedule helpers

    @Test func currentStopIndexIsFirstUnpassedStop() {
        let now = Date()
        let calls = [
            Self.call(scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(scheduledDeparture: Self.past(now, minutes: 2)),
            Self.call(scheduledDeparture: Self.future(now, minutes: 6)),
            Self.call(scheduledDeparture: Self.future(now, minutes: 13))
        ]
        #expect(calls.currentStopIndex(now: now) == .betweenStops(before: 1, after: 2))
        #expect(calls.stopRows(now: now).map(\.isPassed) == [true, true, false, false])
    }

    @Test func currentStopIndexAtStopWithinWindow() {
        let now = Date()
        // The vehicle is standing at stop 1, which departs right now.
        let calls = [
            Self.call(scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(scheduledDeparture: Self.future(now, minutes: 0)),
            Self.call(scheduledDeparture: Self.future(now, minutes: 20))
        ]
        #expect(calls.currentStopIndex(now: now) == .atStop(index: 1))
        #expect(calls.stopRows(now: now).map(\.isPassed) == [true, false, false])
    }

    @Test func currentStopIndexSnapsToNextStopWithinItsWindow() {
        let now = Date()
        // Stop 1 departs 10 seconds from now, so `now` sits inside stop 1's
        // own ±30 s window even though the previous stop departed 2 minutes
        // ago — the "snaps to next stop" case from API-Instructions §5.4. The
        // window must be built from the next stop's date, not the previous
        // stop's.
        let calls = [
            Self.call(scheduledDeparture: Self.past(now, minutes: 2)),
            Self.call(scheduledDeparture: Self.timestamp(now.addingTimeInterval(10))),
            Self.call(scheduledDeparture: Self.future(now, minutes: 20))
        ]
        #expect(calls.currentStopIndex(now: now) == .atStop(index: 1))
        #expect(calls.stopRows(now: now).map(\.isPassed) == [true, false, false])
    }

    @Test func currentStopIndexNilWhenAllPassed() {
        let now = Date()
        let calls = [
            Self.call(scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(scheduledDeparture: Self.past(now, minutes: 2))
        ]
        #expect(calls.currentStopIndex(now: now) == nil)
        #expect(calls.stopRows(now: now).map(\.isPassed) == [true, true])
    }

    @Test func currentStopIndexNilForEmptySchedule() {
        let calls: [TripCall] = []
        #expect(calls.currentStopIndex() == nil)
    }

    @Test func stopRowsCarryPrecomputedPresentationState() {
        let now = Date()
        // The vehicle is between stop 1 and stop 2, so stop 2 is the target.
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.past(now, minutes: 2)),
            Self.call(stopId: "2", name: "Third", scheduledDeparture: Self.future(now, minutes: 6)),
            Self.call(stopId: "3", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows.map(\.name) == ["First", "Second", "Third", "Final"])
        #expect(rows.map(\.isPassed) == [true, true, false, false])
        #expect(rows.map(\.isTarget) == [false, false, true, false])
        #expect(rows.map(\.isCurrent) == [false, false, false, false])
        #expect(rows.map(\.isBetweenStops) == [false, false, true, false])
        #expect(rows.map(\.isFirst) == [true, false, false, false])
        #expect(rows.map(\.isFinal) == [false, false, false, true])
        #expect(rows.last?.subtitle == "Final stop")
    }

    @Test func stopRowsSubtitleCountsDownAtTargetStop() {
        let now = Date()
        // The vehicle is between stop 0 and stop 1, which it reaches in 5
        // minutes, so the target row carries the countdown.
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.future(now, minutes: 5)),
            Self.call(stopId: "2", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows[1].subtitle == "Arriving in 5 min")
        #expect(rows.map(\.isTarget) == [false, true, false])
    }

    @Test func stopRowsClearBetweenStopsWhenVehicleIsAtStop() {
        let now = Date()
        // The vehicle is standing at stop 1, which departs right now, so no
        // row carries the between-stops flag even though one is the target.
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.future(now, minutes: 0)),
            Self.call(stopId: "2", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows.map(\.isTarget) == [false, true, false])
        #expect(rows.map(\.isBetweenStops) == [false, false, false])
        #expect(rows[1].subtitle == "Departing now")
    }

    @Test func stopRowsSubtitleNeverSaysDepartingWhileBetweenStops() {
        let now = Date()
        // The vehicle is rolling towards stop 1, which it reaches in 40
        // seconds: outside the at-stop window but inside the last minute,
        // which used to truncate to "Departing now" — a vehicle still between
        // stops can't be departing. The countdown rounds up to the arrival
        // and only switches once the position says the vehicle is at the
        // stop.
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 2)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.timestamp(now.addingTimeInterval(40))),
            Self.call(stopId: "2", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows.map(\.isBetweenStops) == [false, true, false])
        #expect(rows[1].subtitle == "Arriving in 1 min")
    }

    @Test func stopRowsSubtitleSaysArrivingNowJustBeforeTheStopWindow() {
        let now = Date()
        // Ten seconds out is still before the ±30 s at-stop window, so the
        // vehicle is officially between stops and the subtitle reads
        // "Arriving now" rather than "Departing now".
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 2)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.timestamp(now.addingTimeInterval(10))),
            Self.call(stopId: "2", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows[1].isBetweenStops)
        #expect(rows[1].subtitle == "Arriving now")
    }

    @Test func stopRowsTargetIsTheRowTheMarkerSitsOn() {
        let now = Date()
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(stopId: "1", name: "Second", scheduledDeparture: Self.future(now, minutes: 5)),
            Self.call(stopId: "2", name: "Final", scheduledDeparture: Self.future(now, minutes: 13))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows.target?.name == "Second")
    }

    @Test func stopRowsTargetNilWhenVehicleIsOffTheTrack() {
        let now = Date()
        let calls = [
            Self.call(stopId: "0", name: "First", scheduledDeparture: Self.past(now, minutes: 10)),
            Self.call(stopId: "1", name: "Final", scheduledDeparture: Self.past(now, minutes: 2))
        ]
        let rows = calls.stopRows(now: now)
        #expect(rows.target == nil)
    }

    // MARK: - Helpers

    /// Builds a `TripCall` with sensible defaults for tests.
    static func call(
        stopId: String = "1",
        name: String? = "Test",
        scheduledArrival: String? = nil,
        realtimeArrival: String? = nil,
        arrivalDelay: Int? = nil,
        arrivalCanceled: Bool? = nil,
        scheduledDeparture: String? = "2099-01-01T12:00:00",
        realtimeDeparture: String? = nil,
        departureDelay: Int? = nil,
        departureCanceled: Bool? = nil,
        isRealtime: Bool? = nil
    ) -> TripCall {
        TripCall(
            scheduledArrival: try! scheduledArrival.map(LocalDate.init(string:)),
            realtimeArrival: try! realtimeArrival.map(LocalDate.init(string:)),
            arrivalDelay: arrivalDelay,
            arrivalCanceled: arrivalCanceled,
            scheduledDeparture: try! scheduledDeparture.map(LocalDate.init(string:)),
            realtimeDeparture: try! realtimeDeparture.map(LocalDate.init(string:)),
            departureDelay: departureDelay,
            departureCanceled: departureCanceled,
            stop: TimetableStop(
                id: stopId,
                name: name ?? "",
                lat: 0,
                lon: 0,
                area_id: nil,
                transport_modes: nil,
                alerts: nil
            ),
            scheduled_platform: nil,
            realtime_platform: nil,
            alerts: nil,
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
