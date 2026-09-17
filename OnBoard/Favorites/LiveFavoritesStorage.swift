import SwiftUI
import Foundation

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
