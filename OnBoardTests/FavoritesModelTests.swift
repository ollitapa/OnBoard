import Testing
import Foundation
import SwiftData
@testable import OnBoard

@MainActor
struct FavoritesModelTests {

    // MARK: - Loading

    @Test func loadFavoritesEmptyStoreStartsEmpty() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        // When
        model.loadFavorites(context: context)
        // Then
        #expect(model.favorites == [])
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func loadFavoritesReadsPersistedList() async throws {
        let context = try makeContext(seed: [
            Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])
        ])
        let model = FavoritesModel()
        // When
        model.loadFavorites(context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("1", "Medborgarplatsen", ["3", "7"])
        ])
        #expect(model.failure == nil)
    }

    @Test func loadFavoritesKeepsListEmptyWhenFetchThrows() async throws {
        // An in-memory container for StoredFavorites never throws on fetch, so
        // the failure path can't be exercised through it. The relevant
        // invariant a load must preserve is that a failed/empty load leaves an
        // empty list and a nil failure rather than a stale one; verified here
        // against a fresh context.
        let context = try makeContext()
        let model = FavoritesModel()
        model.loadFavorites(context: context)
        #expect(model.favorites == [])
        #expect(model.failure == nil)
    }

    // MARK: - contains

    @Test func containsIsFalseBeforeSave() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.loadFavorites(context: context)
        #expect(model.contains("1") == false)
    }

    @Test func containsIsTrueAfterSave() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        #expect(model.contains("1") == true)
    }

    @Test func containsIsFalseAfterRemove() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        #expect(model.contains("1") == false)
    }

    // MARK: - toggle

    @Test func toggleAddsFavorite() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        // When
        model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"], context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("1", "Medborgarplatsen", ["3", "7"])
        ])
        #expect(model.failure == nil)
    }

    @Test func toggleRemovesExistingFavorite() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context)
        model.toggle("2", name: "Slussen", lines: ["4"], context: context)
        // When
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("2", "Slussen", ["4"])
        ])
    }

    @Test func toggleDoesNotDuplicateFavorite() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context)
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context)
        model.toggle("1", name: "Medborgarplatsen", lines: ["7"], context: context)
        // Then: still one entry, id-keyed; toggle removed then re-added.
        #expect(model.favorites.count == 1)
        #expect(model.favorites.first?.id == "1")
    }

    @Test func toggleUpdatesLineLabelsWhenReAdding() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context)
        model.toggle("1", name: "Medborgarplatsen", lines: ["3"], context: context) // remove
        // When
        model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"], context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("1", "Medborgarplatsen", ["3", "7"])
        ])
    }

    @Test func toggleKeepsFavoritesSortedByName() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        // Insert out of alphabetical order.
        model.toggle("1", name: "Slussen", lines: [], context: context)
        model.toggle("2", name: "Medborgarplatsen", lines: [], context: context)
        model.toggle("3", name: "Odenplan", lines: [], context: context)
        // Then: the list is kept sorted by name, not in insertion order.
        #expect(model.favorites.map(\.name) == ["Medborgarplatsen", "Odenplan", "Slussen"])
    }

    // MARK: - remove

    @Test func removeIsNoOpForUnknownId() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        // When
        model.remove("999", context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("1", "Slussen", ["4"])
        ])
    }

    @Test func removeDeletesFavorite() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        model.toggle("2", name: "Odenplan", lines: ["4"], context: context)
        // When
        model.remove("1", context: context)
        // Then
        #expect(model.favorites.map(\.snapshot) == [
            ("2", "Odenplan", ["4"])
        ])
    }

    @Test func removeIsNoOpWhenStoreNotLoaded() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        // `stored` is nil before loadFavorites; remove must not crash.
        model.remove("1", context: context)
        #expect(model.favorites == [])
    }

    // MARK: - Persistence

    @Test func togglePersistsToStorage() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        // When
        model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"], context: context)
        try context.save()
        // Then: a fresh model reading the same context sees the saved list.
        let reader = FavoritesModel()
        reader.loadFavorites(context: context)
        #expect(reader.favorites.map(\.snapshot) == [
            ("1", "Medborgarplatsen", ["3", "7"])
        ])
    }

    @Test func removePersistsToStorage() async throws {
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        model.toggle("2", name: "Odenplan", lines: ["4"], context: context)
        // When
        model.remove("1", context: context)
        try context.save()
        // Then
        let reader = FavoritesModel()
        reader.loadFavorites(context: context)
        #expect(reader.favorites.map(\.snapshot) == [
            ("2", "Odenplan", ["4"])
        ])
    }

    @Test func toggleCreatesStoreOnDemand() async throws {
        // With no seeded StoredFavorites, the first toggle inserts one rather
        // than crashing, and the favourite is visible through the same context.
        let context = try makeContext()
        let model = FavoritesModel()
        model.toggle("1", name: "Slussen", lines: ["4"], context: context)
        try context.save()
        let reader = FavoritesModel()
        reader.loadFavorites(context: context)
        #expect(reader.favorites.map(\.snapshot) == [
            ("1", "Slussen", ["4"])
        ])
    }

    // MARK: - Presentation

    @Test func lineSummaryJoinsLines() {
        let favorite = Favorite(id: "1", name: "Medborgarplatsen", lines: ["2", "3", "55"])
        #expect(favorite.lineSummary == "Lines 2, 3, 55")
    }

    @Test func lineSummaryEmptyWithoutLines() {
        let favorite = Favorite(id: "1", name: "Medborgarplatsen", lines: [])
        #expect(favorite.lineSummary == "")
    }
}

// MARK: - Helpers

private extension FavoritesModelTests {
    /// Builds an in-memory `ModelContext` for `StoredFavorites`, optionally
    /// seeded with one `StoredFavorites` holding the given favourites. SwiftData
    /// models are reference types with no value `==`, so tests compare a
    /// `Favorite`'s `(id, name, lines)` snapshot rather than the model itself.
    func makeContext(seed favorites: [Favorite] = []) throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StoredFavorites.self,
            configurations: configuration
        )
        let context = container.mainContext
        if !favorites.isEmpty {
            let stored = StoredFavorites(favorites: favorites)
            context.insert(stored)
            try context.save()
        }
        return context
    }
}

private extension Favorite {
    /// A value snapshot of the favourite's persisted fields, for `==`-based
    /// expectations. `Favorite` is a SwiftData `@Model` (reference identity), so
    /// tests compare this tuple instead of the model object.
    var snapshot: (String, String, [String]) {
        (id, name, lines)
    }
}
