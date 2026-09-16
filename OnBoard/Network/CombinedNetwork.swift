import Foundation

/// Routes requests to one of several underlying `NetworkProtocol`s based on
/// the base URL each child is responsible for.
///
/// A request is sent to the first child whose base URL shares the same
/// scheme and host as the request URL. Requests that match no child are
/// sent to the fallback, if one was provided; otherwise `data(for:)` throws
/// `NoRouteConfigured`.
struct CombinedNetwork: NetworkProtocol {

    /// A network endpoint paired with the base URL it is responsible for.
    /// Matching uses the base URL's scheme and host.
    struct Route: Sendable {
        let baseURL: URL
        let network: any NetworkProtocol
    }

    private let routes: [Route]
    private let fallback: (any NetworkProtocol)?

    /// Creates a combined network from an ordered list of routes.
    /// - Parameters:
    ///   - routes: The base URL / network pairs, consulted in order.
    ///   - fallback: An optional network used when no route matches.
    init(routes: [Route], fallback: (any NetworkProtocol)? = nil) {
        self.routes = routes
        self.fallback = fallback
    }

    /// Convenience initializer taking a list of routes with no fallback.
    init(_ routes: Route...) {
        self.init(routes: routes, fallback: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let route = route(for: request) {
            return try await route.network.data(for: request)
        }
        if let fallback {
            return try await fallback.data(for: request)
        }
        throw NoRouteConfigured(request: request)
    }

    private func route(for request: URLRequest) -> Route? {
        guard let url = request.url else { return nil }
        return routes.first { route in
            url.scheme == route.baseURL.scheme && url.host == route.baseURL.host
        }
    }
}

/// Error thrown when no route matches a request and no fallback is configured.
struct NoRouteConfigured: Error {
    let request: URLRequest
}
