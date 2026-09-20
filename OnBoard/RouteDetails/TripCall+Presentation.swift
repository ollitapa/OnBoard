import Foundation

/// Presentation helpers for `TripCall` values used by the Live Trip screen
/// (``RouteDetailsView``). Modeled as computed properties/methods on the
/// receiver rather than static "pass-the-value" functions so call sites read
/// naturally (`call.date`, `call.isCanceled`), per the repo's
/// presentation-helper convention. The schedule-level helpers (which stop is
/// current, the precomputed track rows) live with the view model in
/// ``RouteDetailsModel``.
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

    /// The row's subtitle: cancelled calls show "Cancelled"; the stop the
    /// vehicle is heading to counts down to its arrival ("Bussen är här om 7
    /// min" in the storyboard), rounded up so the last minute reads "Arriving
    /// in 1 min" until the vehicle pulls up — the final stop included while
    /// the vehicle is still travelling; the intermediate stop the vehicle is
    /// standing at shows "Arrived" for most of its dwell and "Departing now"
    /// for the last tenth; the final stop shows "Final stop" once the vehicle
    /// isn't heading to it (the trip ends there, so it never departs).
    /// `nil` for every other row.
    func subtitle(isTarget: Bool, isBetweenStops: Bool, isFinal: Bool, now: Date) -> String? {
        if isCanceled {
            return "Cancelled"
        }
        if isTarget, isBetweenStops {
            // En route: count up to the arrival (falling back to the
            // departure when the call carries a single time), never
            // "Departing now" — the vehicle only stands at the stop once
            // the position says so, and the two must agree for the whole
            // last minute.
            guard let arrival = arrivalDate ?? departureDate else { return nil }
            let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.up))
            return minutes <= 0 ? "Arriving now" : "Arriving in \(minutes) min"
        }
        if isFinal {
            return "Final stop"
        }
        if isTarget {
            // Standing at the stop: "Arrived" until the last tenth of the
            // dwell, then "Departing now" — with a momentary stop the whole
            // (grace-extended) visit reads as departing.
            guard let arrival = arrivalDate ?? departureDate,
                  let departure = departureDate ?? arrivalDate else { return nil }
            let dwell = departure.timeIntervalSince(arrival)
            let departingFrom = arrival.addingTimeInterval(Swift.max(dwell * 0.9, dwell - 10))
            return now >= departingFrom ? "Departing now" : "Arrived"
        }
        return nil
    }

    /// The arrival time for an upcoming row's trailing edge: whole minutes
    /// away up to 10 ("7 min"), and the clock time ("11:22") beyond that —
    /// the closer the stop, the more useful a relative count. `nil` on the
    /// target row, whose arrival is already counted down in the subtitle,
    /// and on passed rows.
    func trailingTime(isTarget: Bool, isPassed: Bool, now: Date) -> String? {
        guard !isTarget, !isPassed, let arrival = arrivalDate ?? departureDate else { return nil }
        let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.down))
        if minutes < 1 {
            return "1 min"
        }
        return minutes <= 10 ? "\(minutes) min" : arrival.formatted(date: .omitted, time: .shortened)
    }
}
