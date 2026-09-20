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
}
