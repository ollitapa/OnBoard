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

    /// The trips returned from the Trips endpoint, keyed by `"{tripId}/{startDate}"`
    /// (the path segments after `/trips/`). A trip id with no entry returns an
    /// empty trip, matching the real API. Defaults to ``defaultTripsByKey`` so
    /// the Live Trip screen renders canned data in previews and UI tests.
    let tripsByKey: [String: Trip]

    /// Creates a mock Trafiklab service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - nearbyStops: The stops to return from the nearby endpoint.
    ///   - departuresByAreaId: The departures to return per area id from the
    ///     departures endpoint; area ids with no entry return an empty list.
    init(
        baseURL: URL = URL(string: "https://api.resrobot.se")!,
        nearbyStops: [StopLocation] = MockTrafiklabService.defaultNearbyStops,
        departuresByAreaId: [String: [CallAtLocation]] = MockTrafiklabService.defaultDeparturesByAreaId,
        tripsByKey: [String: Trip] = MockTrafiklabService.defaultTripsByKey
    ) {
        self.baseURL = baseURL
        self.nearbyStops = nearbyStops
        self.departuresByAreaId = departuresByAreaId
        self.tripsByKey = tripsByKey
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

        if request.httpMethod == "GET", url.path.contains("/trips/") {
            let trip = self.trip(for: url)
            let payload = TripResponse(
                timestamp: "2099-01-01T12:00:00",
                query: TripResponse.TripQuery(queryTime: "2099-01-01T12:00:00", query: nil),
                trip: trip
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

    /// Extracts the `{tripId}/{startDate}` key from a trips URL
    /// (`.../trips/{tripId}/{startDate}`) and returns the configured trip for
    /// it, defaulting to an empty trip.
    private func trip(for url: URL) -> Trip? {
        let segments = url.path.split(separator: "/").map(String.init)
        guard let tripsIndex = segments.lastIndex(of: "trips"),
              segments.count > tripsIndex + 2 else {
            return nil
        }
        let key = "\(segments[tripsIndex + 1])/\(segments[tripsIndex + 2])"
        return tripsByKey[key] ?? Trip(stops: [])
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

    /// The default trips served by the Trips endpoint, keyed by
    /// `"{tripId}/{startDate}"`. Each sample departure's `trip` references one of
    /// these so tapping a row opens a populated Live Trip screen in previews and
    /// UI tests. A computed property so the relative stop times stay fresh.
    static var defaultTripsByKey: [String: Trip] {
        [
            "900001/2099-01-01": sampleTrip(routeDesignation: "3", direction: "Karolinska sjukhuset", delaySeconds: 0),
            "900002/2099-01-01": sampleTrip(routeDesignation: "7", direction: "Ropsten", delaySeconds: 180)
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
                trip: TripRef(trip_id: "900001", start_date: "2099-01-01"),
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
                trip: TripRef(trip_id: "900002", start_date: "2099-01-01"),
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

    /// A canned trip exercising the Live Trip track's passed/current/upcoming
    /// states: two stops already passed, the current stop arriving soon, then
    /// upcoming stops ending at the destination. `delaySeconds` shifts every
    /// realtime time by that amount so the delay pill renders in the screen.
    static func sampleTrip(routeDesignation: String, direction: String, delaySeconds: Int) -> Trip {
        let names = ["Skanstull", "Medborgarplatsen", "Slussen", "Gamla stan", direction]
        let offsets = [-10, 6, 13, 21, 30]
        let stops = (0..<names.count).map { index in
            TripStop(
                id: "\(routeDesignation)-\(index)",
                name: names[index],
                lat: nil,
                lon: nil,
                scheduled: Self.futureTimestamp(minutesFromNow: offsets[index]),
                realtime: Self.futureTimestamp(minutesFromNow: offsets[index] + delaySeconds / 60),
                delay: delaySeconds,
                canceled: false,
                is_realtime: delaySeconds != 0
            )
        }
        return Trip(
            id: routeDesignation,
            trip_id: routeDesignation,
            start_date: "2099-01-01",
            stops: stops
        )
    }
}
