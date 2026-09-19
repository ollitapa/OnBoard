import Foundation

extension NetworkProtocol {
    /// Wraps this network in a `PrintingNetwork` that prints every request
    /// and its response to the console.
    func printing() -> some NetworkProtocol {
        PrintingNetwork(wrapped: self)
    }
}

/// A decorating `NetworkProtocol` that prints the request it sends and the
/// response it receives. JSON response bodies are decoded with a generic
/// `JSONSerialization`-based pretty printer; non-JSON bodies print as plain
/// UTF-8 text.
struct PrintingNetwork: NetworkProtocol {

    let wrapped: any NetworkProtocol

    init(wrapped: any NetworkProtocol) {
        self.wrapped = wrapped
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        print("→ \(method(of: request)) \(request.url?.absoluteString ?? "<no url>")")
        let (data, response) = try await wrapped.data(for: request)
        print("← \(status(of: response))")
        print(body(of: data))
        print()
        return (data, response)
    }

    private func method(of request: URLRequest) -> String {
        request.httpMethod ?? "GET"
    }

    private func status(of response: URLResponse) -> String {
        guard let http = response as? HTTPURLResponse else {
            return "Response \(response)"
        }
        return "\(http.statusCode) \(http.url?.absoluteString ?? "")"
    }

    private func body(of data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        else {
            return String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
        }
        return String(data: pretty, encoding: .utf8) ?? "\(data.count) bytes"
    }
}
