import Foundation
import Observation

/// A navigation value carrying everything the Live Trip screen needs from the
/// departure row that was tapped: the trip id + start date to load the
/// stop-by-stop schedule, plus the line label, direction, and delay shown in
/// the screen's header (mirroring what the rider saw on the board).
///
/// Built from a `CallAtLocation` via ``CallAtLocation.routeDetails``; `nil`
/// when the departure has no `trip` reference and so can't open the screen.
struct RouteDetails: Identifiable, Hashable, Sendable {
    /// `trip.trip_id` from the tapped departure, fed to `Trafiklab.trip`.
    let tripId: String
    /// `trip.start_date` from the tapped departure, fed to `Trafiklab.trip`.
    let startDate: String
    /// The line-badge label, e.g. "55" or "T14", shown as "Line 55 → Ropsten".
    let lineLabel: String
    /// The destination text, shown after the arrow in the header.
    let direction: String
    /// Whole-minute delay for the header's "Delayed 3 min" pill, from the tapped
    /// departure's realtime data; `nil` when on time or no realtime data.
    let delayMinutes: DelayTime?
    /// The transport mode for the route, used to display the mode icon.
    let transportMode: TransportMode?

    /// Identity is the trip + its start date (a line runs the same id many times
    /// a day; the date disambiguates).
    var id: String { "\(tripId)-\(startDate)" }

    /// The inline nav title: "Line 55 • Ropsten"
    var lineTitle: String {
        "Line \(lineLabel) • \(direction)"
    }
}

/// The view model for the Live Trip screen (`Designs/storyboard.html`,
/// "Step 3 — Tap a departure → track the bus stop by stop").
///
/// Loads a single trip's stop-by-stop schedule via `Trafiklab.trip` and stores
/// the raw `TripCall` rows for the view to render. Mirrors ``StopDetailsModel``:
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
    var calls: [TripCall] = []

    /// The track's presentation rows, precomputed from ``calls`` on every load
    /// so the view renders straight from them without re-deriving the
    /// vehicle's position per row. Because the view reloads every 30 s, the
    /// countdown subtitles and the marker's position stay current.
    var rows: [TripStopRow] = []

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
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.trip(tripId: tripId, startDate: startDate)

            // No need to do any updates if task is cancelled.
            try Task.checkCancellation()

            calls = response.calls ?? []
            rows = calls.stopRows()
            failure = nil
        } catch is CancellationError {
            // Task was cancelled, ignore.
        }  catch {
            calls = []
            rows = []
            failure = String(describing: error)
        }
    }

    /// Recomputes the track's presentation rows from the loaded schedule at
    /// `now`. Trafiklab's realtime data only refreshes every 60 s, so the view
    /// reloads the schedule on that cadence and calls this between reloads
    /// (from a periodic `TimelineView`) to keep the marker's position and the
    /// countdown subtitles moving with the clock instead of lagging a minute
    /// behind the vehicle.
    func recalculateRows(now: Date) {
        rows = calls.stopRows(now: now)
    }
}

// MARK: - Track rows

/// Where the vehicle is on the trip's schedule at a moment in time.
enum TransportPosition: Hashable {
    case atStop(index: Int)
    case betweenStops(before: Int, after: Int)
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
    /// How far the vehicle has travelled from the previous stop's node to this
    /// one while between stops: 0 as it leaves the previous stop, 1 as it
    /// pulls up to this one. `nil` unless this row is between stops.
    let travelProgress: Double?
    let isFirst: Bool
    let isFinal: Bool
    let subtitle: String?
}

/// The schedule-to-rows calculation owned by ``RouteDetailsModel``, answering
/// questions about the whole trip schedule (which stop is current, whether a
/// stop is passed) rather than about a single call.
extension Array where Element == TripCall {

    /// How long the vehicle is still considered to be standing at a stop after
    /// its departure time: the moment it is scheduled to move on. Stops with a
    /// real dwell (arrival before departure) read as "at the stop" for that
    /// whole span; a stop whose arrival and departure coincide gets this much
    /// presence so the "Arrived"/"Departing now" signage is visible at all.
    private static let dwellGrace: TimeInterval = 30

    /// The index of the call the vehicle is currently at or heading to next,
    /// derived from the calls' arrival and departure spans: the vehicle stands
    /// at a stop from its arrival until shortly after its departure, and
    /// travels between one stop's departure and the next stop's arrival.
    /// Returns `nil` when the trip is empty, hasn't started, or has finished.
    func currentStopIndex(now: Date = Date()) -> TransportPosition? {
        guard !isEmpty else { return nil }

        // Go through each call and the next call
        for ((stopIdx, stop), (nextIdx, nextStop)) in zip(self.enumerated(), self.enumerated().dropFirst()) {
            guard let arrival = stop.arrivalDate ?? stop.departureDate,
                  let departure = stop.departureDate ?? stop.arrivalDate else { continue }

            // Vehicle is standing at the stop: arrival → departure (+ grace).
            if now >= arrival, now <= departure.addingTimeInterval(Self.dwellGrace) {
                return .atStop(index: stopIdx)
            }
            // Vehicle is travelling between this stop and the next one.
            if let nextArrival = nextStop.arrivalDate ?? nextStop.departureDate,
               now > departure.addingTimeInterval(Self.dwellGrace), now < nextArrival {
                return .betweenStops(before: stopIdx, after: nextIdx)
            }
            // Vehicle is not on the track at all.
            if now < arrival { return nil }
        }

        // The final call has no following stop: the vehicle is at the end of
        // the line from its arrival until shortly after its departure.
        if let lastCall = last,
           let arrival = lastCall.arrivalDate ?? lastCall.departureDate {
            let departure = lastCall.departureDate ?? arrival
            if now >= arrival, now <= departure.addingTimeInterval(Self.dwellGrace) {
                return .atStop(index: count - 1)
            }
        }
        return nil
    }

    /// One ``TripStopRow`` per call in travel order, computed with a single
    /// position lookup instead of re-deriving it for every row: the track
    /// renders straight from the rows with no index comparisons.
    func stopRows(now: Date = Date()) -> [TripStopRow] {
        let position = currentStopIndex(now: now)

        /// How far into the current leg the vehicle is, 0 leaving the previous
        /// stop and 1 pulling up to the target one, so the view can move the
        /// marker smoothly instead of snapping between rows.
        let travelProgress: Double?
        if case .betweenStops(let before, let after) = position,
           let legStart = self[before].departureDate ?? self[before].arrivalDate,
           let legEnd = self[after].arrivalDate ?? self[after].departureDate {
            let span = legEnd.timeIntervalSince(legStart.addingTimeInterval(Self.dwellGrace))
            if span > 0 {
                let elapsed = now.timeIntervalSince(legStart.addingTimeInterval(Self.dwellGrace))
                travelProgress = min(max(elapsed / span, 0), 1)
            } else {
                travelProgress = nil
            }
        } else {
            travelProgress = nil
        }

        return enumerated().map { index, call in
            /// Whether the call at `index` has already been passed at `now`.
            let isPassed = switch position {
                case .atStop(let current): index < current
                case .betweenStops(let current, _): index <= current
                case .none: true
            }

            /// Whether the vehicle is standing at the call at `index` right now.
            let isCurrent = if case .atStop(let current) = position { index == current } else { false }

            /// The stop the vehicle is at or heading to next: the stop it is standing
            /// at when `atStop`, and the upcoming stop when between two stops — the row
            /// the bus marker sits on.
            let isTarget = switch position {
                case .atStop(let current), .betweenStops(before: _, after: let current): index == current
                case .none: false
            }

            /// Whether the vehicle is on the move between this stop and the next one.
            let isBetweenStops = if case .betweenStops = position { true } else { false }

            return TripStopRow(
                id: call.id,
                name: call.stop?.name ?? "",
                isCanceled: call.isCanceled,
                isPassed: isPassed,
                isCurrent: isCurrent,
                isTarget: isTarget,
                isBetweenStops: isTarget && isBetweenStops,
                travelProgress: isTarget && isBetweenStops ? travelProgress : nil,
                isFirst: index == 0,
                isFinal: index == count - 1,
                subtitle: Self.subtitle(
                    for: call,
                    isTarget: isTarget,
                    isBetweenStops: isTarget && isBetweenStops,
                    isFinal: index == count - 1,
                    now: now
                )
            )
        }
    }

    /// The subtitle for a row: cancelled calls show "Cancelled"; the final
    /// stop shows "Final stop"; the stop the vehicle is heading to counts down
    /// to its arrival ("Bussen är här om 7 min" in the storyboard), rounded up
    /// so the last minute reads "Arriving in 1 min" until the vehicle pulls up;
    /// the stop the vehicle is standing at shows "Arrived" for most of its
    /// dwell and "Departing now" for the last tenth, so the signage follows
    /// the arrival and estimated departure times. `nil` for every other row.
    private static func subtitle(
        for call: TripCall,
        isTarget: Bool,
        isBetweenStops: Bool,
        isFinal: Bool,
        now: Date
    ) -> String? {
        if call.isCanceled {
            return "Cancelled"
        }
        if isFinal {
            return "Final stop"
        }
        if isTarget {
            if isBetweenStops {
                // En route: count up to the arrival (falling back to the
                // departure when the call carries a single time), never
                // "Departing now" — the vehicle only stands at the stop once
                // the position says so, and the two must agree for the whole
                // last minute.
                guard let arrival = call.arrivalDate ?? call.departureDate else { return nil }
                let minutes = Int((arrival.timeIntervalSince(now) / 60).rounded(.up))
                return minutes <= 0 ? "Arriving now" : "Arriving in \(minutes) min"
            }
            // Standing at the stop: "Arrived" until the last tenth of the
            // dwell, then "Departing now" — with a momentary stop the whole
            // (grace-extended) visit reads as departing.
            guard let arrival = call.arrivalDate ?? call.departureDate,
                  let departure = call.departureDate ?? call.arrivalDate else { return nil }
            let dwell = departure.timeIntervalSince(arrival)
            let departingFrom = arrival.addingTimeInterval(max(dwell * 0.9, dwell - 10))
            return now >= departingFrom ? "Departing now" : "Arrived"
        }
        return nil
    }
}

/// Presentation helpers for the model's precomputed track rows, answering
/// questions about the rendered track rather than the raw schedule.
extension Array where Element == TripStopRow {

    /// The row the vehicle is at or heading to — the row carrying the bus
    /// marker, which the view scrolls to when the screen opens. Read off the
    /// rows' own `isTarget` flags, so it costs no extra position lookup.
    /// `nil` when the vehicle isn't on the track.
    var target: TripStopRow? {
        first { $0.isTarget }
    }
}
