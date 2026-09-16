import Foundation
import Synchronization

/// Mock implementation of NetworkProtocol for testing.
/// State is guarded by a mutex so the mock can be used safely from any
/// actor without being pinned to the main actor.
struct MockNetwork: NetworkProtocol {

    /// Creates a response tuple from an Encodable value.
    /// - Parameters:
    ///   - value: The Encodable value to encode as JSON
    ///   - statusCode: The HTTP status code for the response (defaults to 200)
    /// - Returns: A tuple of (Data, URLResponse) for use in handlers
    static func makeResponse(json: String, statusCode: Int = 200) -> (Data, URLResponse) {
        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
    /// Creates a response tuple from an Encodable value.
    /// - Parameters:
    ///   - value: The Encodable value to encode as JSON
    ///   - statusCode: The HTTP status code for the response (defaults to 200)
    /// - Returns: A tuple of (Data, URLResponse) for use in handlers
    static func makeJSONResponse<T: Encodable>(_ value: T, statusCode: Int = 200) -> (Data, URLResponse) {
        let data = try! JSONEncoder().encode(value)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    /// A request structure that can be compared for testing purposes.
    /// Captures the essential parts of a URLRequest for verification.
    struct TestableRequest: Equatable, Sendable {
        /// The URL of the request
        var url: URL?
        /// The HTTP method (GET, POST, etc.)
        var httpMethod: String?
        /// The request body data
        var httpBody: Data?

        /// Creates a TestableRequest from a URLRequest.
        /// - Parameter request: The URLRequest to capture
        init(request: URLRequest) {
            self.url = request.url
            self.httpMethod = request.httpMethod
            self.httpBody = request.httpBody
        }

        /// Creates a TestableRequest from its captured fields.
        /// - Parameters:
        ///   - url: The URL of the request
        ///   - httpMethod: The HTTP method (GET, POST, etc.)
        ///   - httpBody: The request body data
        init(url: URL?, httpMethod: String?, httpBody: Data?) {
            self.url = url
            self.httpMethod = httpMethod
            self.httpBody = httpBody
        }
    }

    /// Mutable storage shared by reference and guarded by a mutex so that
    /// request recording made inside the non-mutating `data(for:)` protocol
    /// method stays visible to the test that owns the mock, without pinning
    /// the mock to the main actor.
    private final class Storage: Sendable {
        private struct State: Sendable {
            var testableRequests: [TestableRequest] = []
            var handlers: [@Sendable (URLRequest) async throws  -> (Data, URLResponse)?] = []
        }

        private let state = Mutex(State())

        func record(_ request: TestableRequest) {
            state.withLock { $0.testableRequests.append(request) }
        }

        func resetRequests() {
            state.withLock { $0.testableRequests.removeAll() }
        }

        func appendHandler(_ handler: @Sendable @escaping  (URLRequest) async throws -> (Data, URLResponse)?) {
            state.withLock { $0.handlers.append(handler) }
        }

        func snapshotRequests() -> [TestableRequest] {
            state.withLock { $0.testableRequests }
        }

        func snapshotHandlers() -> [@Sendable (URLRequest) async throws -> (Data, URLResponse)?] {
            state.withLock { $0.handlers }
        }
    }

    private let storage = Storage()

    /// All requests that have been made through this mock, for verification
    var testableRequests: [TestableRequest] {
        storage.snapshotRequests()
    }

    /// Clears all tracked requests, useful for resetting between tests
    mutating func reset() {
        storage.resetRequests()
    }

    /// Registers a handler to provide mock responses.
    /// Handlers are called in the order they were registered.
    /// - Parameter handler: A closure that takes a URLRequest and returns an optional (Data, URLResponse) tuple
    mutating func registerHandler(_ handler: @Sendable @escaping (URLRequest) async throws -> (Data, URLResponse)?) {
        storage.appendHandler(handler)
    }

    /// Fetches data for a given URLRequest, recording the request and checking handlers.
    /// - Parameter request: The URLRequest to mock
    /// - Returns: A tuple containing the data and URLResponse from the first matching handler
    /// - Throws: NoResponseConfigured if no handler returns a response
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        storage.record(TestableRequest(request: request))

        for handler in storage.snapshotHandlers() {
            if let response = try await handler(request) {
                return response
            }
        }

        throw NoResponseConfigured()
    }
}

/// Error thrown when no handler provides a response for a request
struct NoResponseConfigured: Error { }
