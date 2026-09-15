import Foundation

@MainActor
struct MockNetwork: NetworkProtocol {

    struct TestableRequest: Equatable {
        var url: URL?
        var httpMethod: String?
        var httpBody: Data?

        init(request: URLRequest) {
            self.url = request.url
            self.httpMethod = request.httpMethod
            self.httpBody = request.httpBody
        }

        static func == (lhs: TestableRequest, rhs: TestableRequest) -> Bool {
            lhs.url == rhs.url &&
            lhs.httpMethod == rhs.httpMethod &&
            lhs.httpBody == rhs.httpBody
        }
    }

    var testableRequests: [TestableRequest] = []

    var handlers: [(URLRequest) async throws -> (Data, URLResponse)?] = []

    mutating func reset() {
        testableRequests.removeAll()
    }

    mutating func registerHandler(_ handler: @escaping (URLRequest) async throws -> (Data, URLResponse)?) {
        handlers.append(handler)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        testableRequests.append(TestableRequest(request: request))

        for handler in handlers {
            if let response = try await handler(request) {
                return response
            }
        }

        throw NoResponseConfigured()
    }
}

struct NoResponseConfigured: Error { }
