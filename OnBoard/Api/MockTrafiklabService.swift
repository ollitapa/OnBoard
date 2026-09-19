import Foundation

/// A mock `NetworkProtocol` that serves canned responses for the Trafiklab
/// endpoints described in `Designs/API-Instructions.md`.
///
/// Every dataset is configured as a multiline JSON string in the endpoint's
/// wire format — the same shape `Trafiklab` decodes — so fixtures read like
/// captured API responses instead of hand-built Swift value trees. Any
/// timestamp string in a fixture may use a relative marker (`"now"`, `"now+2"`,
/// `"now-10"`, in minutes) that is resolved to an absolute Trafiklab timestamp
/// when the service is created, so previews and UI tests always show fresh
/// times; every other string is served verbatim. Malformed fixture JSON traps
/// at creation with the fixture named, so a broken fixture fails loudly
/// rather than silently serving an empty response.
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

    /// The nearby stops returned from the nearby-stops endpoint, decoded from
    /// the `nearbyStops` fixture when the service is created.
    let nearbyStops: [StopLocation]

    /// The departures returned from the Timetables departures endpoint, keyed
    /// by the area id in the request path (`/departures/{areaId}`) and decoded
    /// from the `departuresByAreaId` fixture. An area id with no entry returns
    /// an empty departures list, matching the real API. Defaults to
    /// ``defaultDeparturesJSON`` so previews, the `--mock-network` UI-test
    /// harness, and unit tests all share one canned dataset.
    let departuresByAreaId: [String: [CallAtLocation]]

    /// The trips returned from the Trips endpoint, keyed by `"{tripId}/{startDate}"`
    /// (the path segments after `/trips/`) and decoded from the `tripsByKey`
    /// fixture. A trip id with no entry returns an empty trip, matching the
    /// real API. Defaults to ``defaultTripsJSON`` so the Live Trip screen
    /// renders canned data in previews and UI tests.
    let tripsByKey: [String: Trip]

    /// The stop groups returned from the Stop Lookup name-search endpoint,
    /// decoded from the `stopGroups` fixture and filtered client-side by name
    /// against the request's `{searchValue}` so the mock reflects the real
    /// endpoint's behaviour. Defaults to ``defaultStopGroupsJSON`` so previews,
    /// the `--mock-network` UI-test harness, and unit tests all share one
    /// canned dataset.
    let stopGroups: [StopGroup]

    /// Creates a mock Trafiklab service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - nearbyStops: Multiline JSON for the nearby-stops fixture: an array
    ///     of `StopLocation` objects in ResRobot's wire shape.
    ///   - departuresByAreaId: Multiline JSON for the departures fixture: an
    ///     object keyed by area id, each value an array of `CallAtLocation`
    ///     rows in the Timetables wire shape; area ids with no entry return an
    ///     empty list.
    ///   - tripsByKey: Multiline JSON for the trips fixture: an object keyed by
    ///     `"{tripId}/{startDate}"`, each value a `Trip` in the Trips wire
    ///     shape; trip ids with no entry return an empty trip.
    ///   - stopGroups: Multiline JSON for the Stop Lookup fixture: an array of
    ///     `StopGroup` objects, filtered by name against the search value.
    init(
        baseURL: URL = URL(string: "https://api.resrobot.se")!,
        nearbyStops: String = MockTrafiklabService.defaultNearbyStopsJSON,
        departuresByAreaId: String = MockTrafiklabService.defaultDeparturesJSON,
        tripsByKey: String = MockTrafiklabService.defaultTripsJSON,
        stopGroups: String = MockTrafiklabService.defaultStopGroupsJSON
    ) {
        self.baseURL = baseURL
        self.nearbyStops = Self.decode(
            nearbyStops,
            as: [StopLocation].self,
            fixture: "nearbyStops"
        )
        self.departuresByAreaId = Self.decode(
            departuresByAreaId,
            as: [String: [CallAtLocation]].self,
            fixture: "departuresByAreaId"
        )
        self.tripsByKey = Self.decode(
            tripsByKey,
            as: [String: Trip].self,
            fixture: "tripsByKey"
        )
        self.stopGroups = Self.decode(
            stopGroups,
            as: [StopGroup].self,
            fixture: "stopGroups"
        )
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

    /// Extracts the `{searchValue}` path segment from a Stop Lookup name
    /// search URL (`.../stops/name/{searchValue}`) for the response's `query`
    /// field. Returns `nil` when the segment can't be found.
    private func searchValue(for url: URL) -> String? {
        let segments = url.path.split(separator: "/").map(String.init)
        guard let nameIndex = segments.lastIndex(of: "name"),
              segments.count > nameIndex + 1 else {
            return nil
        }
        // The client percent-encodes the search value into the path segment,
        // so decode it back before filtering.
        return segments[nameIndex + 1].removingPercentEncoding
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

    // MARK: - Fixture decoding

    /// Matches a relative timestamp marker in a fixture: the quoted word `now`
    /// with an optional signed minute offset, e.g. `"now"`, `"now+2"`, `"now-10"`.
    private static let relativeTimestamp = /"now(?:([+-])([0-9]+))?"/

    /// The Trafiklab timestamp format `YYYY-MM-DDTHH:mm:ss` pinned to
    /// Europe/Stockholm, the same configuration `LocalDate` parses with, so a
    /// resolved marker re-reads as the instant it meant.
    private static let timestampStyle = Date.ISO8601FormatStyle
        .iso8601(timeZone: TimeZone(identifier: "Europe/Stockholm")!)
        .year()
        .month()
        .day()
        .time(includingFractionalSeconds: false)

    /// Decodes a multiline-JSON fixture into its wire type, resolving relative
    /// timestamp markers first. Traps on invalid JSON with the fixture named:
    /// a broken fixture is a programming error in the test or preview that
    /// wired it, and a loud failure at creation beats a silently empty
    /// response.
    private static func decode<T: Decodable>(_ json: String, as type: T.Type, fixture: String) -> T {
        let resolved = resolvingRelativeTimestamps(in: json)
        do {
            return try JSONDecoder().decode(T.self, from: Data(resolved.utf8))
        } catch {
            fatalError("MockTrafiklabService: invalid \(fixture) JSON: \(error)")
        }
    }

    /// Replaces every relative timestamp marker (`"now"`, `"now+2"`,
    /// `"now-10"`) in a fixture with an absolute Trafiklab timestamp the given
    /// number of minutes from `now`. Markers match any quoted string in the
    /// fixture, so fixtures must not use those exact spellings as literal
    /// values.
    static func resolvingRelativeTimestamps(in json: String, now: Date = Date()) -> String {
        var resolved = ""
        resolved.reserveCapacity(json.count)
        var cursor = json.startIndex
        for match in json.matches(of: relativeTimestamp) {
            resolved += json[cursor..<match.range.lowerBound]
            let sign = match.output.1?.first == "-" ? -1 : 1
            let minutes = sign * (match.output.2.flatMap { Int($0) } ?? 0)
            let date = now.addingTimeInterval(TimeInterval(minutes) * 60)
            resolved += "\""
            resolved += date.formatted(timestampStyle)
            resolved += "\""
            cursor = match.range.upperBound
        }
        resolved += json[cursor...]
        return resolved
    }

    // MARK: - Default fixtures

    /// A stable set of nearby stops served by default, matching the shape
    /// ResRobot returns (`dist` in meters, `lat`/`lon` as strings).
    static let defaultNearbyStopsJSON = """
        [
            {
                "id": "740000001",
                "extId": "740000001",
                "name": "Medborgarplatsen",
                "lat": "59.3139",
                "lon": "18.0720",
                "dist": 180,
                "weight": 100,
                "products": 1024
            },
            {
                "id": "740000002",
                "extId": "740000002",
                "name": "Slussen",
                "lat": "59.3199",
                "lon": "18.0717",
                "dist": 420,
                "weight": 200,
                "products": 1024
            },
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
        ]
        """

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
    static let defaultDeparturesJSON = """
        {
            "740000001": \(Self.sampleDeparturesJSON),
            "740000002": \(Self.sampleDeparturesJSON)
        }
        """

    /// The default trips served by the Trips endpoint, keyed by
    /// `"{tripId}/{startDate}"`. Each sample departure's `trip` in
    /// ``sampleDeparturesJSON`` references one of these so tapping a row
    /// opens a populated Live Trip screen in previews and UI tests. The stop
    /// times are relative markers (the tram's realtime times shifted by its
    /// 3-minute delay) so the track's passed/current/upcoming states render.
    static let defaultTripsJSON = """
        {
            "900001/2099-01-01": {
                "id": "3",
                "trip_id": "900001",
                "start_date": "2099-01-01",
                "route": {
                    "designation": "3",
                    "transport_mode": "BUS",
                    "direction": "Karolinska sjukhuset"
                },
                "stops": [
                    {
                        "id": "3-0",
                        "name": "Skanstull",
                        "scheduled": "now-10",
                        "realtime": "now-10",
                        "delay": 0,
                        "canceled": false,
                        "is_realtime": false
                    },
                    {
                        "id": "3-1",
                        "name": "Medborgarplatsen",
                        "scheduled": "now+6",
                        "realtime": "now+6",
                        "delay": 0,
                        "canceled": false,
                        "is_realtime": false
                    },
                    {
                        "id": "3-2",
                        "name": "Slussen",
                        "scheduled": "now+13",
                        "realtime": "now+13",
                        "delay": 0,
                        "canceled": false,
                        "is_realtime": false
                    },
                    {
                        "id": "3-3",
                        "name": "Gamla stan",
                        "scheduled": "now+21",
                        "realtime": "now+21",
                        "delay": 0,
                        "canceled": false,
                        "is_realtime": false
                    },
                    {
                        "id": "3-4",
                        "name": "Karolinska sjukhuset",
                        "scheduled": "now+30",
                        "realtime": "now+30",
                        "delay": 0,
                        "canceled": false,
                        "is_realtime": false
                    }
                ]
            },
            "900002/2099-01-01": {
                "id": "7",
                "trip_id": "900002",
                "start_date": "2099-01-01",
                "route": {
                    "designation": "7",
                    "transport_mode": "TRAM",
                    "direction": "Ropsten"
                },
                "stops": [
                    {
                        "id": "7-0",
                        "name": "Skanstull",
                        "scheduled": "now-10",
                        "realtime": "now-7",
                        "delay": 180,
                        "canceled": false,
                        "is_realtime": true
                    },
                    {
                        "id": "7-1",
                        "name": "Medborgarplatsen",
                        "scheduled": "now+6",
                        "realtime": "now+9",
                        "delay": 180,
                        "canceled": false,
                        "is_realtime": true
                    },
                    {
                        "id": "7-2",
                        "name": "Slussen",
                        "scheduled": "now+13",
                        "realtime": "now+16",
                        "delay": 180,
                        "canceled": false,
                        "is_realtime": true
                    },
                    {
                        "id": "7-3",
                        "name": "Gamla stan",
                        "scheduled": "now+21",
                        "realtime": "now+24",
                        "delay": 180,
                        "canceled": false,
                        "is_realtime": true
                    },
                    {
                        "id": "7-4",
                        "name": "Ropsten",
                        "scheduled": "now+30",
                        "realtime": "now+33",
                        "delay": 180,
                        "canceled": false,
                        "is_realtime": true
                    }
                ]
            }
        }
        """

    /// A stable set of stop groups served by default for the Stop Lookup
    /// endpoints, matching the shape the Trafiklab API returns
    /// (`average_daily_stop_times`, `transport_modes`, child `stops`).
    static let defaultStopGroupsJSON = """
        [
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
            },
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
            },
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
        ]
        """
}
