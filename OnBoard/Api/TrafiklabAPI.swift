import Foundation

/// A client for the Trafiklab APIs described in `Designs/API-Instructions.md`.
///
/// Wraps the four endpoints the app needs — Stop Lookup, ResRobot Nearby Stops,
/// Timetables, and Trips (beta) — behind a single struct that depends only on a
/// `NetworkProtocol` for transport. API keys are read from the app's Info.plist
/// (no secrets are committed in source); init takes nothing but the network.
///
/// Both products authenticate via a query-string parameter rather than a header:
/// the realtime APIs use `key`, ResRobot uses `accessId`.
struct Trafiklab {

    /// Base URL for the Trafiklab realtime APIs (Stop Lookup, Timetables, Trips).
    private static let realtimeBase = URL(string: "https://realtime-api.trafiklab.se/v1/")!

    /// Base URL for ResRobot v2.1 (Nearby Stops).
    private static let resrobotBase = URL(string: "https://api.resrobot.se/v2.1/")!

    /// The realtime-API key, read from the app's Info.plist under `TrafiklabRealtimeKey`.
    private let realtimeKey: String

    /// The ResRobot key, read from the app's Info.plist under `TrafiklabResrobotKey`.
    private let resrobotKey: String

    /// The transport used to perform requests.
    private let network: NetworkProtocol

    /// Creates a client backed by the given network.
    /// - Parameter network: The `NetworkProtocol` used to perform requests.
    init(network: some NetworkProtocol) {
        self.network = network
        self.realtimeKey = Self.infoValue(forKey: "TrafiklabRealtimeKey")
        self.resrobotKey = Self.infoValue(forKey: "TrafiklabResrobotKey")
    }

    // MARK: - Stop Lookup (Search screen)

    /// Searches stop groups by name.
    /// - Parameter searchValue: At least one character matched against stop group names.
    /// - Returns: Matching stop groups, busiest first.
    func searchStops(named searchValue: String) async throws -> NationalStopGroupResponse {
        let path = "stops/name/\(searchValue)"
        let request = try realtimeRequest(path: path)
        return try await decode(request)
    }

    /// Lists every known stop group.
    /// - Returns: All stop groups, busiest first.
    func listStops() async throws -> NationalStopGroupResponse {
        let request = try realtimeRequest(path: "stops/list")
        return try await decode(request)
    }

    // MARK: - ResRobot Nearby Stops (Nearby screen)

    /// Returns stops ranked by distance from the given coordinate.
    /// - Parameters:
    ///   - latitude: WGS84 decimal degrees.
    ///   - longitude: WGS84 decimal degrees.
    ///   - maxResults: Result count (default 10, max 1000).
    ///   - radius: Search radius in meters (default 1000, max 10000).
    func nearbyStops(
        latitude: Double,
        longitude: Double,
        maxResults: Int = 10,
        radius: Int = 1000
    ) async throws -> NearbyStopsResponse {
        let endpoint = Self.resrobotBase.appendingPathComponent("location.nearbystops")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw TrafiklabInvalidURL() }
        components.queryItems = [
            URLQueryItem(name: "originCoordLat", value: String(latitude)),
            URLQueryItem(name: "originCoordLong", value: String(longitude)),
            URLQueryItem(name: "accessId", value: resrobotKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "maxNo", value: String(maxResults)),
            URLQueryItem(name: "r", value: String(radius))
        ]
        guard let url = components.url else { throw TrafiklabInvalidURL() }
        let request = URLRequest(url: url)
        return try await decode(request)
    }

    // MARK: - Timetables (Stop board screen)

    /// Fetches departures at an area id, starting "now".
    /// - Parameter areaId: The rikshållplats/meta-stop id (group id, never a child stop id).
    func departures(at areaId: String) async throws -> DeparturesResponse {
        let request = try realtimeRequest(path: "departures/\(areaId)")
        return try await decode(request)
    }

    /// Fetches departures at an area id, starting at the given time.
    /// - Parameters:
    ///   - areaId: The rikshållplats/meta-stop id (group id, never a child stop id).
    ///   - time: `YYYY-MM-DDTHH:mm` (no seconds); the 60-minute window starts here.
    func departures(at areaId: String, from time: String) async throws -> DeparturesResponse {
        let request = try realtimeRequest(path: "departures/\(areaId)/\(time)")
        return try await decode(request)
    }

    /// Fetches arrivals at an area id, starting "now".
    /// - Parameter areaId: The rikshållplats/meta-stop id (group id, never a child stop id).
    func arrivals(at areaId: String) async throws -> ArrivalsResponse {
        let request = try realtimeRequest(path: "arrivals/\(areaId)")
        return try await decode(request)
    }

    /// Fetches arrivals at an area id, starting at the given time.
    /// - Parameters:
    ///   - areaId: The rikshållplats/meta-stop id (group id, never a child stop id).
    ///   - time: `YYYY-MM-DDTHH:mm` (no seconds); the 60-minute window starts here.
    func arrivals(at areaId: String, from time: String) async throws -> ArrivalsResponse {
        let request = try realtimeRequest(path: "arrivals/\(areaId)/\(time)")
        return try await decode(request)
    }

    // MARK: - Trips (Live Trip screen, beta)

    /// Looks up a single trip stop-by-stop.
    /// - Parameters:
    ///   - tripId: The `trip.trip_id` from a `CallAtLocation` on the Timetables response.
    ///   - startDate: The `trip.start_date` from the same `CallAtLocation`.
    func trip(tripId: String, startDate: String) async throws -> TripResponse {
        let request = try realtimeRequest(path: "trips/\(tripId)/\(startDate)")
        return try await decode(request)
    }

    // MARK: - Internals

    /// Builds a GET request against the realtime base, appending the `key` query parameter.
    private func realtimeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: Self.realtimeBase),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw TrafiklabInvalidURL()
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: realtimeKey)]
        guard let resolved = components.url else { throw TrafiklabInvalidURL() }
        return URLRequest(url: resolved)
    }

    /// Performs a request and decodes its JSON body.
    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await network.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Reads a string value from the main bundle's Info.plist.
    private static func infoValue(forKey key: String) -> String {
        (Bundle.main.infoDictionary?[key] as? String) ?? ""
    }
}

/// Errors thrown by `Trafiklab`.
struct TrafiklabInvalidURL: Error { }


// MARK: - Response models

/// Top-level response for Stop Lookup (`NationalStopGroupResponse`).
struct NationalStopGroupResponse: Codable, Equatable {
    var timestamp: String
    var query: StopLookupQuery
    var stop_groups: [StopGroup]

    struct StopLookupQuery: Codable, Equatable {
        var queryTime: String
        var query: String?
    }
}

/// A national stop group / meta-stop returned by Stop Lookup.
struct StopGroup: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var area_type: String
    var average_daily_stop_times: Double
    var transport_modes: [String]
    var stops: [StopRef]
}

/// A child stop reference — never use its `id` for Timetables/Trips calls.
struct StopRef: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
}

/// Top-level response for ResRobot Nearby Stops.
struct NearbyStopsResponse: Codable, Equatable {
    var StopLocation: [StopLocation]
}

/// A nearby stop ranked by distance, returned by ResRobot Nearby Stops.
struct StopLocation: Codable, Equatable, Identifiable {
    /// Use `extId` (the group id) as the stable identifier; the raw `id` is internal.
    var id: String { extId }

    /// Internal ResRobot id — do not use.
    var rawId: String?
    var extId: String
    var name: String
    var lat: String
    var lon: String
    /// Distance from the query point, in meters.
    var dist: Int
    var weight: Int?
    var products: Int?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case extId, name, lat, lon, dist, weight, products
    }
}

/// Top-level response for Trafiklab Timetables departures.
struct DeparturesResponse: Codable, Equatable {
    var timestamp: String
    var query: TimetableQuery
    var stops: [TimetableStop]
    var departures: [CallAtLocation]
}

/// Top-level response for Trafiklab Timetables arrivals.
struct ArrivalsResponse: Codable, Equatable {
    var timestamp: String
    var query: TimetableQuery
    var stops: [TimetableStop]
    var arrivals: [CallAtLocation]
}

/// Query metadata shared by the Timetables responses.
struct TimetableQuery: Codable, Equatable {
    var queryTime: String
    var query: String?
}

/// A physical stop covered by a Timetables area id.
struct TimetableStop: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var transport_modes: [String]?
    var alerts: [Alert]?
}

/// A single departure/arrival row on a stop board.
struct CallAtLocation: Codable, Equatable, Identifiable {
    /// A stable row id derived from the trip; falls back to scheduled time.
    var id: String { trip?.trip_id ?? "\(scheduled)-\(route?.designation ?? "")" }

    var scheduled: String
    var realtime: String?
    /// Delay in seconds; may be negative. `0` when there is no realtime data.
    var delay: Int?
    var canceled: Bool?
    var is_realtime: Bool?
    var route: Route?
    var agency: Agency?
    var trip: TripRef?
    var stop: TimetableStop?
    var scheduled_platform: Platform?
    var realtime_platform: Platform?
    var alerts: [Alert]?
}

/// Route information for a departure/arrival row.
struct Route: Codable, Equatable {
    /// The line-badge number, e.g. "3" or "T14".
    var designation: String?
    /// `BUS` / `METRO` / `TRAM` / `TRAIN` / `TAXI` / `BOAT`.
    var transport_mode: String?
    /// Destination text; may change mid-route.
    var direction: String?
    /// Set only for lines known by name rather than number.
    var name: String?
}

/// Operator branding for a departure/arrival row.
struct Agency: Codable, Equatable {
    var name: String?
    var operator_: String?

    enum CodingKeys: String, CodingKey {
        case name
        case operator_ = "operator"
    }
}

/// Reference to a trip, needed to open the Live Trip screen.
struct TripRef: Codable, Equatable {
    var trip_id: String
    var start_date: String
}

/// A platform/läge, e.g. "Läge C".
struct Platform: Codable, Equatable {
    var id: String?
    var designation: String?
}

/// A service message for a stop or departure.
struct Alert: Codable, Equatable, Identifiable {
    var id: String
    var text: String?
}

/// Top-level response for Trafiklab Trips (beta).
struct TripResponse: Codable, Equatable {
    var timestamp: String
    var query: TripQuery?
    var trip: Trip?

    struct TripQuery: Codable, Equatable {
        var queryTime: String
        var query: String?
    }
}

/// A single trip with its stop-by-stop schedule.
struct Trip: Codable, Equatable, Identifiable {
    var id: String?
    var trip_id: String?
    var start_date: String?
    var stops: [TripStop]
}

/// One scheduled stop along a trip, with delay/ETA per stop.
struct TripStop: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var lat: Double?
    var lon: Double?
    var scheduled: String?
    var realtime: String?
    var delay: Int?
    var canceled: Bool?
    var is_realtime: Bool?
}
