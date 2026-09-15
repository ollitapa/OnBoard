import Foundation

extension AsyncStorage where Self.Value == Data {

    /// Makes a storage that encodes and decodes a value to Data
    /// - Parameters:
    ///   - valueType: Type of the value
    ///   - encoder: JSONEncoder
    ///   - decoder: JSONDecoder
    /// - Returns: Storage
    public func codable<CodableType: Codable & Sendable>(
        for valueType: CodableType.Type,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> some AsyncStorage<CodableType, Self.Id> {
        CodableStorage(original: self, jsonDecoder: decoder, jsonEncoder: encoder)
    }
}

struct CodableStorage<Value: Codable & Sendable, Original: AsyncStorage>: AsyncStorage
where Original.Value == Data {

    let original: Original
    let jsonDecoder: JSONDecoder
    let jsonEncoder: JSONEncoder

    func value(for id: Original.Id) async throws -> Value? {
        let data = try await original.value(for: id)
        return try data.map { try jsonDecoder.decode(Value.self, from: $0) }
    }

    func saveValue(_ value: Value?, for id: Original.Id) async throws {
        try await original.saveValue(value.map { try jsonEncoder.encode($0) }, for: id)
    }
}
