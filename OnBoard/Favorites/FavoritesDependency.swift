import SwiftUI
import Foundation

/// The storage contract the Favourites feature persists its list under.
/// A concrete `AsyncStorage<[Favorite], String>` (an ``AsyncStorage`` whose
/// `Value` is the whole favourites array and whose `Id` is a single fixed
/// string), provided through the SwiftUI environment so views/tests can inject
/// an in-memory store and the app can inject a file-backed one.
///
/// Declared as a named typealias because the existential `any AsyncStorage`
/// needs concrete associated-type bindings, and `FavoriteStorage` reads far
/// clearer at call sites than `any AsyncStorage<[Favorite], String>`. The
/// typealias already includes the `any`, so use it bare (`FavoriteStorage`),
/// never `any FavoriteStorage` (which would be `any any …`).
typealias FavoriteStorage = any AsyncStorage<[Favorite], String>

extension EnvironmentValues {
    /// The ``FavoritesModel`` shared across the Favourites tab and the Stop
    /// board's star toggle, injected by ``MainView`` so both screens read and
    /// mutate the same persisted list. `nil` by default (previews/tests that
    /// build a single view inject their own model).
    @Entry var favoritesModel: FavoritesModel?
}

/// Builds the live favourites store: a file-backed store (application support
/// directory) wrapped in an in-memory cache so repeated reads don't hit disk,
/// composed via the existing `combined(with:)` storage helper.
///
/// Centralized here rather than in `MainView` so the store is built once per
/// app session and is reachable from previews/tests that want the live path.
func liveFavoritesStorage() -> FavoriteStorage {
    let cache = InMemoryFavoriteStorage()
    let file = FileStorage(
        searchPath: .applicationSupportDirectory,
        domain: .userDomainMask
    )
    .codable(for: [Favorite].self)
    return cache.combined(with: file)
}
