import Foundation
import Synchronization

extension NetworkProtocol {
    /// Wraps this network in a `PrintingNetwork` that prints every request
    /// and its response to the console.
    func printing() -> some NetworkProtocol {
        PrintingNetwork(wrapped: self)
    }
}

/// A decorating `NetworkProtocol` that prints the request it sends and the
/// response it receives. Every request/response pair is tagged with a
/// `#number` from a mutex-guarded counter, so a response can be matched to
/// its request even when several calls are in flight and their logs
/// interleave. JSON response bodies are decoded with a generic
/// `JSONSerialization`-based pretty printer; non-JSON bodies print as plain
/// UTF-8 text.
struct PrintingNetwork: NetworkProtocol {

    let wrapped: any NetworkProtocol

    private let counter = RequestCounter()

    init(wrapped: any NetworkProtocol) {
        self.wrapped = wrapped
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let number = counter.next()
        print("→ #\(number) \(method(of: request)) \(request.url?.absoluteString ?? "<no url>")")
        let (data, response) = try await wrapped.data(for: request)
        print("← #\(number) \(status(of: response))")
        print(body(of: data))
        print()
        return (data, response)
    }

    /// A thread-safe monotonically increasing counter, held by reference so
    /// every request through the wrapper draws from the same sequence even
    /// when calls run concurrently.
    final class RequestCounter: Sendable {
        private let count = Mutex(0)

        /// Returns the next number in the sequence, starting at 1.
        func next() -> Int {
            count.withLock { $0 += 1 }
        }
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
