import Foundation

/// A protocol defining network operations for dependency injection.
/// Conforms to Sendable to allow safe use across actor boundaries.
protocol NetworkProtocol: Sendable {
    /// Fetches data for a given URLRequest.
    /// - Parameter request: The URLRequest to execute
    /// - Returns: A tuple containing the data and URLResponse
    /// - Throws: An error if the network request fails
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
