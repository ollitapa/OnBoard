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
        realtime?.date ?? scheduled?.date
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
}

enum TransportPosition: Hashable {
    case atStop(index: Int)
    case betweenStops(before: Int, after: Int)

    var lowerBoundIndex: Int {
        switch self {
        case .atStop(let index), .betweenStops(before: let index, after: _): index
        }
    }
}

/// Presentation helpers for the whole trip schedule, answering questions about
/// the collection (which stop is current, whether a stop is passed) rather
/// than about a single stop, modeled as a computed property on the receiver.
extension Array where Element == TripStop {

    /// The index of the stop the vehicle is currently at or heading to next:
    /// the first stop whose departure time has not yet passed at `now`. A stop
    /// still ahead by minutes is "current" once the previous stop's time has
    /// passed, so the bus marker sits on the next un-passed stop — matching
    /// the storyboard's "snaps to next stop" behavior (see API-Instructions ·5.4).
    /// Returns `nil` when the trip is empty or every stop has passed.
    func currentStopIndex(now: Date = Date()) -> TransportPosition? {
        guard !isEmpty else { return nil }

        // Go through each stop and the next stop
        for ((stopIdx, stop), (nextIdx, nextStop)) in zip(self.enumerated(), self.enumerated().dropFirst()) {
            if let date = stop.date {
                let onStopRange = date.addingTimeInterval(-30)...date.addingTimeInterval(30)
                // Vehicle is at the stop
                if onStopRange.contains(now) { return .atStop(index: stopIdx) }
                if let nextDate = nextStop.date {
                    let onNextStopRange = date.addingTimeInterval(-30)...date.addingTimeInterval(30)
                    // Vehicle is at the next stop
                    if onNextStopRange.contains(now) { return .atStop(index: nextIdx) }
                    // Vehicle is between these stops
                    if now > date && now < nextDate { return .betweenStops(before: stopIdx, after: nextIdx) }
                }
                // Vehicle is not on the track at all.
                if now < date { return nil }
            }
        }
        return nil
    }

    /// Whether the stop at `index` has already been passed at `now`: any stop
    /// before ``currentStopIndex(now:)``. The current stop and all later
    /// stops return `false`.
    func isPassed(at index: Int, now: Date = Date()) -> Bool {
        switch currentStopIndex(now: now) {
        case .none: return true
        case .atStop(let current):
            return index < current
        case .betweenStops(let current, _):
            return index <= current
        }
    }
}
