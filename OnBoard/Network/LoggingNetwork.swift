import Foundation
import OSLog
import Synchronization

extension NetworkProtocol {
    /// Wraps this network in a `LoggingNetwork` that logs every request
    /// and its response through OSLog.
    func logging() -> some NetworkProtocol {
        LoggingNetwork(wrapped: self)
    }
}

/// A decorating `NetworkProtocol` that logs the request it sends and the
/// response it receives through OSLog. Every request/response pair is tagged
/// with a `#number` from a mutex-guarded counter, so a response can be matched
/// to its request even when several calls are in flight and their logs
/// interleave. JSON response bodies are decoded with a generic
/// `JSONSerialization`-based pretty printer; non-JSON bodies log as plain
/// UTF-8 text.
struct LoggingNetwork: NetworkProtocol {

    let wrapped: any NetworkProtocol

    private let counter = RequestCounter()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnBoard",
        category: "LoggingNetwork"
    )

    init(wrapped: any NetworkProtocol) {
        self.wrapped = wrapped
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let number = counter.next()
        logger.log("→ #\(number, privacy: .public) \(method(of: request), privacy: .public) \(requestLine(of: request), privacy: .public)")
        let (data, response) = try await wrapped.data(for: request)
        logger.log("← #\(number, privacy: .public) \(status(of: response), privacy: .public)")
        logger.log("\(body(of: data), privacy: .public)")
        return (data, response)
    }

    /// A thread-safe monotonically increasing counter, held by reference so
    /// every request through the wrapper draws from the same sequence even
    /// when calls run concurrently.
    final class RequestCounter: Sendable {
        private let count = Mutex<Int>(0)

        /// Returns the next number in the sequence, starting at 1.
        func next() -> Int {
            count.withLock {
                $0 += 1
                return $0
            }
        }
    }

    private func method(of request: URLRequest) -> String {
        request.httpMethod ?? "GET"
    }

    /// The request's scheme, host, and path. The query is redacted because it
    /// carries the API key and OSLog output persists in the unified log.
    private func requestLine(of request: URLRequest) -> String {
        guard let url = request.url else { return "<no url>" }
        var line = "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
        if url.query != nil {
            line += "?<redacted query>"
        }
        return line
    }

    private func status(of response: URLResponse) -> String {
        guard let http = response as? HTTPURLResponse else {
            return "Response \(response)"
        }
        return "\(http.statusCode) \(http.url?.path ?? "")"
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
