import Foundation

/// Presentation helpers for `CallAtLocation` rows used by the Stop board
/// screen. Modeled as computed properties rather than static "pass-the-value"
/// functions so call sites read naturally (`departure.lineLabel`) instead of
/// the Java-style `Type.lineLabel(for: departure)`.
extension CallAtLocation {

    /// The line-badge label for a departure row: the route's designation when
    /// available, falling back to the route name, then to "?".
    var lineLabel: String {
        route?.designation ?? route?.name ?? "?"
    }

    /// The destination text for a departure row, from the route's direction.
    var destination: String {
        route?.direction ?? ""
    }

    /// Whole-minute delay for the delay pill, rounded away from zero. Returns
    /// `nil` when there is no realtime data (delay missing or zero).
    var delayMinutes: Int? {
        guard is_realtime == true, let delay, delay != 0 else {
            return nil
        }
        let minutes = Double(delay) / 60
        return delay > 0
            ? Int(minutes.rounded(.up))
            : Int(minutes.rounded(.down))
    }

    /// The departure time parsed into a `Date`, preferring the realtime time
    /// and falling back to the scheduled time. Returns `nil` when the string
    /// is empty or malformed.
    var date: Date? {
        Self.parsedDate(from: realtime ?? scheduled)
    }

    /// Parses a Trafiklab realtime timestamp (`YYYY-MM-DDTHH:mm:ss`) into a
    /// `Date`. Returns `nil` for an empty or malformed string.
    private static func parsedDate(from string: String?) -> Date? {
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
