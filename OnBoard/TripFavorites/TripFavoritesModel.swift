import Foundation
import Observation
import SwiftData

/// The view model for the Trips tab: journeys saved from the Live Trip
/// screen so the next ride starts one tap away.
///
/// Mirrors ``FavoritesModel``: `@MainActor @Observable`, storage-agnostic
/// (reads and mutates the `StoredTripFavorites` aggregate through the
/// `ModelContext` passed into each method), surfaces storage errors as a
/// `failure` string, and keeps the list sorted — newest first, so the most
/// recently saved trip is the easiest to reach. A trip is saved at most once
/// (uniquely identified by trip id + start date, matching `RouteDetails.id`)
/// and toggling a trip that is already saved removes it.
///
/// Also owns the stale-trip cleanup: a saved trip is stale once its final
/// stop has been passed (the vehicle has left the terminus), at which point
/// the live schedule no longer tracks it. ``cleanStaleTrips(network:context:now:)``
/// loads each saved trip's schedule and removes the finished ones.
@MainActor
@Observable
final class TripFavoritesModel {
    /// The most recent storage error, if the last load failed.
    var failure: String?
    /// Whether the initial load is still in progress. `true` until the first
    /// `loadTripFavorites` completes (success or failure), so the view can
    /// show a spinner before the empty state.
    var isLoading: Bool = false
    /// Whether a stale-trip cleanup is currently in flight, so the view can
    /// disable its clean button while trips are being checked.
    var isCleaning: Bool = false
    /// The saved trips, sorted newest-first (the model re-sorts on every add).
    private(set) var stored: StoredTripFavorites?
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

    /// Removes the saved trips whose journey is over: each trip's schedule is
    /// loaded via the Trafiklab Trips API and the trip is deleted once its
    /// final stop has been passed (see `Array.isFinished(now:)`), when the
    /// live schedule no longer tracks the vehicle. Cleaning is best-effort:
    /// a trip whose schedule can't be loaded (network or decode failure) is
    /// kept rather than guessed at, so a transient outage never deletes a
    /// trip that is still running. Empty and unparsable schedules are kept
    /// for the same reason — they never read as finished.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - context: The SwiftData context the aggregate lives in.
    ///   - now: The instant the finished check is evaluated against.
    func cleanStaleTrips(
        network: some NetworkProtocol,
        context: ModelContext,
        now: Date = Date()
    ) async {
        guard let stored, !stored.trips.isEmpty else { return }
        isCleaning = true
        defer { isCleaning = false }
        let api = Trafiklab(network: network)
        /// The ids found to be finished, collected first so the aggregate is
        /// mutated only after every schedule has been checked.
        var staleIds: Set<String> = []
        for trip in stored.trips {
            do {
                let response = try await api.trip(
                    tripId: trip.tripId,
                    startDate: trip.startDate
                )
                if (response.calls ?? []).isFinished(now: now) {
                    staleIds.insert(trip.id)
                }
            } catch {
                // Best-effort: a schedule that can't be loaded is kept.
                continue
            }
        }
        for id in staleIds {
            remove(id, context: context)
        }
    }
}
