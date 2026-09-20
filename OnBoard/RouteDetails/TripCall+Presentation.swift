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

    /// The stop the vehicle is at or heading to next: the stop it is standing
    /// at when `atStop`, and the upcoming stop when between two stops — the row
    /// the bus marker sits on.
    var targetIndex: Int {
        switch self {
        case .atStop(let index), .betweenStops(before: _, after: let index): index
        }
    }

    /// Whether the call at `index` has already been passed for this position:
    /// any call before the stop the vehicle is at, and the stop it left when
    /// between two stops.
    func isPassed(index: Int) -> Bool {
        switch self {
        case .atStop(let current):
            return index < current
        case .betweenStops(let current, _):
            return index <= current
        }
    }

    /// Whether the vehicle is standing at the call at `index` right now, as
    /// opposed to merely heading to it.
    func isAt(index: Int) -> Bool {
        if case .atStop(let current) = self { return index == current }
        return false
    }

    /// Whether the vehicle is on the move between this stop and the next one.
    var isBetweenStops: Bool {
        if case .betweenStops = self { return true }
        return false
    }
}

/// A precomputed presentation snapshot for one row of the Live Trip track,
/// so the view never re-derives the vehicle's position per row: the schedule
/// is walked once (``Array/stopRows(now:)``) and each row carries its name,
/// flags, and subtitle ready to render.
struct TripStopRow: Identifiable, Equatable, Sendable {

    let id: String
    let name: String
    let isCanceled: Bool
    /// The vehicle has already left this stop; the row fades.
    let isPassed: Bool
    /// The vehicle is standing at this stop right now.
    let isCurrent: Bool
    /// The vehicle is at or heading to this stop — the row carrying the bus
    /// marker and the delay pill.
    let isTarget: Bool
    /// The vehicle is between the previous stop and this one, so the marker
    /// sits at the rows' boundary instead of on the node.
    let isBetweenStops: Bool
    let isFirst: Bool
    let isFinal: Bool
    let subtitle: String?
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
                    let onNextStopRange = nextDate.addingTimeInterval(-30)...nextDate.addingTimeInterval(30)
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

    /// One ``TripStopRow`` per call in travel order, computed with a single
    /// position lookup instead of re-deriving it for every row: the track
    /// renders straight from the rows with no index comparisons.
    func stopRows(now: Date = Date()) -> [TripStopRow] {
        let position = currentStopIndex(now: now)

        return enumerated().map { index, call in
            /// Whether the call at `index` has already been passed at `now`.
            let isPassed = position?.isPassed(index: index) ?? true
            return TripStopRow(
                id: call.id,
                name: call.stop?.name ?? "",
                isCanceled: call.isCanceled,
                isPassed: position?.isPassed(index: index) ?? true,
                isCurrent: position?.isAt(index: index) == true,
                isTarget: position?.targetIndex == index,
                isBetweenStops: position?.targetIndex == index && position?.isBetweenStops == true,
                isFirst: index == 0,
                isFinal: index == count - 1,
                subtitle: Self.subtitle(
                    for: call,
                    isTarget: position?.targetIndex == index,
                    isFinal: index == count - 1,
                    now: now
                )
            )
        }
    }

    /// The subtitle for a row: cancelled calls show "Cancelled"; the final
    /// stop shows "Final stop"; the stop the vehicle is at or heading to shows
    /// its countdown ("Bussen är här om 7 min" in the storyboard). `nil` for
    /// every other row.
    private static func subtitle(
        for call: TripCall,
        isTarget: Bool,
        isFinal: Bool,
        now: Date
    ) -> String? {
        if call.isCanceled {
            return "Cancelled"
        }
        if isFinal {
            return "Final stop"
        }
        if isTarget, let date = call.date {
            let minutes = Calendar.current.dateComponents([.minute], from: now, to: date).minute
            if let minutes {
                return minutes <= 0 ? "Departing now" : "Arriving in \(minutes) min"
            }
        }
        return nil
    }
}

/// Presentation helpers for the precomputed track rows, answering questions
/// about the rendered track rather than the raw schedule.
extension Array where Element == TripStopRow {

    /// The row the vehicle is at or heading to — the row carrying the bus
    /// marker, which the view scrolls to when the screen opens. Read off the
    /// rows' own `isTarget` flags, so it costs no extra position lookup.
    /// `nil` when the vehicle isn't on the track.
    var target: TripStopRow? {
        first { $0.isTarget }
    }
}
