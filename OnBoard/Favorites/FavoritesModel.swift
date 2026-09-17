import Foundation
import Observation
import SwiftData

/// The view model for the Favourites tab ("Step 4 — Save a stop → skip the
/// search next time" in `Designs/storyboard.html`).
///
/// Owns the loaded `StoredFavorites` aggregate and the loading lifecycle,
/// mirroring ``NearbyModel`` and ``StopDetailsModel``: `@MainActor @Observable`,
/// surfaces storage errors as a `failure` string rather than throwing. The
/// model is storage-agnostic: it reads and mutates the `StoredFavorites`
/// aggregate through the `ModelContext` passed into each method, so it depends
/// only on the SwiftData store injected into the SwiftUI environment (see
/// ``MyApp``). A favourite is uniquely identified by its stop id (see
/// ``Favorite``); a stop is saved at most once, and toggling a stop that is
/// already saved removes it. The list is kept sorted by stop name.
@MainActor
@Observable
final class FavoritesModel {
    /// The most recent storage error, if the last load or save failed.
    var failure: String?
    /// Whether the initial load is still in progress. `true` until the first
    /// `loadFavorites` completes (success or failure), so the view can show a
    /// spinner before the empty state.
    var isLoading: Bool = false
    /// The saved stops, sorted by name (the model re-sorts on every add).
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
    /// show a "Lines …" subtitle. A `StoredFavorites` aggregate is created on
    /// demand the first time a stop is saved. The list is re-sorted by stop
    /// name after each add; the change is persisted when the caller saves the
    /// `ModelContext`.
    /// - Parameters:
    ///   - stopId: The stop group id (Trafiklab `extId`).
    ///   - stopName: The stop name shown in the row and the board header.
    ///   - lineLabels: The distinct line labels seen on the stop's board.
    ///   - context: The SwiftData context the aggregate lives in.
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
    /// saved or the aggregate has not been loaded. The change is persisted when
    /// the caller saves the `ModelContext`.
    /// - Parameters:
    ///   - stopId: The stop group id (Trafiklab `extId`).
    ///   - context: The SwiftData context the aggregate lives in.
    func remove(_ stopId: String, context: ModelContext) {
        guard let stored else { return }
        guard let index = stored.favorites.firstIndex(where: { $0.id == stopId }) else {
            return
        }
        let fav = stored.favorites.remove(at: index)
        context.delete(fav)
    }
}
