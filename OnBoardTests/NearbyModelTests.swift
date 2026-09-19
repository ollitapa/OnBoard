import Testing
import Foundation
@testable import OnBoard

@MainActor
struct NearbyModelTests {

    @Test func loadStopsSuccess() async throws {
        // Given
        let network = MockTrafiklabService(nearbyStops: Self.twoStopsJSON)

        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then
        let expectedStops = [
            Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420, distance: 120),
            Stop(id: "2", name: "Market Square", latitude: 60.1699, longitude: 24.9384, distance: 300)
        ]
        #expect(model.stops == expectedStops)
        #expect(model.failure == nil)
    }

    @Test func loadStopsEmptyResponse() async throws {
        // Given
        let network = MockTrafiklabService(nearbyStops: [])
        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then
        #expect(model.stops == [])
        #expect(model.failure == nil)
    }

    @Test func loadStopsNetworkError() async throws {
        // Given: a network with no handlers throws NoResponseConfigured, which
        // surfaces as a failure rather than an empty success.
        let network = MockNetwork()
        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
    }

    @Test func loadStopsKeepsStopsOnFailure() async throws {
        // Given: a model that loaded stops, then a network that fails.
        let model = NearbyModel()
        await model.loadStops(
            network: MockTrafiklabService(nearbyStops: Self.centralStationJSON),
            latitude: 59.31,
            longitude: 18.07
        )
        #expect(model.stops.count == 1)

        // When: a refresh with a network that has no handlers fails.
        await model.loadStops(network: MockNetwork(), latitude: 59.31, longitude: 18.07)

        // Then: the failure surfaces and the stale stops are kept for context.
        #expect(model.failure != nil)
        #expect(model.stops.count == 1)
        #expect(model.stops.first?.name == "Central Station")
    }

    @Test func loadStopsClearsFailureOnSuccess() async throws {
        // Given: a failed load left a failure string.
        let model = NearbyModel()
        await model.loadStops(network: MockNetwork(), latitude: 59.31, longitude: 18.07)
        #expect(model.failure != nil)

        // When: a subsequent load succeeds.
        let network = MockTrafiklabService(nearbyStops: [])
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then: the failure is cleared.
        #expect(model.failure == nil)
    }

    @Test func loadStopsSkipsUnparseableCoordinates() async throws {
        // Given: a response where one stop has an unparseable coordinate string.
        let network = MockTrafiklabService(nearbyStops: Self.unparseableCoordinateJSON)
        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then: the malformed stop is skipped rather than placed at (0, 0).
        #expect(model.stops.count == 1)
        #expect(model.stops.first?.name == "Central Station")
    }

    @Test func loadStopsInvalidJSON() async throws {
        // Given: a handler that returns non-matching JSON for the nearby path.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.hasSuffix("location.nearbystops") == true {
                return MockNetwork.makeResponse(json: #"{"invalid":"json"}"#, statusCode: 200)
            }
            return nil
        }
        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
    }

    // MARK: - Distance label

    @Test func distanceLabelFormatsMetersBelowKilometer() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420, distance: 420)
        #expect(stop.distanceLabel == "420 m")
    }

    @Test func distanceLabelFormatsKilometersAbove1000Meters() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420, distance: 1800)
        #expect(stop.distanceLabel == "1,8 km")
    }

    @Test func distanceLabelNilWithoutDistance() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420)
        #expect(stop.distanceLabel == nil)
    }

    // MARK: - Helpers

    /// A one-stop nearby fixture for tests that need a single known stop.
    static let centralStationJSON = [
        """
        {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": "60.1756",
        "lon": "24.9420",
        "dist": 120,
        "weight": 50,
        "products": 0
        }
        """
    ]

    /// A two-stop nearby fixture for tests that assert on the full mapped list.
    static let twoStopsJSON = [
        """
        {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": "60.1756",
        "lon": "24.9420",
        "dist": 120,
        "weight": 50,
        "products": 0
        }
        """,
        """
        {
        "id": "2",
        "extId": "2",
        "name": "Market Square",
        "lat": "60.1699",
        "lon": "24.9384",
        "dist": 300,
        "weight": 40,
        "products": 0
        }
        """
    ]

    /// A two-stop nearby fixture whose second stop has an unparseable
    /// coordinate string, for the malformed-response path.
    static let unparseableCoordinateJSON = [
        """
        {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": "60.1756",
        "lon": "24.9420",
        "dist": 120,
        "weight": 50,
        "products": 0
        }
        """,
        """
        {
        "id": "2",
        "extId": "2",
        "name": "Bad Fix",
        "lat": "not-a-number",
        "lon": "24.9384",
        "dist": 300,
        "weight": 40,
        "products": 0
        }
        """
    ]

}
