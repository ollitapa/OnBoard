import Foundation

/// Presentation helpers for `TripCall` rows used by the Live Trip screen
/// (``RouteDetailsView``). Modeled as computed properties/methods on the
/// receiver rather than static "pass-the-value" functions so call sites read
/// naturally (`call.date`, `tripCalls.currentStopIndex(now:)`), per the repo's
/// presentation-helper convention.
extension TripCall {

    /// The time the vehicle moves on from this stop, parsed into a `Date`,
    /// preferring the realtime departure and falling back to the scheduled
    /// departure, then the arrival pair when the trip ends here. Returns `nil`
    /// when no time can be parsed. Mirrors ``CallAtLocation.date``.
    var date: Date? {
        departureDate ?? arrivalDate
    }

    /// The realtime (or scheduled) departure `Date`, or `nil` when absent.
    var departureDate: Date? {
        realtimeDeparture?.date ?? scheduledDeparture?.date
    }

    /// The realtime (or scheduled) arrival `Date`, or `nil` when absent.
    var arrivalDate: Date? {
        realtimeArrival?.date ?? scheduledArrival?.date
    }

    /// Whole-minute delay for a call, rounded away from zero. Returns `nil`
    /// when there is no realtime data (delay missing or zero). Uses the
    /// departure delay — the rider tracks where the vehicle is heading — and
    /// falls back to the arrival delay at the final stop. Mirrors
    /// ``CallAtLocation.delayMinutes``.
    var delayMinutes: DelayTime? {
        guard is_realtime == true, let delay = departureDelay ?? arrivalDelay else {
            return nil
        }
        return DelayTime(seconds: delay)
    }

    /// Whether this call is cancelled: the departure is cancelled, or — when
    /// the trip ends here — the arrival is.
    var isCanceled: Bool {
        departureCanceled == true || arrivalCanceled == true
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
/// than about a single call, modeled as a computed property on the receiver.
extension Array where Element == TripCall {

    /// The index of the call the vehicle is currently at or heading to next:
    /// the first call whose departure time has not yet passed at `now`. A stop
    /// still ahead by minutes is "current" once the previous call's time has
    /// passed, so the bus marker sits on the next un-passed stop — matching
    /// the storyboard's "snaps to next stop" behavior (see API-Instructions §5.4).
    /// Returns `nil` when the trip is empty or every call has passed.
    func currentStopIndex(now: Date = Date()) -> TransportPosition? {
        guard !isEmpty else { return nil }

        // Go through each call and the next call
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

    /// Whether the call at `index` has already been passed at `now`: any call
    /// before ``currentStopIndex(now:)``. The current call and all later
    /// calls return `false`.
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
