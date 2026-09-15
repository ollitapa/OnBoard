import Foundation

/// Mock implementation of NetworkProtocol for testing.
/// Runs on MainActor to safely update UI from tests.
@MainActor
struct MockNetwork: NetworkProtocol {
    /// Creates a response tuple with the given data and response.
    /// - Parameters:
    ///   - data: The data to return
    ///   - response: The URLResponse to return (defaults to empty HTTPURLResponse)
    /// - Returns: A tuple of (Data, URLResponse) for use in handlers
    static func makeResponse(data: Data, response: URLResponse = HTTPURLResponse()) -> (Data, URLResponse) {
        (data, response)
    }

    /// Creates a response tuple from a JSON dictionary.
    /// - Parameters:
    ///   - json: The JSON dictionary to encode
    ///   - statusCode: The HTTP status code for the response (defaults to 200)
    /// - Returns: A tuple of (Data, URLResponse) for use in handlers
    static func makeResponse(json: [String: Any], statusCode: Int = 200) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: json)
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
    struct TestableRequest: Equatable {
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
    }

    /// Mutable storage shared by reference so that request recording made
    /// inside the non-mutating `data(for:)` protocol method stays visible
    /// to the test that owns the mock.
    @MainActor
    private final class Storage: @unchecked Sendable {
        var testableRequests: [TestableRequest] = []
        var handlers: [(URLRequest) async throws -> (Data, URLResponse)?] = []
    }

    private let storage = Storage()

    /// All requests that have been made through this mock, for verification
    var testableRequests: [TestableRequest] {
        storage.testableRequests
    }

    /// Clears all tracked requests, useful for resetting between tests
    mutating func reset() {
        storage.testableRequests.removeAll()
    }

    /// Registers a handler to provide mock responses.
    /// Handlers are called in the order they were registered.
    /// - Parameter handler: A closure that takes a URLRequest and returns an optional (Data, URLResponse) tuple
    mutating func registerHandler(_ handler: @escaping (URLRequest) async throws -> (Data, URLResponse)?) {
        storage.handlers.append(handler)
    }

    /// Fetches data for a given URLRequest, recording the request and checking handlers.
    /// - Parameter request: The URLRequest to mock
    /// - Returns: A tuple containing the data and URLResponse from the first matching handler
    /// - Throws: NoResponseConfigured if no handler returns a response
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        storage.testableRequests.append(TestableRequest(request: request))

        for handler in storage.handlers {
            if let response = try await handler(request) {
                return response
            }
        }

        throw NoResponseConfigured()
    }
}

/// Error thrown when no handler provides a response for a request
struct NoResponseConfigured: Error { }
