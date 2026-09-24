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

    @Test func loadStopsDropsNonStopHits() async throws {
        // Given: a response where one hit is an address (`CoordLocation`), not
        // a stop. ResRobot mixes the two into the same keyed list.
        let network = MockTrafiklabService(nearbyStops: Self.mixedHitsJSON)
        let model = NearbyModel()

        // When
        await model.loadStops(network: network, latitude: 59.31, longitude: 18.07)

        // Then: the address hit is dropped rather than failing the response.
        #expect(model.stops.count == 1)
        #expect(model.stops.first?.name == "Central Station")
    }

    @Test func loadStopsInvalidJSON() async throws {
        // Given: a handler that returns JSON with a wrong-typed hits array for
        // the nearby path.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.hasSuffix("location.nearbystops") == true {
                return MockNetwork.makeResponse(json: #"{"stopLocationOrCoordLocation":"oops"}"#, statusCode: 200)
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

    @Test func cancelledLoadLeavesLoadingFlagToReplacementTask() async throws {
        // Given: a load in flight whose replacement is already loading. The
        // replacement sets `isLoading` before the cancelled task resumes.
        let network = MockTrafiklabService(nearbyStops: Self.twoStopsJSON)
        let model = NearbyModel()
        model.isLoading = true

        // When: a cancelled task runs the same method (as `.task(id:)` does to
        // the previous coordinate's task when the location changes).
        let cancelled = Task { await model.loadStops(network: network, latitude: 59.31, longitude: 18.07) }
        cancelled.cancel()
        await cancelled.value

        // Then: the cancelled run did not clobber the replacement's flag.
        #expect(model.isLoading == true)
    }

    // MARK: - Distance label

    @Test func distanceLabelFormatsMetersBelowKilometer() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420, distance: 420)
        #expect(stop.distanceLabel == "420 m")
    }

    @Test func distanceLabelFormatsKilometersAbove1000Meters() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420, distance: 1800)
        // Then: kilometers with at most one decimal, in the current locale's
        // number format ("1,8 km" on a Swedish device, "1.8 km" on an English
        // one) — the label formats for the rider's locale, not a fixed one.
        let expected = 1.8.formatted(.number.precision(.fractionLength(0...1))) + " km"
        #expect(stop.distanceLabel == expected)
    }

    @Test func distanceLabelNilWithoutDistance() {
        let stop = Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420)
        #expect(stop.distanceLabel == nil)
    }

    // MARK: - Helpers

    /// A one-stop nearby fixture for tests that need a single known stop.
    static let centralStationJSON = [
        """
        {"StopLocation": {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": 60.1756,
        "lon": 24.9420,
        "dist": 120,
        "weight": 50,
        "products": 0
        }}
        """
    ]

    /// A two-stop nearby fixture for tests that assert on the full mapped list.
    static let twoStopsJSON = [
        """
        {"StopLocation": {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": 60.1756,
        "lon": 24.9420,
        "dist": 120,
        "weight": 50,
        "products": 0
        }}
        """,
        """
        {"StopLocation": {
        "id": "2",
        "extId": "2",
        "name": "Market Square",
        "lat": 60.1699,
        "lon": 24.9384,
        "dist": 300,
        "weight": 40,
        "products": 0
        }}
        """
    ]

    /// A two-hit nearby fixture whose second hit is an address
    /// (`CoordLocation`), not a stop, for the mixed-hit path.
    static let mixedHitsJSON = [
        """
        {"StopLocation": {
        "id": "1",
        "extId": "1",
        "name": "Central Station",
        "lat": 60.1756,
        "lon": 24.9420,
        "dist": 120,
        "weight": 50,
        "products": 0
        }}
        """,
        """
        {"CoordLocation": {
        "id": "2",
        "extId": "2",
        "name": "Bad Fix",
        "lat": 60.1699,
        "lon": 24.9384,
        "dist": 300
        }}
        """
    ]

}
