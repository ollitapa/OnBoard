import Foundation

/// A client for the Trafiklab APIs described in `Designs/API-Instructions.md`.
///
/// Wraps the four endpoints the app needs — Stop Lookup, ResRobot Nearby Stops,
/// Timetables, and Trips (beta) — behind a single struct that depends only on a
/// `NetworkProtocol` for transport. API keys are read from the env file bundled
/// with the build (`Secrets.env`, see the README's "API keys" section); a missing
/// key throws when a request is built, surfacing as the caller's load failure
/// rather than an empty-key request.
///
/// Both products authenticate via a query-string parameter rather than a header:
/// the realtime APIs use `key`, ResRobot uses `accessId`.
struct Trafiklab {

    /// Base URL for the Trafiklab realtime APIs (Stop Lookup, Timetables, Trips).
    private static let realtimeBase = URL(string: "https://realtime-api.trafiklab.se/v1/")!

    /// Base URL for ResRobot v2.1 (Nearby Stops).
    private static let resrobotBase = URL(string: "https://api.resrobot.se/v2.1/")!

    /// The app's API keys, read when a request is built so a missing key
    /// surfaces as a load failure instead of an empty-key request.
    private let secrets: Secrets

    /// The transport used to perform requests.
    private let network: NetworkProtocol

    /// Creates a client backed by the given network and the app's bundled keys.
    /// - Parameters:
    ///   - network: The `NetworkProtocol` used to perform requests.
    ///   - secrets: The keys to authenticate with.
    init(network: some NetworkProtocol, secrets: Secrets = Secrets()) {
        self.network = network
        self.secrets = secrets
    }

    // MARK: - Stop Lookup (Search screen)

    /// Searches stop groups by name.
    /// - Parameter searchValue: At least one character matched against stop group names.
    /// - Returns: Matching stop groups, busiest first.
    func searchStops(named searchValue: String) async throws -> NationalStopGroupResponse {
        // Percent-encode the query into the path segment: a raw "/" or "?"
        // in the search text would otherwise split or terminate the path and
        // hit the wrong endpoint.
        guard let encoded = searchValue.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))
        ) else {
            throw TrafiklabInvalidURL()
        }
        let path = "stops/name/\(encoded)"
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
            URLQueryItem(name: "accessId", value: try secrets.resrobotKey),
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
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: try secrets.realtimeKey)]
        guard let resolved = components.url else { throw TrafiklabInvalidURL() }
        return URLRequest(url: resolved)
    }

    private static let decoder = JSONDecoder()

    /// Performs a request and decodes its JSON body.
    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await network.data(for: request)
        return try Self.decoder.decode(T.self, from: data)
    }
}

/// Errors thrown by `Trafiklab`.
struct TrafiklabInvalidURL: Error, Sendable { }


// MARK: - Response models

/// Top-level response for Stop Lookup (`NationalStopGroupResponse`).
struct NationalStopGroupResponse: Codable, Equatable, Sendable {
    var timestamp: String
    var query: StopLookupQuery
    var stop_groups: [StopGroup]

    struct StopLookupQuery: Codable, Equatable, Sendable {
        var queryTime: String
        var query: String?
    }
}

/// A national stop group / meta-stop returned by Stop Lookup.
struct StopGroup: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var area_type: String
    var average_daily_stop_times: Double
    var transport_modes: [TransportMode]
    var stops: [StopRef]
}

/// A child stop reference — never use its `id` for Timetables/Trips calls.
struct StopRef: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
}

/// A named stop reference without coordinates, e.g. a route's origin or
/// destination.
struct StopNameRef: Codable, Equatable, Identifiable, Sendable {
    var id: String?
    var name: String?
}

/// Top-level response for ResRobot Nearby Stops.
struct NearbyStopsResponse: Codable, Equatable, Sendable {
    /// ResRobot's hits, each wrapped in a keyed object naming what matched —
    /// `"StopLocation"` for a stop, `"CoordLocation"` for an address. Absent
    /// when the search found nothing.
    var stopLocationOrCoordLocation: [StopHit]?

    /// The stop hits, unwrapped from their keyed entries; hits that aren't
    /// stops carry no `StopLocation` and are dropped.
    var stops: [StopLocation] {
        (stopLocationOrCoordLocation ?? []).compactMap(\.StopLocation)
    }

    /// A keyed ResRobot hit: `"StopLocation"` for a stop, `"CoordLocation"`
    /// for an address. Only the stop variant is decoded; other keys are
    /// ignored, so a mixed result list never fails the whole response.
    struct StopHit: Codable, Equatable, Sendable {
        var StopLocation: StopLocation?
    }
}

/// A nearby stop ranked by distance, returned by ResRobot Nearby Stops.
struct StopLocation: Codable, Equatable, Identifiable, Sendable {
    /// Use `extId` (the group id) as the stable identifier; the raw `id` is internal.
    var id: String { extId }

    /// Internal ResRobot id — do not use.
    var rawId: String?
    var extId: String
    var name: String
    var lat: Double
    var lon: Double
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
struct DeparturesResponse: Codable, Equatable, Sendable {
    var timestamp: String
    var query: TimetableQuery
    var stops: [TimetableStop]
    var departures: [CallAtLocation]
}

/// Top-level response for Trafiklab Timetables arrivals.
struct ArrivalsResponse: Codable, Equatable, Sendable {
    var timestamp: String
    var query: TimetableQuery
    var stops: [TimetableStop]
    var arrivals: [CallAtLocation]
}

/// Query metadata shared by the Timetables responses.
struct TimetableQuery: Codable, Equatable, Sendable {
    var queryTime: String
    var query: String?
}

/// A physical stop covered by a Timetables area id.
struct TimetableStop: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var area_id: String?
    var transport_modes: [String]?
    var alerts: [Alert]?
}

/// A single departure/arrival row on a stop board.
struct CallAtLocation: Codable, Equatable, Identifiable, Sendable {
    /// A stable row id derived from the trip; falls back to scheduled time.
    var id: String { trip?.trip_id ?? "\(scheduled)-\(route?.designation ?? "")" }

    var scheduled: LocalDate
    var realtime: LocalDate?
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
struct Route: Codable, Equatable, Sendable {
    /// The line-badge number, e.g. "3" or "T14".
    var designation: String?
    /// `BUS` / `METRO` / `TRAM` / `TRAIN` / `TAXI` / `BOAT`.
    var transport_mode: TransportMode?
    /// The GTFS extended route type, e.g. `700` (bus) or `401` (metro).
    var transport_mode_code: Int?
    /// Destination text; may change mid-route.
    var direction: String?
    /// Set only for lines known by name rather than number.
    var name: String?
    /// The route's first stop.
    var origin: StopNameRef?
    /// The route's last stop.
    var destination: StopNameRef?
}

struct TransportMode: Codable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// `BUS` / `METRO` / `TRAM` / `TRAIN` / `TAXI` / `BOAT`.
    var rawMode: String

    init(stringLiteral value: String) {
        self.rawMode = value.uppercased()
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawMode = try container.decode(String.self).uppercased()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawMode)
    }
}

/// Operator branding for a departure/arrival row.
struct Agency: Codable, Equatable, Sendable {
    /// Agency id matching GTFS Sweden 3.
    var id: String?
    var name: String?
    var operator_: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case operator_ = "operator"
    }
}

/// Reference to a trip, needed to open the Live Trip screen.
struct TripRef: Codable, Equatable, Sendable {
    var trip_id: String
    var start_date: String
    var technical_number: Int?
}

/// A platform/läge, e.g. "Läge C".
struct Platform: Codable, Equatable, Sendable {
    var id: String?
    var designation: String?
}

/// A service message for a stop or call, e.g. `CONSTRUCTION` or
/// `MAINTENANCE`.
struct Alert: Codable, Equatable, Sendable {
    var type: String?
    var title: String?
    var text: String?
}

/// Top-level response for Trafiklab Trips (beta): the trip's agency, route,
/// and one call per stop along the journey.
struct TripResponse: Codable, Equatable, Sendable {
    var timestamp: String
    var query: TripQuery?
    var agency: Agency?
    var route: Route?
    var trip: TripRef?
    var calls: [TripCall]?

    struct TripQuery: Codable, Equatable, Sendable {
        var queryTime: String
        var query: String?
    }
}

/// One scheduled stop along a trip, splitting the vehicle's arrival and
/// departure into their scheduled/realtime/delay/canceled pairs. Only the
/// first call lacks a distinct arrival and only the last lacks a distinct
/// departure; intermediate stops carry both.
struct TripCall: Codable, Equatable, Identifiable, Sendable {
    var id: String {
        let fallback = [scheduledArrival?.date, scheduledDeparture?.date]
            .compactMap { $0 }
            .map { String($0.timeIntervalSinceReferenceDate) }
            .joined(separator: "-")
        return stop?.id ?? fallback
    }

    var scheduledArrival: LocalDate?
    var realtimeArrival: LocalDate?
    var arrivalDelay: Int?
    var arrivalCanceled: Bool?
    var scheduledDeparture: LocalDate?
    var realtimeDeparture: LocalDate?
    var departureDelay: Int?
    var departureCanceled: Bool?
    var stop: TimetableStop?
    var scheduled_platform: Platform?
    var realtime_platform: Platform?
    var alerts: [Alert]?
    var is_realtime: Bool?
}

struct LocalDate: Codable, Hashable, Sendable {
    /// The wrapped instant, always normalized to whole-second precision so a
    /// value stays equal to itself after an encode/decode round trip (the wire
    /// format carries no fractional seconds).
    private(set) var date: Date

    init(date: Date) {
        self.date = Self.truncatingFractionalSeconds(date)
    }
    init(string: String) throws {
        self.date = try Self.truncatingFractionalSeconds(Self.formatter.parse(string))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringDate = try container.decode(String.self)

        guard !stringDate.isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date can not be empty")
        }

        let parsedDate = try Self.formatter.parse(stringDate)
        self.date = Self.truncatingFractionalSeconds(parsedDate)
    }

    /// Drops any sub-second component so values match the second-granularity
    /// timestamps the API sends and ``encode(to:)`` writes.
    private static func truncatingFractionalSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.formatter.format(date))
    }

    /// The Trafiklab APIs send timestamps without a zone designator
    /// (`YYYY-MM-DDTHH:mm:ss`) in Swedish local time, matching the GTFS Sweden
    /// data they are built from. Pin the zone rather than following the
    /// device, so a traveller outside Sweden sees the same departure instants
    /// the boards on the platform show.
    private static let formatter = Date.ISO8601FormatStyle
        .iso8601(timeZone: TimeZone(identifier: "Europe/Stockholm")!)
        .year()
        .month()
        .day()
        .time(includingFractionalSeconds: false)
}
