import Foundation

protocol NetworkProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
