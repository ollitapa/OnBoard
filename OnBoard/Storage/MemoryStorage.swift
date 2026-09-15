import os

struct MemoryStorage<Value: Hashable & Sendable, Id: Hashable & Sendable>: AsyncStorage<Value, Id> {

    private let memory = OSAllocatedUnfairLock<[Id: Value]>(initialState: [:])

    func value(for id: Id) -> Value? {
        memory.withLock { $0[id] }
    }

    func saveValue(_ value: Value?, for id: Id) {
        memory.withLock { $0[id] = value }
    }
}
