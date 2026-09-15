/// An interface for a storage that can asynchronously get and set values for given ID.
public protocol AsyncStorage<Value, Id> {
    associatedtype Value: Sendable
    associatedtype Id: Sendable

    func value(for id: Id) async throws -> Value?
    func saveValue(_ value: Value?, for id: Id) async throws
}
