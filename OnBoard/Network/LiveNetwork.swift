import Foundation

struct LiveNetwork: NetworkProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
