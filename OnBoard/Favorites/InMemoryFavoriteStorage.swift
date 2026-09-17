import Foundation
import os

/// An in-memory `AsyncStorage` for the favourites list, used as the
/// environment default (previews) and by tests.
///
/// A dedicated type rather than the generic ``MemoryStorage`` because
/// `MemoryStorage` constrains `Value` to `Hashable`, and `[Favorite]` is not
/// `Hashable`. State is guarded by a lock, mirroring `MemoryStorage`, so the
/// store is safe to share across actors without pinning it to the main actor.
struct InMemoryFavoriteStorage: AsyncStorage {
    typealias Value = [Favorite]
    typealias Id = String

    private let memory = OSAllocatedUnfairLock<[Id: Value]>(initialState: [:])

    func value(for id: Id) async throws -> Value? {
        memory.withLock { $0[id] }
    }

    func saveValue(_ value: Value?, for id: Id) async throws {
        memory.withLock { $0[id] = value }
    }
}
