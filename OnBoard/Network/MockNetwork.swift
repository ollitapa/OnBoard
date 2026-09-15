import Foundation

@MainActor
struct MockNetwork: NetworkProtocol {

    struct TestableRequest: Equatable {
        var requestURL: String

        // Add simple equatable properties for testing purposes
    }

    var testableRequests: [TestableRequest] = []

    var handlers: [(URLRequest) async throws -> (Data, URLResponse)?] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {

        // Find first that responds
        // ...

        throw NoResponseConfigured()
    }
}

struct NoResponseConfigured: Error { }
