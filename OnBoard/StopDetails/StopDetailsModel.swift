import Foundation
import Observation

/// The view model for the Stop board screen (`Designs/storyboard.html`,
/// "Step 2 \u2014 Stop board").
///
/// Loads realtime departures for a stop group id via `Trafiklab.departures`
/// and stores the raw `CallAtLocation` rows for the view to render. Mirrors
/// ``NearbyModel``: `@MainActor @Observable`, builds a `Trafiklab` client from
/// the injected network so tests can substitute a mock service, and surfaces
/// transport errors as a `failure` string rather than throwing.
@MainActor
@Observable
final class StopDetailsModel {

    /// The most recent transport error, if the last load failed.
    var failure: String?

    /// Whether a load is currently in progress.
    var isLoading: Bool = false

    /// The departures returned for the loaded stop, in API order (soonest first).
    var departures: [CallAtLocation] = []

    init() {}

    /// Loads departures for the given stop group id via the Trafiklab Timetables API.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - areaId: The riksh\u00e5llplats/meta-stop id (group id, never a child stop id).
    func loadDepartures(network: some NetworkProtocol, areaId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.departures(at: areaId)
            departures = response.departures
            failure = nil
        } catch {
            departures = []
            failure = String(describing: error)
        }
    }
}

// MARK: - Presentation helpers

extension StopDetailsModel {

    /// The line-badge label for a departure row: the route's designation when
    /// available, falling back to the route name, then to "?".
    static func lineLabel(for departure: CallAtLocation) -> String {
        departure.route?.designation
            ?? departure.route?.name
            ?? "?"
    }

    /// The destination text for a departure row, from the route's direction.
    static func destination(for departure: CallAtLocation) -> String {
        departure.route?.direction ?? ""
    }

    /// Whole-minute delay for the delay pill, rounded away from zero. Returns
    /// `nil` when there is no realtime data (delay missing or zero).
    static func delayMinutes(for departure: CallAtLocation) -> Int? {
        guard departure.is_realtime == true, let delay = departure.delay, delay != 0 else {
            return nil
        }
        let minutes = Double(delay) / 60
        return delay > 0
            ? Int(minutes.rounded(.up))
            : Int(minutes.rounded(.down))
    }

    /// Whole minutes from `now` until the departure's realtime time, falling
    /// back to its scheduled time when no realtime value is present. Returns
    /// `nil` when no time can be parsed.
    static func minutesUntil(
        departure: CallAtLocation,
        now: Date,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> Int? {
        let timeString = departure.realtime ?? departure.scheduled
        guard let date = Self.date(from: timeString, timeZone: timeZone) else {
            return nil
        }
        let components = calendar.dateComponents([.minute], from: now, to: date)
        return components.minute
    }

    /// Parses a Trafiklab realtime timestamp (`YYYY-MM-DDTHH:mm:ss`) into a
    /// `Date`. Returns `nil` for an empty or malformed string.
    static func date(from string: String?, timeZone: TimeZone) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
