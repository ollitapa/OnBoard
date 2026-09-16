import Foundation

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

/// Launch argument used by UI tests to substitute a mock network for the
/// production `LiveNetwork`. See `mockNetwork()`.
let mockNetworkLaunchArgument = "--mock-network"

/// Builds the `CombinedNetwork` used when `--mock-network` is passed at
/// launch, composing a `MockNearbyServer` over the nearby stops base URL.
func mockNetwork() -> some NetworkProtocol {
    let server = MockNearbyServer()
    return CombinedNetwork(routes: [
        .init(baseURL: server.baseURL, network: server)
    ], fallback: LiveNetwork())
}
