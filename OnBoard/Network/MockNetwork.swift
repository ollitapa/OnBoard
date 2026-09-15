import Foundation

@MainActor
struct MockNetwork: NetworkProtocol {
    static func makeResponse(data: Data, response: URLResponse = HTTPURLResponse()) -> (Data, URLResponse) {
        (data, response)
    }

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

    struct TestableRequest {
        var url: URL?
        var httpMethod: String?
        var httpBody: Data?

        init(request: URLRequest) {
            self.url = request.url
            self.httpMethod = request.httpMethod
            self.httpBody = request.httpBody
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
