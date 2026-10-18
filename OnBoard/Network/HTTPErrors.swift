import Foundation

/// A non-2xx HTTP response, reported before any decoding is attempted.
/// Carries the status code and raw body so a failure message describes the
/// server's answer (e.g. a quota or key error) instead of a decoding error
/// on the error body.
struct UnexpectedStatusError: Error, Sendable, CustomStringConvertible {
    let statusCode: Int
    let body: Data

    var description: String {
        let body = String(data: body, encoding: .utf8) ?? ""
        return body.isEmpty
            ? "Unexpected status \(statusCode)"
            : "Unexpected status \(statusCode): \(body)"
    }
}

/// A response that was not an `HTTPURLResponse`, so no status exists to
/// check — the request never reached an HTTP server or the transport
/// returned a bare response. Reported before any decoding is attempted.
struct NoHTTPResponseError: Error, Sendable, CustomStringConvertible {
    var description: String {
        "No HTTP response (missing status)"
    }
}

extension NetworkProtocol {
    /// Performs a request, validates the HTTP response, and returns the
    /// body. A non-2xx status throws `UnexpectedStatusError`; a response
    /// without an HTTP status at all throws `NoHTTPResponseError`. Use this
    /// instead of `data(for:)` whenever the body will be decoded, so a
    /// server error surfaces as itself rather than as a `DecodingError` on
    /// its error body.
    func httpData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NoHTTPResponseError()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UnexpectedStatusError(statusCode: http.statusCode, body: data)
        }
        return data
    }
}
