import Foundation
import Observation

/// A navigation value carrying everything the Live Trip screen needs from the
/// departure row that was tapped: the trip id + start date to load the
/// stop-by-stop schedule, plus the line label, direction, and delay shown in
/// the screen's header (mirroring what the rider saw on the board).
///
/// Built from a `CallAtLocation` via ``CallAtLocation.routeDetails``; `nil`
/// when the departure has no `trip` reference and so can't open the screen.
struct RouteDetails: Identifiable, Hashable {
    /// `trip.trip_id` from the tapped departure, fed to `Trafiklab.trip`.
    let tripId: String
    /// `trip.start_date` from the tapped departure, fed to `Trafiklab.trip`.
    let startDate: String
    /// The line-badge label, e.g. "55" or "T14", shown as "Line 55 \u2192 Ropsten".
    let lineLabel: String
    /// The destination text, shown after the arrow in the header.
    let direction: String
    /// Whole-minute delay for the header's "Delayed 3 min" pill, from the tapped
    /// departure's realtime data; `nil` when on time or no realtime data.
    let delayMinutes: Int?

    /// Identity is the trip + its start date (a line runs the same id many times
    /// a day; the date disambiguates).
    var id: String { "\(tripId)-\(startDate)" }
}

/// The view model for the Live Trip screen (`Designs/storyboard.html`,
/// "Step 3 \u2014 Tap a departure \u2192 track the bus stop by stop").
///
/// Loads a single trip's stop-by-stop schedule via `Trafiklab.trip` and stores
/// the raw `TripStop` rows for the view to render. Mirrors ``StopDetailsModel``:
/// `@MainActor @Observable`, builds a `Trafiklab` client from the injected
/// network so tests can substitute a mock service, and surfaces transport
/// errors as a `failure` string rather than throwing.
@MainActor
@Observable
final class RouteDetailsModel {

    /// The most recent transport error, if the last load failed.
    var failure: String?

    /// Whether a load is currently in progress.
    var isLoading: Bool = false

    /// The stop-by-stop schedule for the loaded trip, in travel order.
    var stops: [TripStop] = []

    init() {}

    /// Loads the stop-by-stop schedule for a trip via the Trafiklab Trips API.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - tripId: The `trip.trip_id` from a `CallAtLocation` on the Timetables
    ///     response.
    ///   - startDate: The `trip.start_date` from the same `CallAtLocation`.
    func loadTrip(network: some NetworkProtocol, tripId: String, startDate: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.trip(tripId: tripId, startDate: startDate)
            stops = response.trip?.stops ?? []
            failure = nil
        } catch {
            stops = []
            failure = String(describing: error)
        }
    }
}
