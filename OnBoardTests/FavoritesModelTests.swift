import Testing
import Foundation
@testable import OnBoard

@MainActor
struct FavoritesModelTests {
    // MARK: - Loading

    @Test func loadFavoritesEmptyStoreStartsEmpty() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        // When
        await model.loadFavorites()
        // Then
        #expect(model.favorites == [])
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func loadFavoritesReadsPersistedList() async throws {
        let storage = MemoryStorage<Data, String>()
        storage.saveValue(
            try JSONEncoder().encode([Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])]),
            for: "favorites"
        )
        let model = FavoritesModel(fileStorage: storage)
        // When
        await model.loadFavorites()
        // Then
        #expect(model.favorites == [Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])])
        #expect(model.failure == nil)
    }

    @Test func loadFavoritesSurfacesStorageError() async {
        let model = FavoritesModel(fileStorage: ThrowingFavoriteStorage())
        // When
        await model.loadFavorites()
        // Then
        #expect(model.favorites == [])
        #expect(model.failure != nil)
        #expect(model.isLoading == false)
    }

    @Test func loadFavoritesSurfacesDecodeError() async throws {
        let storage = MemoryStorage<Data, String>()
        storage.saveValue(Data("not-json".utf8), for: "favorites")
        let model = FavoritesModel(fileStorage: storage)
        // When
        await model.loadFavorites()
        // Then
        #expect(model.favorites == [])
        #expect(model.failure != nil)
    }

    // MARK: - contains

    @Test func containsIsFalseBeforeSave() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.loadFavorites()
        #expect(model.contains("1") == false)
    }

    @Test func containsIsTrueAfterSave() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Slussen", lines: ["4"])
        #expect(model.contains("1") == true)
    }

    @Test func containsIsFalseAfterRemove() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Slussen", lines: ["4"])
        await model.toggle("1", name: "Slussen", lines: ["4"])
        #expect(model.contains("1") == false)
    }

    // MARK: - toggle

    @Test func toggleAddsFavorite() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        // When
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"])
        // Then
        #expect(model.favorites == [Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])])
        #expect(model.failure == nil)
    }

    @Test func toggleRemovesExistingFavorite() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"])
        await model.toggle("2", name: "Slussen", lines: ["4"])
        // When
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"])
        // Then
        #expect(model.favorites == [Favorite(id: "2", name: "Slussen", lines: ["4"])])
    }

    @Test func toggleDoesNotDuplicateFavorite() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"])
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"])
        await model.toggle("1", name: "Medborgarplatsen", lines: ["7"])
        // Then: still one entry, id-keyed; toggle removed then re-added.
        #expect(model.favorites.count == 1)
        #expect(model.favorites.first?.id == "1")
    }

    @Test func toggleUpdatesLineLabelsWhenReAdding() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"])
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3"]) // remove
        // When
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"])
        // Then
        #expect(model.favorites == [Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])])
    }

    @Test func togglePreservesInsertionOrder() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "First", lines: [])
        await model.toggle("2", name: "Second", lines: [])
        await model.toggle("3", name: "Third", lines: [])
        #expect(model.favorites.map(\.id) == ["1", "2", "3"])
    }

    // MARK: - remove

    @Test func removeIsNoOpForUnknownId() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Slussen", lines: ["4"])
        // When
        await model.remove("999")
        // Then
        #expect(model.favorites == [Favorite(id: "1", name: "Slussen", lines: ["4"])])
    }

    @Test func removeDeletesFavorite() async {
        let model = FavoritesModel(fileStorage: MemoryStorage<Data, String>())
        await model.toggle("1", name: "Slussen", lines: ["4"])
        await model.toggle("2", name: "Odenplan", lines: ["4"])
        // When
        await model.remove("1")
        // Then
        #expect(model.favorites == [Favorite(id: "2", name: "Odenplan", lines: ["4"])])
    }

    // MARK: - Persistence

    @Test func togglePersistsToStorage() async throws {
        let storage = MemoryStorage<Data, String>()
        let model = FavoritesModel(fileStorage: storage)
        // When
        await model.toggle("1", name: "Medborgarplatsen", lines: ["3", "7"])
        // Then: a fresh model reading the same store sees the saved list.
        let reader = FavoritesModel(fileStorage: storage)
        await reader.loadFavorites()
        #expect(reader.favorites == [Favorite(id: "1", name: "Medborgarplatsen", lines: ["3", "7"])])
    }

    @Test func removePersistsToStorage() async throws {
        let storage = MemoryStorage<Data, String>()
        let model = FavoritesModel(fileStorage: storage)
        await model.toggle("1", name: "Slussen", lines: ["4"])
        await model.toggle("2", name: "Odenplan", lines: ["4"])
        // When
        await model.remove("1")
        // Then
        let reader = FavoritesModel(fileStorage: storage)
        await reader.loadFavorites()
        #expect(reader.favorites == [Favorite(id: "2", name: "Odenplan", lines: ["4"])])
    }

    @Test func toggleRollsBackOnSaveError() async {
        let model = FavoritesModel(fileStorage: ThrowingFavoriteStorage(allowRead: true))
        await model.toggle("1", name: "Slussen", lines: ["4"])
        // When: the save throws, so the in-memory list rolls back.
        await model.toggle("2", name: "Odenplan", lines: ["4"])
        // Then
        #expect(model.favorites == [Favorite(id: "1", name: "Slussen", lines: ["4"])])
        #expect(model.failure != nil)
    }

    // MARK: - Equality / identity

    @Test func favoritesEqualByIdOnly() {
        let a = Favorite(id: "1", name: "Slussen", lines: ["4"])
        let b = Favorite(id: "1", name: "Medborgarplatsen", lines: ["3"])
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func favoritesNotEqualByDifferentId() {
        let a = Favorite(id: "1")
        let b = Favorite(id: "2")
        #expect(a != b)
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

/// A `AsyncStorage<Data, String>` that throws on every operation, optionally
/// allowing reads so a first favorite can be saved before a failing write
/// tests the rollback path.
private struct ThrowingFavoriteStorage: AsyncStorage {
    typealias Value = Data
    typealias Id = String

    let allowRead: Bool

    init(allowRead: Bool = false) {
        self.allowRead = allowRead
    }

    func value(for id: Id) async throws -> Data? {
        guard allowRead else { throw StorageError() }
        return nil
    }

    func saveValue(_ value: Data?, for id: Id) async throws {
        throw StorageError()
    }

    private struct StorageError: Error {}
}
