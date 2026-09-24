import Foundation
import Observation
import SwiftData

/// Whether a saved trip's journey is on the track right now, classified from
/// the schedule loaded by ``TripFavoritesModel/refreshStatuses(network:now:)``.
enum SavedTripStatus: Equatable, Sendable {
    /// The vehicle is between the trip's first and final stop right now.
    case active
    /// The trip hasn't begun yet. Also the stand-in for a schedule that
    /// couldn't be loaded or parsed — an unreadable trip is never treated as
    /// finished, so the cleanup never deletes one on a guess.
    case upcoming
    /// The final stop has passed and the live schedule no longer tracks the
    /// vehicle: the trip is stale.
    case finished
}

/// The view model for the saved-trip sections of the Favourites tab:
/// journeys saved from the Live Trip screen, so the next ride starts one
/// tap away.
///
/// Mirrors ``FavoritesModel``: `@MainActor @Observable`, storage-agnostic
/// (reads and mutates the `StoredTripFavorites` aggregate through the
/// `ModelContext` passed into each method), surfaces storage errors as a
/// `failure` string, and keeps the list sorted — newest first. A trip is
/// saved at most once (uniquely identified by trip id + start date, matching
/// `RouteDetails.id`) and toggling a trip that is already saved removes it.
///
/// Also owns the trips' live classification and the stale-trip cleanup:
/// ``refreshStatuses(network:now:)`` loads each saved trip's schedule and
/// records whether its journey is currently on the track, so the Favourites
/// list can put the active ones in its top section and shunt the rest to the
/// end; ``cleanStaleTrips(context:)`` removes the finished ones.
@MainActor
@Observable
final class TripFavoritesModel {
    /// The most recent storage error, if the last load failed.
    var failure: String?
    /// Whether the initial load is still in progress. `true` until the first
    /// `loadTripFavorites` completes (success or failure), so the view can
    /// show a spinner before the empty state.
    var isLoading: Bool = false
    /// Whether a status refresh is currently in flight, so the view can show
    /// its toolbar spinner while schedules load.
    var isRefreshing: Bool = false
    /// The saved trips, sorted newest-first (the model re-sorts on every add).
    private(set) var stored: StoredTripFavorites?
    /// The loaded status per saved trip, keyed by `TripFavorite.id`. A trip
    /// with no entry (not yet refreshed, or its schedule failed to load)
    /// reads as upcoming — never as finished, so it is never cleaned on a
    /// guess.
    private(set) var statuses: [String: SavedTripStatus] = [:]
    /// The saved trips, newest first.
    var trips: [TripFavorite] {
        stored?.trips ?? []
    }

    init() { }

    /// Loads the saved trips from the store into ``trips``.
    func loadTripFavorites(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }
        do {
            stored = try context.fetch(FetchDescriptor<StoredTripFavorites>()).first
        } catch {
            stored = nil
            failure = String(describing: error)
        }
    }

    /// Whether the given trip is saved. Identity is the trip id + start date,
    /// matching `RouteDetails.id`.
    func contains(_ route: RouteDetails) -> Bool {
        trips.contains { $0.id == route.id }
    }

    /// Saves a trip, or removes it if already saved. The line label,
    /// direction, and transport mode captured at save time are stored so the
    /// row renders without a network round trip; the delay is deliberately
    /// not captured (it changes minute to minute, so the Live Trip screen
    /// re-derives it on load). A `StoredTripFavorites` aggregate is created
    /// on demand the first time a trip is saved. The change is persisted
    /// when the caller saves the `ModelContext`.
    /// - Parameters:
    ///   - route: The trip to save, carrying the trip id + start date and the
    ///     row's presentation fields.
    ///   - context: The SwiftData context the aggregate lives in.
    func toggle(_ route: RouteDetails, context: ModelContext) {
        let stored: StoredTripFavorites
        if let existing = self.stored {
            stored = existing
        } else {
            stored = StoredTripFavorites(trips: [])
            context.insert(stored)
            self.stored = stored
        }
        if let index = stored.trips.firstIndex(where: { $0.id == route.id }) {
            let trip = stored.trips.remove(at: index)
            context.delete(trip)
        } else {
            let trip = TripFavorite(
                tripId: route.tripId,
                startDate: route.startDate,
                lineLabel: route.lineLabel,
                direction: route.direction,
                transportMode: route.transportMode
            )
            stored.trips.append(trip)
            stored.trips = stored.trips
                .sorted { $0.savedAt > $1.savedAt }
        }
    }

    /// Removes a saved trip by id ("{tripId}-{startDate}"). A no-op when the
    /// trip is not saved or the aggregate has not been loaded. The change is
    /// persisted when the caller saves the `ModelContext`.
    /// - Parameters:
    ///   - id: The composite trip id, matching `RouteDetails.id`.
    ///   - context: The SwiftData context the aggregate lives in.
    func remove(_ id: String, context: ModelContext) {
        guard let stored else { return }
        guard let index = stored.trips.firstIndex(where: { $0.id == id }) else {
            return
        }
        let trip = stored.trips.remove(at: index)
        context.delete(trip)
    }

    /// The saved trips currently on the track — the Favourites list's top
    /// section, hidden by the view when empty.
    var activeTrips: [TripFavorite] {
        trips.filter { statuses[$0.id] == .active }
    }

    /// The saved trips not running right now — upcoming or already finished —
    /// shown in the Favourites list's trailing section. Upcoming ones come
    /// first (a journey about to leave matters more than one already ended),
    /// then newest-first within each group.
    var inactiveTrips: [TripFavorite] {
        trips
            .filter { statuses[$0.id] != .active }
            .sorted { lhs, rhs in
                let lhsFinished = statuses[lhs.id] == .finished
                let rhsFinished = statuses[rhs.id] == .finished
                if lhsFinished != rhsFinished { return rhsFinished }
                return lhs.savedAt > rhs.savedAt
            }
    }

    /// How many saved trips have finished — the count the "clean finished
    /// trips" button removes.
    var finishedCount: Int {
        statuses.values.filter { $0 == .finished }.count
    }

    /// Loads each saved trip's schedule via the Trafiklab Trips API and
    /// records whether its journey is currently on the track, so the
    /// Favourites list can group the active trips at the top. Best-effort:
    /// a trip whose schedule can't be loaded (network or decode failure, or
    /// an empty one) keeps no status — it reads as upcoming, is shown in
    /// the trailing section, and is never treated as finished.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - now: The instant the classification is evaluated against.
    func refreshStatuses(
        network: some NetworkProtocol,
        now: Date = Date()
    ) async {
        guard let stored, !stored.trips.isEmpty else {
            statuses = [:]
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let api = Trafiklab(network: network)
        /// The statuses loaded this pass, assigned only after every schedule
        /// has been checked, so a cancelled refresh (the view re-triggers it
        /// on every appearance) never leaves a half-classified list behind.
        var loaded: [String: SavedTripStatus] = [:]
        for trip in stored.trips {
            do {
                let response = try await api.trip(
                    tripId: trip.tripId,
                    startDate: trip.startDate
                )
                loaded[trip.id] = Self.status(of: response.calls ?? [], now: now)
            } catch is CancellationError {
                return
            } catch {
                // Best-effort: a schedule that can't be loaded keeps no
                // status, so the trip is shown but never cleaned on a guess.
                continue
            }
        }
        statuses = loaded
    }

    /// Removes the saved trips whose journeys are over (final stop passed),
    /// per the statuses loaded by ``refreshStatuses(network:now:)`` — the
    /// Favourites list's "clean finished trips" button. A no-op when no
    /// status has been classified as finished.
    /// - Parameter context: The SwiftData context the aggregate lives in.
    func cleanStaleTrips(context: ModelContext) {
        let staleIds = Set(
            trips
                .filter { statuses[$0.id] == .finished }
                .map(\.id)
        )
        guard !staleIds.isEmpty else { return }
        for id in staleIds {
            remove(id, context: context)
            statuses.removeValue(forKey: id)
        }
    }

    /// Classifies a loaded schedule: on the track, not begun, or over. An
    /// empty or unparsable schedule reads as upcoming — never finished — so
    /// the cleanup keeps it.
    static func status(of calls: [TripCall], now: Date) -> SavedTripStatus {
        if calls.isFinished(now: now) { return .finished }
        if calls.currentStopIndex(now: now) != nil { return .active }
        return .upcoming
    }
}
