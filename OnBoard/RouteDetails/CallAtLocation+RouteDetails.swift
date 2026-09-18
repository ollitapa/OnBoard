import Foundation

/// Bridge from a stop-board departure row to the Live Trip screen, per the
/// repo's presentation-helper convention: a computed property on the
/// receiver so call sites read `departure.routeDetails` instead of a
/// Java-style `RouteDetails.make(for: departure)`. Returns `nil` when the
/// departure carries no `trip` reference and so can't open the screen.
extension CallAtLocation {

    /// The navigation value for the Live Trip screen built from this departure,
    /// carrying the trip id + start date needed to load the schedule and the
    /// line label / direction / delay shown in the screen's header. `nil` when
    /// the departure has no `trip`.
    var routeDetails: RouteDetails? {
        guard let trip else { return nil }
        return RouteDetails(
            tripId: trip.trip_id,
            startDate: trip.start_date,
            lineLabel: lineLabel,
            direction: destination,
            delayMinutes: delayMinutes,
            transportMode: route?.transport_mode
        )
    }
}
