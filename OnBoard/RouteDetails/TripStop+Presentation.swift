import Foundation

/// Presentation helpers for `TripStop` rows used by the Live Trip screen
/// (``RouteDetailsView``). Modeled as computed properties/methods on the
/// receiver rather than static "pass-the-value" functions so call sites read
/// naturally (`stop.date`, `tripStops.currentStopIndex(now:)`), per the repo's
/// presentation-helper convention.
extension TripStop {

    /// The scheduled time parsed into a `Date`, preferring the realtime time
    /// and falling back to the scheduled time. Returns `nil` when the string
    /// is empty or malformed. Mirrors ``CallAtLocation.date``.
    var date: Date? {
        Self.parsedDate(from: realtime ?? scheduled)
    }

    /// Whole-minute delay for a stop, rounded away from zero. Returns `nil`
    /// when there is no realtime data (delay missing or zero). Mirrors
    /// ``CallAtLocation.delayMinutes``.
    var delayMinutes: DelayTime? {
        guard is_realtime == true, let delay else {
            return nil
        }
        return DelayTime(seconds: delay)
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

/// Presentation helpers for the whole trip schedule, answering questions about
/// the collection (which stop is current, whether a stop is passed) rather
/// than about a single stop, modeled as a computed property on the receiver.
extension Array where Element == TripStop {

    /// The index of the stop the vehicle is currently at or heading to next:
    /// the first stop whose departure time has not yet passed at `now`. A stop
    /// still ahead by minutes is "current" once the previous stop's time has
    /// passed, so the bus marker sits on the next un-passed stop \u2014 matching
    /// the storyboard's "snaps to next stop" behavior (see API-Instructions \u00a75.4).
    /// Returns `nil` when the trip is empty or every stop has passed.
    func currentStopIndex(now: Date = Date()) -> Int? {
        guard !isEmpty else { return nil }
        for (index, stop) in self.enumerated() {
            if let date = stop.date, date > now {
                return index
            }
        }
        return nil
    }

    /// Whether the stop at `index` has already been passed at `now`: any stop
    /// before ``currentStopIndex(now:)``. The current stop and all later
    /// stops return `false`.
    func isPassed(at index: Int, now: Date = Date()) -> Bool {
        guard let current = currentStopIndex(now: now) else {
            return true
        }
        return index < current
    }
}
