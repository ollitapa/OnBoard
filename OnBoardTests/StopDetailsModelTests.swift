import Testing
import Foundation
@testable import OnBoard

@MainActor
struct StopDetailsModelTests {

    @Test func loadDeparturesSuccess() async throws {
        // Given: a mock serving the shared sample departures for the first
        // nearby stop's area id. The expected rows are decoded from the
        // service's stored fixture so the comparison isn't affected by the
        // fixture's relative timestamps being re-evaluated.
        let network = MockTrafiklabService(
            departuresByAreaId: ["740000001": MockTrafiklabService.sampleDeparturesJSON]
        )
        let expected = try JSONDecoder().decode(
            [CallAtLocation].self,
            from: Data(try #require(network.departuresByAreaId["740000001"]).utf8)
        )
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == expected)
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func loadDeparturesEmptyResponse() async throws {
        // Given: an area id explicitly configured with no departures.
        let network = MockTrafiklabService(departuresByAreaId: ["740000001": "[]"])
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000001")
        // Then
        #expect(model.departures == [])
        #expect(model.failure == nil)
    }

    @Test func loadDeparturesForUnknownAreaIdIsEmpty() async throws {
        // Given: the default mock has departures for some area ids; an area id
        // with no entry returns an empty list rather than throwing, matching the
        // real API's empty window.
        let network = MockTrafiklabService()
        let model = StopDetailsModel()
        // When
        await model.loadDepartures(network: network, areaId: "740000999")
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

    @Test func loadDeparturesSetsLastUpdated() async throws {
        // Given
        let network = MockTrafiklabService(departuresByAreaId: ["740000001": "[]"])
        let model = StopDetailsModel()
        #expect(model.lastUpdated == nil)

        // When
        await model.loadDepartures(network: network, areaId: "740000001")

        // Then: the successful load stamps the update time.
        let lastUpdated = try #require(model.lastUpdated)
        #expect(abs(lastUpdated.timeIntervalSinceNow) < 5)
    }

    @Test func failedLoadDoesNotStampLastUpdated() async throws {
        // Given: a previous successful load stamped the update time.
        let good = MockTrafiklabService(departuresByAreaId: ["740000001": "[]"])
        let model = StopDetailsModel()
        await model.loadDepartures(network: good, areaId: "740000001")
        let stamp = try #require(model.lastUpdated)

        // When: a refresh fails.
        await model.loadDepartures(network: MockNetwork(), areaId: "740000001")

        // Then: the stamp still reflects the last *successful* load.
        #expect(model.lastUpdated == stamp)
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

    // MARK: - Platform filtering

    /// A full departures response envelope with two child stops, only one of
    /// which has departures in the current window.
    nonisolated private static let mixedPlatformsDeparturesJSON = #"""
    {
      "timestamp": "2099-01-01T12:00:00",
      "query": { "queryTime": "2099-01-01T12:00:00" },
      "stops": [
        { "id": "740000001", "name": "Platform A", "lat": 59.31, "lon": 18.07 },
        { "id": "740000002", "name": "Platform B", "lat": 59.32, "lon": 18.08 }
      ],
      "departures": [
        {
          "scheduled": "2099-01-01T12:00:00",
          "route": { "designation": "3", "transport_mode": "BUS", "direction": "Sickla" },
          "stop": { "id": "740000002", "name": "Platform B", "lat": 59.32, "lon": 18.08 },
          "trip": { "trip_id": "900010", "start_date": "2099-01-01" }
        }
      ]
    }
    """#

    @Test func loadDeparturesOmitsPlatformsWithoutDepartures() async throws {
        // Given: two child stops in the response envelope but only one has
        // departures in the current window.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.contains("/departures/") == true {
                return MockNetwork.makeResponse(json: Self.mixedPlatformsDeparturesJSON)
            }
            return nil
        }
        let model = StopDetailsModel()

        // When
        await model.loadDepartures(network: network, areaId: "740000001")

        // Then: only the platform with departures is offered.
        #expect(model.platforms.map(\.id) == ["740000002"])
    }

    @Test func platformsWithoutDeparturesHaveNoDominantTransportMode() {
        // Given: a platform with no departures.
        let platform = StopPlatform(from: TimetableStop(
            id: "740000002", name: "Platform B", lat: 59.32, lon: 18.08,
            area_id: nil, transport_modes: nil, alerts: nil
        ))

        // Then: no dominant mode can be derived.
        #expect(platform.dominantTransportMode(departures: []) == nil)
    }

    @Test func platformWithSingleTransportModeHasDominantMode() {
        // Given: a platform served only by trams.
        let platform = StopPlatform(from: TimetableStop(
            id: "740000002", name: "Platform B", lat: 59.32, lon: 18.08,
            area_id: nil, transport_modes: nil, alerts: nil
        ))
        let departures = [
            Self.departure(tripId: "900010", transportMode: "TRAM", direction: "Ropsten"),
            Self.departure(tripId: "900011", transportMode: "TRAM", direction: "Sickla")
        ].map(Self.atPlatformB)

        // Then: the tram mode is dominant and can label the platform.
        #expect(platform.dominantTransportMode(departures: departures) == "TRAM")
    }

    @Test func platformWithMixedTransportModesHasNoDominantMode() {
        // Given: a platform served by both buses and trams.
        let platform = StopPlatform(from: TimetableStop(
            id: "740000002", name: "Platform B", lat: 59.32, lon: 18.08,
            area_id: nil, transport_modes: nil, alerts: nil
        ))
        let departures = [
            Self.departure(tripId: "900010", transportMode: "BUS", direction: "Sickla"),
            Self.departure(tripId: "900011", transportMode: "TRAM", direction: "Ropsten")
        ].map(Self.atPlatformB)

        // Then: no single mode can label the platform.
        #expect(platform.dominantTransportMode(departures: departures) == nil)
    }

    @Test func dominantTransportModeIgnoresDeparturesAtOtherPlatforms() {
        // Given: trams at this platform and a bus at another platform.
        let platform = StopPlatform(from: TimetableStop(
            id: "740000002", name: "Platform B", lat: 59.32, lon: 18.08,
            area_id: nil, transport_modes: nil, alerts: nil
        ))
        let tram = Self.atPlatformB(
            Self.departure(tripId: "900010", transportMode: "TRAM", direction: "Ropsten")
        )
        var bus = Self.departure(tripId: "900011", transportMode: "BUS", direction: "Sickla")
        bus.stop = TimetableStop(
            id: "740000001", name: "Platform A", lat: 59.31, lon: 18.07,
            area_id: nil, transport_modes: nil, alerts: nil
        )

        // Then: the other platform's bus doesn't break the tram dominance.
        #expect(platform.dominantTransportMode(departures: [tram, bus]) == "TRAM")
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
        #expect(departure.delayMinutes?.minutes == 4)
    }

    @Test func delayMinutesRoundsNegativeDown() {
        let departure = Self.departure(
            scheduled: "2099-01-01T12:00:00",
            isRealtime: true,
            delay: -181
        )
        #expect(departure.delayMinutes?.minutes == -4)
    }

    // MARK: - Helpers

    /// Pins a departure to platform B (`740000002`) so it counts for that
    /// platform in stop-based filtering.
    static func atPlatformB(_ departure: CallAtLocation) -> CallAtLocation {
        var departure = departure
        departure.stop = TimetableStop(
            id: "740000002", name: "Platform B", lat: 59.32, lon: 18.08,
            area_id: nil, transport_modes: nil, alerts: nil
        )
        return departure
    }

    /// Builds a `CallAtLocation` with sensible defaults for tests.
    static func departure(
        tripId: String? = nil,
        scheduled: String = "2099-01-01T12:00:00",
        designation: String? = nil,
        name: String? = nil,
        transportMode: TransportMode? = nil,
        direction: String? = nil,
        isRealtime: Bool? = nil,
        delay: Int? = nil,
        canceled: Bool? = nil
    ) -> CallAtLocation {
        CallAtLocation(
            scheduled: try! LocalDate(string: scheduled),
            realtime: nil,
            delay: delay,
            canceled: canceled,
            is_realtime: isRealtime,
            route: Route(
                designation: designation,
                transport_mode: transportMode,
                transport_mode_code: nil,
                direction: direction,
                name: name,
                origin: nil,
                destination: nil
            ),
            agency: nil,
            trip: tripId.map { TripRef(trip_id: $0, start_date: "2099-01-01", technical_number: nil) },
            stop: nil,
            scheduled_platform: nil,
            realtime_platform: nil,
            alerts: nil
        )
    }
}
