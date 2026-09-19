import Foundation

/// A mock `NetworkProtocol` that serves canned responses for the Trafiklab
/// endpoints described in `Designs/API-Instructions.md`.
///
/// Every dataset is configured as JSON strings in the endpoint's wire format
/// — the same shape `Trafiklab` decodes — so fixtures read like captured API
/// responses. The fixtures never round-trip through the API's Swift models or
/// a JSON decoder: the mock stores them as collections of JSON strings
/// (`[String]` for the nearby list, `[String: String]` for the per-area-id,
/// per-trip-key, and name-keyed stop-group configs), picks the entry to serve
/// straight from the dictionary, and either joins the chosen strings into the
/// endpoint's response envelope or serves the stored string verbatim as the
/// full response body (the trips fixture is a complete `TripResponse`).
/// The model under test
/// therefore runs its real production decode path on bytes written exactly
/// like the fixture. Served stop groups come back in name order; the real API
/// orders them busiest-first, a detail the mock doesn't replicate.
///
/// Any timestamp string in a fixture may use a relative marker (`"now"`,
/// `"now+2"`, `"now-10"`, in minutes) that is resolved to an absolute
/// Trafiklab timestamp when the service is created, so previews and UI tests
/// always show fresh times. Malformed fixture JSON traps at creation with the
/// fixture named, so a broken fixture fails loudly rather than silently
/// serving an empty response.
///
/// Mirrors `MockNearbyServer`: it responds to the ResRobot nearby-stops path
/// and to the Trafiklab Stop Lookup, Timetables departures, and Trips paths,
/// and throws `NoResponseConfigured` for anything else. Matching is by URL
/// path so the request's query parameters (including the API key) don't
/// affect the response, which keeps the mock usable from tests where
/// `Bundle.main` has no key configured.
///
/// Use it directly as the network injected into a view model, or wrap it in a
/// `CombinedNetwork` route to mix it with other mock servers (as the app's
/// UI-test harness does with `MockNearbyServer`).
struct MockTrafiklabService: NetworkProtocol {

    /// The base URL this server is responsible for (matched by `CombinedNetwork`).
    let baseURL: URL

    /// The stops served from the nearby-stops endpoint: one JSON string per
    /// `StopLocation`, in ResRobot's wire shape, joined into the
    /// `NearbyStopsResponse` envelope when served. Defaults to
    /// ``defaultNearbyStopsJSON`` so previews, the `--mock-network` UI-test
    /// harness, and unit tests all share one canned dataset.
    let nearbyStops: [String]

    /// The rows served from the Timetables departures endpoint: area id to
    /// a JSON string holding that area's `CallAtLocation` rows in the
    /// Timetables wire shape. An area id with no entry returns an empty
    /// departures list, matching the real API. Defaults to
    /// ``defaultDeparturesByAreaIdJSON`` so previews, the `--mock-network`
    /// UI-test harness, and unit tests all share one canned dataset.
    let departuresByAreaId: [String: String]

    /// The trips served from the Trips endpoint: `"{tripId}/{startDate}"` to
    /// a JSON string holding the full `TripResponse` in the Trips wire shape
    /// (`agency`, `route`, `trip`, and `calls` — one call per stop, with the
    /// arrival/departure pairs the real endpoint sends). A trip id with no
    /// entry returns an empty `calls` list, matching the real API. Defaults
    /// to ``defaultTripsByKeyJSON`` so the Live Trip screen renders canned
    /// data in previews and UI tests.
    let tripsByKey: [String: String]

    /// The stop groups served from the Stop Lookup endpoints: stop group name
    /// to a JSON string holding the `StopGroup` in the Stop Lookup wire shape
    /// (the name repeats inside the JSON, which is fine). The name-search
    /// endpoint picks the entries whose *key* contains the search value
    /// (case-insensitive substring, like the real endpoint) — no searching
    /// inside the JSON strings. Defaults to ``defaultStopGroupsByNameJSON``
    /// so previews, the `--mock-network` UI-test harness, and unit tests all
    /// share one canned dataset.
    let stopGroupsByName: [String: String]

    /// Creates a mock Trafiklab service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - nearbyStops: One JSON string per nearby `StopLocation`, in
    ///     ResRobot's wire shape.
    ///   - departuresByAreaId: Area id to a JSON string of `CallAtLocation`
    ///     rows in the Timetables wire shape; area ids with no entry return
    ///     an empty list.
    ///   - tripsByKey: `"{tripId}/{startDate}"` to a JSON string holding the
    ///     full `TripResponse` in the Trips wire shape (`agency`, `route`,
    ///     `trip`, and `calls`); trip ids with no entry return an empty
    ///     `calls` list.
    ///   - stopGroupsByName: Stop group name to a JSON string holding the
    ///     `StopGroup` in the Stop Lookup wire shape; the name may repeat
    ///     inside the JSON.
    init(
        baseURL: URL = URL(string: "https://api.resrobot.se")!,
        nearbyStops: [String] = MockTrafiklabService.defaultNearbyStopsJSON,
        departuresByAreaId: [String: String] = MockTrafiklabService.defaultDeparturesByAreaIdJSON,
        tripsByKey: [String: String] = MockTrafiklabService.defaultTripsByKeyJSON,
        stopGroupsByName: [String: String] = MockTrafiklabService.defaultStopGroupsByNameJSON
    ) {
        self.baseURL = baseURL
        self.nearbyStops = Self.resolved(nearbyStops, fixture: "nearbyStops")
        self.departuresByAreaId = Self.resolved(departuresByAreaId, fixture: "departuresByAreaId")
        self.tripsByKey = Self.resolved(tripsByKey, fixture: "tripsByKey")
        self.stopGroupsByName = Self.resolved(stopGroupsByName, fixture: "stopGroupsByName")
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw NoResponseConfigured() }

        if request.httpMethod == "GET", url.path.hasSuffix("location.nearbystops") {
            let body = """
            {
              "StopLocation":[\(nearbyStops.joined(separator: ","))]
            }
            """
            return Self.ok(Data(body.utf8), url: url)
        }

        if request.httpMethod == "GET", url.path.contains("/stops/name/") {
            let value = searchValue(for: url)
            let body = """
                {
                  "timestamp":"2099-01-01T12:00:00",
                  "query":{
                    "queryTime":"2099-01-01T12:00:00",
                    "query":\(Self.jsonValue(value))
                  },
                  "stop_groups":[\(servingStopGroups(value).joined(separator: ","))]
                }
                """
            return Self.ok(Data(body.utf8), url: url)
        }

        if request.httpMethod == "GET", url.path.hasSuffix("/stops/list") {
            let body = """
                {
                  "timestamp":"2099-01-01T12:00:00",
                  "query":{
                    "queryTime":"2099-01-01T12:00:00"
                  },
                  "stop_groups":[\(servingStopGroups(nil).joined(separator: ","))]
                }
                """
            return Self.ok(Data(body.utf8), url: url)
        }

        if request.httpMethod == "GET", url.path.contains("/departures/") {
            let rows = departuresByAreaId[areaId(for: url) ?? ""] ?? "[]"
            let body = """
                {
                  "timestamp":"2099-01-01T12:00:00",
                  "query":{
                    "queryTime":"2099-01-01T12:00:00"
                  },
                  "stops":[],
                  "departures":\(rows)
                }
                """
            return Self.ok(Data(body.utf8), url: url)
        }

        if request.httpMethod == "GET", url.path.contains("/trips/") {
            let body = tripsByKey[tripKey(for: url) ?? ""]
                ?? #"{"timestamp":"2099-01-01T12:00:00","calls":[]}"#
            return Self.ok(Data(body.utf8), url: url)
        }

        throw NoResponseConfigured()
    }

    // MARK: - Request paths

    /// The `{areaId}` of a departures URL, or `nil` when the path doesn't
    /// match one.
    private func areaId(for url: URL) -> String? {
        url.path.firstMatch(of: #/departures/([^/]+)/#).map { String($0.output.1) }
    }

    /// The `"{tripId}/{startDate}"` key of a trips URL, or `nil` when the
    /// path doesn't match one.
    private func tripKey(for url: URL) -> String? {
        url.path.firstMatch(of: #/trips/([^/]+)/([^/]+)/#).map {
            "\($0.output.1)/\($0.output.2)"
        }
    }

    /// The `{searchValue}` of a Stop Lookup name search URL, or `nil` when
    /// the path doesn't match one. The client percent-encodes the search
    /// value into the path segment, so decode it back before filtering.
    private func searchValue(for url: URL) -> String? {
        url.path.firstMatch(of: #/stops/name/([^/]+)/#).flatMap {
            $0.output.1.removingPercentEncoding
        }
    }

    // MARK: - Stop Lookup filtering

    /// The stop groups to serve for a name search: the entries whose name key
    /// contains `searchValue` (case-insensitive), or every entry when the
    /// value is missing or empty, in name order. Matching runs on the
    /// dictionary keys, so the group JSON strings are never searched.
    private func servingStopGroups(_ searchValue: String?) -> [String] {
        let needle = searchValue?.lowercased() ?? ""
        return stopGroupsByName
            .filter { needle.isEmpty || $0.key.lowercased().contains(needle) }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    // MARK: - Fixture handling

    /// The Trafiklab timestamp format `YYYY-MM-DDTHH:mm:ss` pinned to
    /// Europe/Stockholm, the same configuration `LocalDate` parses with, so a
    /// resolved marker re-reads as the instant it meant.
    private static let timestampStyle = Date.ISO8601FormatStyle
        .iso8601(timeZone: TimeZone(identifier: "Europe/Stockholm")!)
        .year()
        .month()
        .day()
        .time(includingFractionalSeconds: false)

    /// Resolves each fixture's relative timestamp markers and validates its
    /// JSON at creation, trapping with the fixture named: a broken fixture is
    /// a programming error in the test or preview that wired it, and a loud
    /// failure at creation beats a decoding error surfacing later as the
    /// model's failure string. The validation is a syntax check only — the
    /// fixture string is stored and served exactly as written.
    private static func resolved(_ fixtures: [String], fixture: String) -> [String] {
        fixtures.map { resolved($0, fixture: fixture) }
    }

    /// The `[String: String]` variant of ``resolved(_:fixture:)``, resolving
    /// and validating each value.
    private static func resolved(_ fixtures: [String: String], fixture: String) -> [String: String] {
        fixtures.mapValues { resolved($0, fixture: fixture) }
    }

    /// Resolves one fixture's relative timestamp markers and validates its
    /// JSON syntax, trapping with the fixture named when it doesn't parse.
    private static func resolved(_ json: String, fixture: String) -> String {
        let resolved = resolvingRelativeTimestamps(in: json)
        guard (try? JSONSerialization.jsonObject(with: Data(resolved.utf8))) != nil else {
            fatalError("MockTrafiklabService: invalid \(fixture) JSON")
        }
        return resolved
    }

    /// Replaces every relative timestamp marker (`"now"`, `"now+2"`,
    /// `"now-10"`) in a fixture with an absolute Trafiklab timestamp the given
    /// number of minutes from `now`. Markers match any quoted string in the
    /// fixture, so fixtures must not use those exact spellings as literal
    /// values.
    private static func resolvingRelativeTimestamps(in json: String, now: Date = Date()) -> String {
        json.replacing(/"now(?:([+-])([0-9]+))?"/) { match in
            let sign = match.output.1?.first == "-" ? -1 : 1
            let minutes = sign * (match.output.2.flatMap { Int($0) } ?? 0)
            let date = now.addingTimeInterval(TimeInterval(minutes) * 60)
            return "\"\(date.formatted(timestampStyle))\""
        }
    }

    /// Quotes a string for embedding in a response envelope, escaping the
    /// characters JSON forbids raw inside a string. `nil` becomes `null`.
    private static func jsonValue(_ string: String?) -> String {
        guard let string else { return "null" }
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Wraps a JSON body in a `200` response with a JSON content type.
    private static func ok(_ body: Data, url: URL) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }

    // MARK: - Default fixtures

    /// A stable set of nearby stops served by default, matching the shape
    /// ResRobot returns (`dist` in meters, `lat`/`lon` as strings).
    static let defaultNearbyStopsJSON: [String] = [
        """
        {
            "id": "740000001",
            "extId": "740000001",
            "name": "Medborgarplatsen",
            "lat": "59.3139",
            "lon": "18.0720",
            "dist": 180,
            "weight": 100,
            "products": 1024
        }
        """,
        """
        {
            "id": "740000002",
            "extId": "740000002",
            "name": "Slussen",
            "lat": "59.3199",
            "lon": "18.0717",
            "dist": 420,
            "weight": 200,
            "products": 1024
        }
        """,
        """
        {
            "id": "740000003",
            "extId": "740000003",
            "name": "Folkungagatan",
            "lat": "59.3128",
            "lon": "18.0760",
            "dist": 550,
            "weight": 30,
            "products": 1024
        }
        """
    ]

    /// A handful of departures exercising the row variants the Stop board
    /// renders: an on-time bus, a delayed tram, and a cancelled metro. Their
    /// timestamps are relative markers so previews and UI tests always show
    /// fresh times.
    static let sampleDeparturesJSON = """
        [
            {
                "scheduled": "now+2",
                "realtime": "now+2",
                "delay": 0,
                "canceled": false,
                "is_realtime": true,
                "route": {
                    "designation": "3",
                    "transport_mode": "BUS",
                    "direction": "Karolinska sjukhuset"
                },
                "trip": {
                    "trip_id": "900001",
                    "start_date": "2099-01-01"
                }
            },
            {
                "scheduled": "now+5",
                "realtime": "now+8",
                "delay": 180,
                "canceled": false,
                "is_realtime": true,
                "route": {
                    "designation": "7",
                    "transport_mode": "TRAM",
                    "direction": "Ropsten"
                },
                "trip": {
                    "trip_id": "900002",
                    "start_date": "2099-01-01"
                }
            },
            {
                "scheduled": "now+9",
                "canceled": true,
                "is_realtime": false,
                "route": {
                    "designation": "T14",
                    "transport_mode": "METRO",
                    "direction": "Fruängen"
                }
            }
        ]
        """

    /// The default departures served per area id, keyed to
    /// ``defaultNearbyStopsJSON`` by the stops' `extId`. The first two stops
    /// share ``sampleDeparturesJSON``; the third (`Folkungagatan`) is
    /// intentionally absent so its board shows the empty state.
    static let defaultDeparturesByAreaIdJSON: [String: String] = [
        "740000001": Self.sampleDeparturesJSON,
        "740000002": Self.sampleDeparturesJSON
    ]

    /// The default trips served by the Trips endpoint, keyed by
    /// `"{tripId}/{startDate}"`. Each sample departure's `trip` in
    /// ``sampleDeparturesJSON`` references one of these so tapping a row
    /// opens a populated Live Trip screen in previews and UI tests. The call
    /// times are relative markers (the tram's realtime times shifted by its
    /// 3-minute delay) so the track's passed/current/upcoming states render.
    static let defaultTripsByKeyJSON: [String: String] = [
        "900001/2099-01-01": """
        {
            "timestamp": "2099-01-01T12:00:00",
            "query": {
                "queryTime": "2099-01-01T12:00:00",
                "query": "900001"
            },
            "agency": {
                "id": "505000000000000001",
                "name": "Storstockholms Lokaltrafik",
                "operator": "Nobina"
            },
            "route": {
                "designation": "3",
                "transport_mode_code": 700,
                "transport_mode": "BUS",
                "direction": "Karolinska sjukhuset",
                "origin": { "id": "3-0", "name": "Skanstull" },
                "destination": { "id": "3-4", "name": "Karolinska sjukhuset" }
            },
            "trip": {
                "trip_id": "900001",
                "start_date": "2099-01-01",
                "technical_number": 3
            },
            "calls": [
                {
                    "scheduledArrival": "now-10",
                    "realtimeArrival": "now-10",
                    "arrivalDelay": 0,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now-10",
                    "realtimeDeparture": "now-10",
                    "departureDelay": 0,
                    "departureCanceled": false,
                    "stop": { "id": "3-0", "name": "Skanstull", "lat": 59.3114, "lon": 18.0745 },
                    "is_realtime": false
                },
                {
                    "scheduledArrival": "now+6",
                    "realtimeArrival": "now+6",
                    "arrivalDelay": 0,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+6",
                    "realtimeDeparture": "now+6",
                    "departureDelay": 0,
                    "departureCanceled": false,
                    "stop": { "id": "3-1", "name": "Medborgarplatsen", "lat": 59.3139, "lon": 18.0720 },
                    "is_realtime": false
                },
                {
                    "scheduledArrival": "now+13",
                    "realtimeArrival": "now+13",
                    "arrivalDelay": 0,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+13",
                    "realtimeDeparture": "now+13",
                    "departureDelay": 0,
                    "departureCanceled": false,
                    "stop": { "id": "3-2", "name": "Slussen", "lat": 59.3199, "lon": 18.0717 },
                    "is_realtime": false
                },
                {
                    "scheduledArrival": "now+21",
                    "realtimeArrival": "now+21",
                    "arrivalDelay": 0,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+21",
                    "realtimeDeparture": "now+21",
                    "departureDelay": 0,
                    "departureCanceled": false,
                    "stop": { "id": "3-3", "name": "Gamla stan", "lat": 59.3252, "lon": 18.0711 },
                    "is_realtime": false
                },
                {
                    "scheduledArrival": "now+30",
                    "realtimeArrival": "now+30",
                    "arrivalDelay": 0,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+30",
                    "realtimeDeparture": "now+30",
                    "departureDelay": 0,
                    "departureCanceled": false,
                    "stop": { "id": "3-4", "name": "Karolinska sjukhuset", "lat": 59.3372, "lon": 18.0281 },
                    "is_realtime": false
                }
            ]
        }
        """,
        "900002/2099-01-01": """
        {
            "timestamp": "2099-01-01T12:00:00",
            "query": {
                "queryTime": "2099-01-01T12:00:00",
                "query": "900002"
            },
            "agency": {
                "id": "505000000000000001",
                "name": "Storstockholms Lokaltrafik",
                "operator": "Nobina"
            },
            "route": {
                "designation": "7",
                "transport_mode_code": 900,
                "transport_mode": "TRAM",
                "direction": "Ropsten",
                "origin": { "id": "7-0", "name": "Skanstull" },
                "destination": { "id": "7-4", "name": "Ropsten" }
            },
            "trip": {
                "trip_id": "900002",
                "start_date": "2099-01-01",
                "technical_number": 7
            },
            "calls": [
                {
                    "scheduledArrival": "now-10",
                    "realtimeArrival": "now-7",
                    "arrivalDelay": 180,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now-10",
                    "realtimeDeparture": "now-7",
                    "departureDelay": 180,
                    "departureCanceled": false,
                    "stop": { "id": "7-0", "name": "Skanstull", "lat": 59.3114, "lon": 18.0745 },
                    "is_realtime": true
                },
                {
                    "scheduledArrival": "now+6",
                    "realtimeArrival": "now+9",
                    "arrivalDelay": 180,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+6",
                    "realtimeDeparture": "now+9",
                    "departureDelay": 180,
                    "departureCanceled": false,
                    "stop": { "id": "7-1", "name": "Medborgarplatsen", "lat": 59.3139, "lon": 18.0720 },
                    "is_realtime": true
                },
                {
                    "scheduledArrival": "now+13",
                    "realtimeArrival": "now+16",
                    "arrivalDelay": 180,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+13",
                    "realtimeDeparture": "now+16",
                    "departureDelay": 180,
                    "departureCanceled": false,
                    "stop": { "id": "7-2", "name": "Slussen", "lat": 59.3199, "lon": 18.0717 },
                    "is_realtime": true
                },
                {
                    "scheduledArrival": "now+21",
                    "realtimeArrival": "now+24",
                    "arrivalDelay": 180,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+21",
                    "realtimeDeparture": "now+24",
                    "departureDelay": 180,
                    "departureCanceled": false,
                    "stop": { "id": "7-3", "name": "Gamla stan", "lat": 59.3252, "lon": 18.0711 },
                    "is_realtime": true
                },
                {
                    "scheduledArrival": "now+30",
                    "realtimeArrival": "now+33",
                    "arrivalDelay": 180,
                    "arrivalCanceled": false,
                    "scheduledDeparture": "now+30",
                    "realtimeDeparture": "now+33",
                    "departureDelay": 180,
                    "departureCanceled": false,
                    "stop": { "id": "7-4", "name": "Ropsten", "lat": 59.3269, "lon": 18.0959 },
                    "is_realtime": true
                }
            ]
        }
        """
    ]

    /// A stable set of stop groups served by default for the Stop Lookup
    /// endpoints, matching the shape the Trafiklab API returns
    /// (`average_daily_stop_times`, `transport_modes`, child `stops`), keyed
    /// by the group's name (which repeats inside the JSON).
    static let defaultStopGroupsByNameJSON: [String: String] = [
        "Medborgarplatsen": """
        {
            "id": "740000001",
            "name": "Medborgarplatsen",
            "area_type": "META_STOP",
            "average_daily_stop_times": 850,
            "transport_modes": ["BUS", "METRO", "TRAM"],
            "stops": [
                {
                    "id": "740000001",
                    "name": "Medborgarplatsen",
                    "lat": 59.3139,
                    "lon": 18.0720
                }
            ]
        }
        """,
        "Slussen": """
        {
            "id": "740000002",
            "name": "Slussen",
            "area_type": "META_STOP",
            "average_daily_stop_times": 1200,
            "transport_modes": ["BUS", "METRO", "TRAM", "BOAT"],
            "stops": [
                {
                    "id": "740000002",
                    "name": "Slussen",
                    "lat": 59.3199,
                    "lon": 18.0717
                }
            ]
        }
        """,
        "Odenplan": """
        {
            "id": "740000004",
            "name": "Odenplan",
            "area_type": "META_STOP",
            "average_daily_stop_times": 950,
            "transport_modes": ["BUS", "METRO", "TRAIN"],
            "stops": [
                {
                    "id": "740000004",
                    "name": "Odenplan",
                    "lat": 59.3429,
                    "lon": 18.0496
                }
            ]
        }
        """
    ]
}
