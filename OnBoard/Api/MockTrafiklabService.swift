import Foundation

/// A mock `NetworkProtocol` that serves canned responses for the Trafiklab
/// endpoints described in `Designs/API-Instructions.md`.
///
/// Mirrors `MockNearbyServer`: it responds to the ResRobot nearby-stops path
/// with a JSON-encoded `NearbyStopsResponse`, and throws `NoResponseConfigured`
/// for anything else. Matching is by URL path suffix so the request's query
/// parameters (including the API key) don't affect the response, which keeps
/// the mock usable from tests where `Bundle.main` has no key configured.
///
/// Use it directly as the network injected into a view model, or wrap it in a
/// `CombinedNetwork` route to mix it with other mock servers (as the app's
/// UI-test harness does with `MockNearbyServer`).
struct MockTrafiklabService: NetworkProtocol {

    /// The base URL this server is responsible for (matched by `CombinedNetwork`).
    let baseURL: URL

    /// The nearby stops returned from the nearby-stops endpoint.
    let nearbyStops: [StopLocation]

    /// Creates a mock Trafiklab service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - nearbyStops: The stops to return from the nearby endpoint.
    init(
        baseURL: URL = URL(string: "https://api.resrobot.se")!,
        nearbyStops: [StopLocation] = MockTrafiklabService.defaultNearbyStops
    ) {
        self.baseURL = baseURL
        self.nearbyStops = nearbyStops
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw NoResponseConfigured() }

        if request.httpMethod == "GET", url.path.hasSuffix("location.nearbystops") {
            let payload = NearbyStopsResponse(StopLocation: nearbyStops)
            let data = try JSONEncoder().encode(payload)
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

    /// A stable set of nearby stops used by default in tests, matching the
    /// shape ResRobot returns (`dist` in meters, `lat`/`lon` as strings).
    static let defaultNearbyStops: [StopLocation] = [
        StopLocation(
            rawId: "740000001",
            extId: "740000001",
            name: "Medborgarplatsen",
            lat: "59.3139",
            lon: "18.0720",
            dist: 180,
            weight: 100,
            products: 1024
        ),
        StopLocation(
            rawId: "740000002",
            extId: "740000002",
            name: "Slussen",
            lat: "59.3199",
            lon: "18.0717",
            dist: 420,
            weight: 200,
            products: 1024
        )
    ]
}
