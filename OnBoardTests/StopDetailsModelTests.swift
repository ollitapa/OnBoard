import Testing
import Foundation
@testable import OnBoard

@MainActor
struct StopDetailsModelTests {

    @Test func loadDeparturesSuccess() async throws {
        // Given
        let departures = [
            Self.departure(
                tripId: "trip-1",
                scheduled: "2099-01-01T12:00:00",
                designation: "3",
                transportMode: "BUS",
                direction: "Karolinska sjukhuset"
            ),
            Self.departure(
                tripId: "trip-2",
                scheduled: "2099-01-01T12:05:00",
                designation: "T14",
                transportMode: "METRO",
                direction: "Frängen",
                canceled: true
            )
        ]
        let network = MockTrafiklabService(departures: departures)
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == departures)
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func loadDeparturesEmptyResponse() async throws {
        // Given
        let network = MockTrafiklabService(departures: [])
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == [])
        #expect(model.failure == nil)
    }

    @Test func loadDeparturesNetworkError() async throws {
        // Given: a network with no handlers throws NoResponseConfigured, which
        // surfaces as a failure rather than an empty success.
        let network = MockNetwork()
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == [])
        #expect(model.failure != nil)
        #expect(model.isLoading == false)
    }

    @Test func loadDeparturesInvalidJSON() async throws {
        // Given: a handler that returns non-matching JSON for the departures path.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.contains("/departures/") == true {
                return MockNetwork.makeResponse(json: #"{"invalid":"json"}"#, statusCode: 200)
            }
            return nil
        }
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == [])
        #expect(model.failure != nil)
    }

    // MARK: - Presentation helpers

    @Test func lineLabelPrefersDesignation() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            designation: "3",
            name: nil,
            direction: "Destination"
        )
        #expect(departure.lineLabel == "3")
    }

    @Test func lineLabelFallsBackToName() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            designation: nil,
            name: "Saltsjöbanan",
            direction: "Destination"
        )
        #expect(departure.lineLabel == "Saltsjöbanan")
    }

    @Test func lineLabelFallbackToPlaceholder() {
        let departure = Self.departure(scheduled: "2099-01-01T12:00:00")
        #expect(departure.lineLabel == "?")
    }

    @Test func destinationUsesRouteDirection() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            direction: "Karolinska sjukhuset"
        )
        #expect(departure.destination == "Karolinska sjukhuset")
    }

    @Test func destinationEmptyWithoutDirection() {
        let departure = Self.departure(scheduled: "2099-01-01T12:00:00")
        #expect(departure.destination == "")
    }

    @Test func delayMinutesNilWithoutRealtime() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: false,
            delay: 180
        )
        #expect(departure.delayMinutes == nil)
    }

    @Test func delayMinutesNilForZeroDelay() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: true,
            delay: 0
        )
        #expect(departure.delayMinutes == nil)
    }

    @Test func delayMinutesRoundsPositiveUp() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: true,
            delay: 181
        )
        #expect(departure.delayMinutes == 4)
    }

    @Test func delayMinutesRoundsNegativeDown() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: true,
            delay: -181
        )
        #expect(departure.delayMinutes == -4)
    }

    // MARK: - Helpers

    /// Builds a `CallAtLocation` with sensible defaults for tests.
    static func departure(
        tripId: String? = nil,
        scheduled: String = "2099-01-01T12:00:00",
        designation: String? = nil,
        name: String? = nil,
        transportMode: String? = nil,
        direction: String? = nil,
        isRealtime: Bool? = nil,
        delay: Int? = nil,
        canceled: Bool? = nil
    ) -> CallAtLocation {
        CallAtLocation(
            scheduled: scheduled,
            realtime: nil,
            delay: delay,
            canceled: canceled,
            is_realtime: isRealtime,
            route: Route(
                designation: designation,
                transport_mode: transportMode,
                direction: direction,
                name: name
            ),
            agency: nil,
            trip: tripId.map { TripRef(trip_id: $0, start_date: "2099-01-01") },
            stop: nil,
            scheduled_platform: nil,
            realtime_platform: nil,
            alerts: nil
        )
    }
}
