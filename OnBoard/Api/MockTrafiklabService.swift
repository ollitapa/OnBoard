import Foundation

/// A mock `NetworkProtocol` that serves canned responses for the Trafiklab
/// endpoints described in `Designs/API-Instructions.md`.
///
/// Mirrors `MockNearbyServer`: it responds to the ResRobot nearby-stops path
/// with a JSON-encoded `NearbyStopsResponse` and to the Trafiklab Timetables
/// departures path with a JSON-encoded `DeparturesResponse`, and throws
/// `NoResponseConfigured` for anything else. Matching is by URL path suffix so
/// the request's query parameters (including the API key) don't affect the
/// response, which keeps the mock usable from tests where `Bundle.main` has
/// no key configured.
///
/// Use it directly as the network injected into a view model, or wrap it in a
/// `CombinedNetwork` route to mix it with other mock servers (as the app's
/// UI-test harness does with `MockNearbyServer`).
struct MockTrafiklabService: NetworkProtocol {

    /// The base URL this server is responsible for (matched by `CombinedNetwork`).
    let baseURL: URL

    /// The nearby stops returned from the nearby-stops endpoint.
    let nearbyStops: [StopLocation]

    /// The departures returned from the Timetables departures endpoint, keyed
    /// by the area id in the request path (`/departures/{areaId}`). An area id
    /// with no entry returns an empty departures list, matching the real API.
    /// Defaults to ``defaultDeparturesByAreaId`` so previews, the `--mock-network`
    /// UI-test harness, and unit tests all share one canned dataset.
    let departuresByAreaId: [String: [CallAtLocation]]

    /// The stop groups returned from the Stop Lookup name-search endpoint,
    /// filtered client-side by name against the request's `{searchValue}` so
    /// the mock reflects the real endpoint's behaviour. Defaults to
    /// ``defaultStopGroups`` so previews, the `--mock-network` UI-test harness,
    /// and unit tests all share one canned dataset.
    let stopGroups: [StopGroup]

    /// Creates a mock Trafiklab service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - nearbyStops: The stops to return from the nearby endpoint.
    ///   - departuresByAreaId: The departures to return per area id from the
    ///     departures endpoint; area ids with no entry return an empty list.
    ///   - stopGroups: The stop groups to return from the Stop Lookup name
    ///     search endpoint, filtered by name against the search value.
    init(
        baseURL: URL = URL(string: "https://api.resrobot.se")!,
        nearbyStops: [StopLocation] = MockTrafiklabService.defaultNearbyStops,
        departuresByAreaId: [String: [CallAtLocation]] = MockTrafiklabService.defaultDeparturesByAreaId,
        stopGroups: [StopGroup] = MockTrafiklabService.defaultStopGroups
    ) {
        self.baseURL = baseURL
        self.nearbyStops = nearbyStops
        self.departuresByAreaId = departuresByAreaId
        self.stopGroups = stopGroups
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

        if request.httpMethod == "GET", url.path.contains("/stops/name/") {
            let groups = self.stopGroups(for: url)
            let payload = NationalStopGroupResponse(
                timestamp: "2099-01-01T12:00:00",
                query: NationalStopGroupResponse.StopLookupQuery(
                    queryTime: "2099-01-01T12:00:00",
                    query: self.searchValue(for: url)
                ),
                stop_groups: groups
            )
            let data = try JSONEncoder().encode(payload)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }

        if request.httpMethod == "GET", url.path.hasSuffix("/stops/list") {
            let payload = NationalStopGroupResponse(
                timestamp: "2099-01-01T12:00:00",
                query: NationalStopGroupResponse.StopLookupQuery(
                    queryTime: "2099-01-01T12:00:00",
                    query: nil
                ),
                stop_groups: stopGroups
            )
            let data = try JSONEncoder().encode(payload)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }

        if request.httpMethod == "GET", url.path.contains("/departures/") {
            let departures = self.departures(for: url)
            let payload = DeparturesResponse(
                timestamp: "2099-01-01T12:00:00",
                query: TimetableQuery(queryTime: "2099-01-01T12:00:00", query: nil),
                stops: [],
                departures: departures
            )
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

    /// Extracts the `{areaId}` path segment from a departures URL
    /// (`.../departures/{areaId}` or `.../departures/{areaId}/{time}`) and
    /// returns the configured departures for it, defaulting to empty.
    private func departures(for url: URL) -> [CallAtLocation] {
        let segments = url.path.split(separator: "/").map(String.init)
        guard let departuresIndex = segments.lastIndex(of: "departures"),
              segments.count > departuresIndex + 1 else {
            return []
        }
        let areaId = segments[departuresIndex + 1]
        return departuresByAreaId[areaId] ?? []
    }

    /// Extracts the `{searchValue}` path segment from a Stop Lookup name
    /// search URL (`.../stops/name/{searchValue}`) for the response's `query`
    /// field. Returns `nil` when the segment can't be found.
    private func searchValue(for url: URL) -> String? {
        let segments = url.path.split(separator: "/").map(String.init)
        guard let nameIndex = segments.lastIndex(of: "name"),
              segments.count > nameIndex + 1 else {
            return nil
        }
        return segments[nameIndex + 1]
    }

    /// Extracts the `{searchValue}` path segment from a Stop Lookup name search
    /// URL (`.../stops/name/{searchValue}`) and returns the configured stop
    /// groups whose name contains it (case-insensitive). An empty filter returns
    /// all groups, matching the real endpoint's broadest match.
    private func stopGroups(for url: URL) -> [StopGroup] {
        guard let value = searchValue(for: url), !value.isEmpty else {
            return stopGroups
        }
        let needle = value.lowercased()
        return stopGroups.filter { $0.name.lowercased().contains(needle) }
    }

    /// A stable set of stop groups used by default for the Stop Lookup name
    /// search endpoint, matching the shape the Trafiklab API returns
    /// (`average_daily_stop_times`, `transport_modes`, child `stops`).
    static let defaultStopGroups: [StopGroup] = [
        StopGroup(
            id: "740000001",
            name: "Medborgarplatsen",
            area_type: "META_STOP",
            average_daily_stop_times: 850,
            transport_modes: ["BUS", "METRO", "TRAM"],
            stops: [
                StopRef(id: "740000001", name: "Medborgarplatsen", lat: 59.3139, lon: 18.0720)
            ]
        ),
        StopGroup(
            id: "740000002",
            name: "Slussen",
            area_type: "META_STOP",
            average_daily_stop_times: 1200,
            transport_modes: ["BUS", "METRO", "TRAM", "BOAT"],
            stops: [
                StopRef(id: "740000002", name: "Slussen", lat: 59.3199, lon: 18.0717)
            ]
        ),
        StopGroup(
            id: "740000004",
            name: "Odenplan",
            area_type: "META_STOP",
            average_daily_stop_times: 950,
            transport_modes: ["BUS", "METRO", "TRAIN"],
            stops: [
                StopRef(id: "740000004", name: "Odenplan", lat: 59.3429, lon: 18.0496)
            ]
        )
    ]

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
        ),
        StopLocation(
            rawId: "740000003",
            extId: "740000003",
            name: "Folkungagatan",
            lat: "59.3128",
            lon: "18.0760",
            dist: 550,
            weight: 30,
            products: 1024
        )
    ]

    /// The default departures served per area id, keyed to ``defaultNearbyStops``
    /// by their `extId`. The first two stops share the sample rows; the third
    /// (`Folkungagatan`) is intentionally absent so its board shows the empty
    /// state. A computed property so the relative timestamps stay fresh.
    static var defaultDeparturesByAreaId: [String: [CallAtLocation]] {
        let rows = sampleDepartures
        return [
            "740000001": rows,
            "740000002": rows
        ]
    }

    /// A handful of departures exercising the row variants the Stop board
    /// renders: an on-time bus, a delayed tram, and a cancelled metro.
    static var sampleDepartures: [CallAtLocation] {
        [
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 2),
                realtime: Self.futureTimestamp(minutesFromNow: 2),
                delay: 0,
                canceled: false,
                is_realtime: true,
                route: Route(designation: "3", transport_mode: "BUS", direction: "Karolinska sjukhuset", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            ),
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 5),
                realtime: Self.futureTimestamp(minutesFromNow: 8),
                delay: 180,
                canceled: false,
                is_realtime: true,
                route: Route(designation: "7", transport_mode: "TRAM", direction: "Ropsten", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            ),
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 9),
                realtime: nil,
                delay: nil,
                canceled: true,
                is_realtime: false,
                route: Route(designation: "T14", transport_mode: "METRO", direction: "Fruängen", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            )
        ]
    }

    /// Formats a timestamp `minutesFromNow` minutes ahead as the Trafiklab
    /// realtime format `YYYY-MM-DDTHH:mm:ss` in the current time zone.
    static func futureTimestamp(minutesFromNow: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutesFromNow) * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
