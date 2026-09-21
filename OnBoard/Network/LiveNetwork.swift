import Foundation

/// Production implementation of NetworkProtocol.
/// Uses URLSession.shared to perform actual network requests.
struct LiveNetwork: NetworkProtocol {
    /// Fetches data for a given URLRequest using URLSession.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the data and URLResponse from the server
    /// - Throws: An error if the network request fails
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch URLError.cancelled {
            throw CancellationError()  // Convert to CancellationError for consistency
        } catch {
            throw error  // Propagate other errors as-is
        }
    }
}
