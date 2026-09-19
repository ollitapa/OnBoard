import Foundation

/// This network is not connected to the internet.
struct DisconnectedNetwork: NetworkProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
