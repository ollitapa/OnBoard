import Foundation
import Observation

/// The view model for the Favourites tab ("Step 4 — Save a stop → skip the
/// search next time" in `Designs/storyboard.html`).
///
/// Owns the persisted list of saved stops and the loading lifecycle, mirroring
/// ``NearbyModel`` and ``StopDetailsModel``: `@MainActor @Observable`, surfaces
/// storage errors as a `failure` string rather than throwing, and depends only
/// on an `AsyncStorage` so tests inject an in-memory store. A favourite is
/// uniquely identified by its stop id (see ``Favorite``); a stop is saved at
/// most once, and toggling a stop that is already saved removes it.
@MainActor
@Observable
final class FavoritesModel {
    /// The most recent storage error, if the last load or save failed.
    var failure: String?
    /// Whether the initial load is still in progress. `true` until the first
    /// `loadFavorites` completes (success or failure), so the view can show a
    /// spinner before the empty state.
    var isLoading: Bool = false
    /// The saved stops, in insertion order (most recently saved is last).
    private(set) var favorites: [Favorite] = []

    /// The backing store for the persisted favourites list. Held by reference
    /// so a `@MainActor` model can keep it across the load/save calls without
    /// copying it into `@State`.
    private let storage: any FavoriteStorage
    /// The single id the whole list is stored under.
    private let storageId = "favorites"

    /// Creates a model backed by the given store.
    /// - Parameter storage: The ``FavoriteStorage`` used to persist the
    ///   favourites list. Defaults to a live file-backed store so the app
    ///   survives between launches; tests pass an in-memory store.
    init(storage: any FavoriteStorage) {
        self.storage = storage
    }

    /// Loads the saved favourites from the store into ``favorites``.
    func loadFavorites() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await storage.value(for: storageId) ?? []
            favorites = loaded
            failure = nil
        } catch {
            favorites = []
            failure = String(describing: error)
        }
    }

    /// Whether the given stop id is saved as a favourite.
    func contains(_ stopId: String) -> Bool {
        favorites.contains { $0.id == stopId }
    }

    /// Saves a stop as a favourite, or removes it if already saved. When
    /// saving, the line labels captured at save time are stored so the row can
    /// show a "Lines …" subtitle. The list is persisted on every change; a
    /// save failure rolls the in-memory list back to its prior state and
    /// surfaces the error in ``failure`` rather than leaving the view and the
    /// store out of sync.
    /// - Parameters:
    ///   - stopId: The stop group id (Trafiklab `extId`).
    ///   - stopName: The stop name shown in the row and the board header.
    ///   - lineLabels: The distinct line labels seen on the stop's board.
    func toggle(
        _ stopId: String,
        name stopName: String,
        lines lineLabels: [String]
    ) async {
        let previous = favorites
        if let index = favorites.firstIndex(where: { $0.id == stopId }) {
            favorites.remove(at: index)
        } else {
            favorites.append(
                Favorite(id: stopId, name: stopName, lines: lineLabels)
            )
        }
        await persist(previous: previous)
    }

    /// Removes a saved favourite by stop id. A no-op when the stop is not
    /// saved. Persisted on every change; a save failure rolls back and
    /// surfaces the error in ``failure``.
    func remove(_ stopId: String) async {
        let previous = favorites
        guard let index = favorites.firstIndex(where: { $0.id == stopId }) else {
            return
        }
        favorites.remove(at: index)
        await persist(previous: previous)
    }

    /// Writes the current list to the store, rolling back to `previous` and
    /// surfacing the error in ``failure`` on a write failure so the in-memory
    /// list never drifts ahead of the persisted one.
    private func persist(previous: [Favorite]) async {
        do {
            try await storage.saveValue(favorites, for: storageId)
            failure = nil
        } catch {
            favorites = previous
            failure = String(describing: error)
        }
    }
}
