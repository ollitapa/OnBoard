import Foundation
import Observation
import SwiftData

/// The view model for the Favourites tab ("Step 4 — Save a stop → skip the
/// search next time" in `Designs/storyboard.html`).
///
/// Owns the persisted list of saved stops and the loading lifecycle, mirroring
/// ``NearbyModel`` and ``StopDetailsModel``: `@MainActor @Observable`, surfaces
/// storage errors as a `failure` string rather than throwing. The model takes a
/// raw `AsyncStorage<Data, String>` (a `FileStorage`-shaped store) and does its
/// own JSON encode/decode of the `[Favorite]` list, so it depends only on the
/// same storage primitive the rest of the app uses. A favourite is uniquely
/// identified by its stop id (see ``Favorite``); a stop is saved at most once,
/// and toggling a stop that is already saved removes it.
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
    private(set) var stored: StoredFavorites?

    var favorites: [Favorite] {
        stored?.favorites ?? []
    }

    init() { }

    /// Loads the saved favourites from the store into ``favorites``.
    func loadFavorites(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }
        do {
            stored = try context.fetch(FetchDescriptor<StoredFavorites>()).first
        } catch {
            stored = nil
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
        lines lineLabels: [String],
        context: ModelContext
    ) {
        let stored: StoredFavorites
        if let existing = self.stored {
            stored = existing
        } else {
            stored = StoredFavorites(favorites: [])
            context.insert(stored)
            self.stored = stored
        }

        if let index = stored.favorites.firstIndex(where: { $0.id == stopId }) {
            let fav = stored.favorites.remove(at: index)
            context.delete(fav)
        } else {
            let fav = Favorite(id: stopId, name: stopName, lines: lineLabels)
            stored.favorites.append(fav)
            stored.favorites = stored.favorites
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Removes a saved favourite by stop id. A no-op when the stop is not
    /// saved. Persisted on every change; a save failure rolls back and
    /// surfaces the error in ``failure``.
    func remove(_ stopId: String, context: ModelContext) {
        guard let stored else { return }
        guard let index = stored.favorites.firstIndex(where: { $0.id == stopId }) else {
            return
        }
        let fav = stored.favorites.remove(at: index)
        context.delete(fav)
    }
}
