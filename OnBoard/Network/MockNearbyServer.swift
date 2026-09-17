import Foundation
import CoreLocation

/// A mock `NetworkProtocol` that serves a canned response for the nearby
/// stops endpoint from a fixed base URL, intended for UI tests where the
/// app process can't be injected with a `MockNetwork` directly.
///
/// It responds to any `GET` request whose path ends with `/stops/nearby`
/// with a JSON-encoded array of stops, encoded with the same `Codable`
/// shape the app decodes. Other requests throw `NoResponseConfigured`.
struct MockNearbyServer: NetworkProtocol {

    /// The base URL this server is responsible for (matched by `CombinedNetwork`).
    let baseURL: URL

    /// The stops returned for the nearby endpoint.
    let stops: [Stop]

    /// Creates a mock nearby server.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - stops: The stops to return from the nearby endpoint.
    init(baseURL: URL = URL(string: "https://api.example.com")!, stops: [Stop] = MockNearbyServer.defaultStops) {
        self.baseURL = baseURL
        self.stops = stops
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw NoResponseConfigured() }

        if request.httpMethod == "GET", url.path.hasSuffix("/stops/nearby") {
            let data = try JSONEncoder().encode(stops)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }

        throw NoResponseConfigured()
    }

    /// A stable set of stops used by default in tests.
    static let defaultStops: [Stop] = [
        Stop(id: "ui-1", name: "Central Station", latitude: 60.1756, longitude: 24.9420),
        Stop(id: "ui-2", name: "Market Square", latitude: 60.1699, longitude: 24.9384)
    ]
}

/// Builds the `CombinedNetwork` used when `--mock-network` is passed at
/// launch, composing a `MockTrafiklabService` over both the ResRobot and
/// Trafiklab realtime base URLs so the nearby view (ResRobot
/// `location.nearbystops`) and the stop details view (realtime
/// `departures/{areaId}`) are served canned data instead of making real
/// network requests. `MockTrafiklabService()` already defaults to the shared
/// canned nearby stops and per-stop departures, so this needs no setup.
func mockNetwork() -> some NetworkProtocol {
    let server = MockTrafiklabService()
    return CombinedNetwork(routes: [
        .init(baseURL: server.baseURL, network: server),
        .init(
            baseURL: URL(string: "https://realtime-api.trafiklab.se")!,
            network: server
        )
    ], fallback: LiveNetwork())
}

/// Builds a pre-authorized `LocationAuthorization` delivering a fixed
/// Stockholm coordinate, for previews and tests that need the Nearby tab to
/// render its stops without a real CoreLocation permission prompt. Mirrors the
/// `--skip-location-permission` launch-argument path but usable directly.
@MainActor
func previewLocationAuthorization() -> LocationAuthorization {
    let manager = FixedLocationManager(
        authorizationStatus: .authorizedWhenInUse,
        coordinate: CLLocationCoordinate2D(latitude: 59.31, longitude: 18.07)
    )
    let model = LocationAuthorization(manager: manager)
    model.startUpdating()
    return model
}
