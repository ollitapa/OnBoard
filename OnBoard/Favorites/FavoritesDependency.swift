import SwiftUI
import Foundation

extension EnvironmentValues {
    /// The ``FavoritesModel`` shared across the Favourites tab and the Stop
    /// board's star toggle, injected by ``MainView`` so both screens read and
    /// mutate the same persisted list. `nil` by default (previews/tests that
    /// build a single view inject their own model).
    @Entry var favoritesModel: FavoritesModel?
}

/// Builds the live favourites store: a file-backed store (application support
/// directory) wrapped in an in-memory cache so repeated reads don't hit disk,
/// composed via the existing `combined(with:)` storage helper. Returns the raw
/// `Data` store the model JSON-encodes the favourites list into.
func liveFavoritesStorage() -> any AsyncStorage<Data, String> {
    let cache = MemoryStorage<Data, String>()
    let file = FileStorage(
        searchPath: .applicationSupportDirectory,
        domain: .userDomainMask
    )
    return cache.combined(with: file)
}
