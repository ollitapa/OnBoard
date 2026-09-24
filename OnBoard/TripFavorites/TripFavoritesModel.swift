import Foundation
import Observation
import SwiftData

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
/// The list is classified from the end date captured at save time (see
/// ``TripFavorite/endDate``), not from a schedule refresh: ``activeTrips``
/// is the journeys whose end hasn't passed, ``inactiveTrips`` the rest, and
/// ``cleanStaleTrips(context:now:)`` purges the finished ones.
@MainActor
@Observable
final class TripFavoritesModel {
    /// The most recent storage error, if the last load failed.
    var failure: String?
    /// Whether the initial load is still in progress. `true` until the first
    /// `loadTripFavorites` completes (success or failure), so the view can
    /// show a spinner before the empty state.
    var isLoading: Bool = false
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
    /// direction, transport mode, and the journey's end date — the final
    /// stop's departure from the schedule the Live Trip screen already
    /// loaded — are stored so the row renders and the live/finished split
    /// works without a network round trip. A `StoredTripFavorites` aggregate
    /// is created on demand the first time a trip is saved. The change is
    /// persisted when the caller saves the `ModelContext`.
    /// - Parameters:
    ///   - route: The trip to save, carrying the trip id + start date and
    ///     the row's presentation fields.
    ///   - endDate: The journey's end (the final stop's departure), or `nil`
    ///     when the schedule hasn't loaded yet.
    ///   - context: The SwiftData context the aggregate lives in.
    func toggle(_ route: RouteDetails, endDate: Date?, context: ModelContext) {
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
                transportMode: route.transportMode,
                endDate: endDate
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

    /// The saved trips whose journeys haven't ended — the Favourites list's
    /// top section, hidden by the view when empty. A trip saved without a
    /// known end date reads as live (see ``TripFavorite/isActive(now:)``),
    /// so a half-loaded save is never shunted or cleaned on a guess.
    var activeTrips: [TripFavorite] {
        trips.filter { $0.isActive() }
    }

    /// The saved trips whose journeys have ended — shown in the Favourites
    /// list's trailing section, newest-first, and removable with
    /// ``cleanStaleTrips(context:now:)``.
    var inactiveTrips: [TripFavorite] {
        trips.filter { !$0.isActive() }
    }

    /// How many saved trips have finished — the count the "clean finished
    /// trips" button removes.
    var finishedCount: Int {
        inactiveTrips.count
    }

    /// Removes the saved trips whose journeys are over — their saved end date
    /// has passed, so the vehicle has left the final stop and the live
    /// schedule no longer tracks it. A no-op when nothing has finished.
    /// - Parameters:
    ///   - context: The SwiftData context the aggregate lives in.
    ///   - now: The instant the live/finished split is evaluated against.
    func cleanStaleTrips(context: ModelContext, now: Date = Date()) {
        let staleIds = Set(inactiveTrips(now: now).map(\.id))
        guard !staleIds.isEmpty else { return }
        for id in staleIds {
            remove(id, context: context)
        }
    }

    /// The finished trips as of `now`, for ``cleanStaleTrips(context:now:)``.
    private func inactiveTrips(now: Date) -> [TripFavorite] {
        trips.filter { !$0.isActive(now: now) }
    }
}
