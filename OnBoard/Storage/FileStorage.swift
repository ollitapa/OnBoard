import Foundation

/// A storage for files in given directory. Use in counjunction with MemoryStorage to prevent unnecessary reads.
///
///     struct Stuff: Codable { ... }
///
///     let storage = MemoryStorage<Stuff, String>().combined(
///         with: FileStorage(searchPath: .cachesDirectory, domain: .userDomainMask)
///             .codable(for: Stuff.self)
///         )
///
public struct FileStorage: AsyncStorage, Sendable {
    public typealias Value = Data
    public typealias Id = String

    private let directory: @Sendable () throws -> URL
    private let queue = DispatchQueue(label: "com.storage.file")

    public init(directory: URL) {
        self.directory = { directory }
    }

    public init(searchPath: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask) {
        self.directory = {
            try FileManager.default.url(for: searchPath, in: domain, appropriateFor: nil, create: false)
        }
    }

    public init(securityApplicationGroupIdentifier: String) {
        self.directory = {
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: securityApplicationGroupIdentifier)
                    else {
                throw NoContainerFound(securityApplicationGroupIdentifier: securityApplicationGroupIdentifier)
            }
            return container
        }
    }

    public func value(for filename: String) async throws -> Data? {
        let directory = directory
        return try await withCheckedThrowingContinuation { continuation in
            // We should not do file-operations in the Cooperative Thread pool,
            // so we spin up our own thread.
            queue.async {
                do {
                    let documentsDirectory = try directory()
                    let fileURL = documentsDirectory.appendingPathComponent(filename)

                    if FileManager.default.fileExists(atPath: fileURL.relativePath) {
                        continuation.resume(returning: try Data(contentsOf: fileURL))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }

        }
    }

    public func saveValue(_ data: Data?, for filename: String) async throws {
        let directory = directory
        try await withCheckedThrowingContinuation { continuation in
            // We should not do file-operations in the Cooperative Thread pool,
            // so we spin up our own thread.
            queue.async {
                do {
                    let documentsDirectory = try directory()
                    let fileURL = documentsDirectory.appendingPathComponent(filename)

                    if let data {
                        try data.write(to: fileURL)
                    } else if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct NoContainerFound: Error {
    var securityApplicationGroupIdentifier: String
}
