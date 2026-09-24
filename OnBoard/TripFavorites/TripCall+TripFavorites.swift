import Foundation

/// Schedule-level helpers for `[TripCall]` used by the Trips tab's stale-trip
/// cleanup, per the repo's presentation-helper convention: computed on the
/// receiver so call sites read naturally (`calls.isFinished(now:)`).
extension Array where Element == TripCall {
    /// Whether the journey is over — the vehicle has passed the final stop,
    /// so the live schedule no longer tracks it and the trip is stale.
    ///
    /// Reads the position off the schedule the Live Trip screen renders from:
    /// a trip is finished once it has started (the first call's time has
    /// come) and the vehicle is no longer on the track — standing at, or
    /// travelling towards, no stop. `false` for an empty or unparsable
    /// schedule and for a trip that hasn't begun, so the cleanup never
    /// guesses at a trip it can't see.
    func isFinished(now: Date = Date()) -> Bool {
        guard let start = first?.arrivalDate ?? first?.departureDate else { return false }
        return now >= start && currentStopIndex(now: now) == nil
    }
}
