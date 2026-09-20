import Foundation

/// Production implementation of NetworkProtocol.
/// Uses URLSession.shared to perform actual network requests.
///
/// A transport failure — a timeout, a dropped connection, a missing route to
/// the host — is retried once per ``retryDelays`` entry with a short backoff,
/// so one blip on a flaky connection doesn't fail the whole refresh. HTTP
/// statuses are never retried: `Trafiklab.decode` turns a non-2xx response
/// into a `TrafiklabHTTPError` for the caller's failure message, and a 429
/// must be honored with a pause (`Designs/API-Instructions.md`, "back off and
/// retry with delay rather than hammering"), not re-sent immediately.
struct LiveNetwork: NetworkProtocol {
    /// The pause before each retry — short, and doubling — so a blip is
    /// retried quickly without hammering the API. The first entry is the
    /// initial attempt, made without waiting.
    private let retryDelays: [Duration?] = [nil, .milliseconds(200), .milliseconds(400)]

    /// Fetches data for a given URLRequest using URLSession.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the data and URLResponse from the server
    /// - Throws: The last error if every attempt fails
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: (any Error)?
        for delay in retryDelays {
            do {
                if let delay { try await Task.sleep(for: delay) }
                return try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                guard (error as? URLError)?.isTransientTransportFailure == true else { throw error }
            }
        }
        throw lastError ?? URLError(.timedOut)
    }
}

extension URLError {

    /// Whether the failure is a transient transport blip worth another
    /// attempt — a timeout, a dropped or missing connection — as opposed to
    /// something a retry can't fix (a cancelled task, a malformed request, a
    /// bad response). Non-`URLError` failures are never retried by the caller.
    var isTransientTransportFailure: Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
