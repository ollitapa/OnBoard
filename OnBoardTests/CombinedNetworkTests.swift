import Testing
import Foundation
@testable import OnBoard

struct CombinedNetworkTests {

    @Test func routesRequestToMatchingBaseURL() async throws {
        let nearby = MockNearbyServer(
            baseURL: URL(string: "https://api.example.com")!,
            stops: [Stop(id: "1", name: "Central Station", latitude: 0, longitude: 0)]
        )
        // A network whose handler records whether it was consulted; sharing
        // a reference avoids capturing a mutable variable in a @Sendable
        // closure.
        actor Probe {
            var handled = false
            func mark() { handled = true }
            func value() -> Bool { handled }
        }
        let probe = Probe()
        var other = MockNetwork()
        other.registerHandler { _ in
            await probe.mark()
            return MockNetwork.makeResponse(json: "{}")
        }

        let network = CombinedNetwork(routes: [
            .init(baseURL: nearby.baseURL, network: nearby),
            .init(baseURL: URL(string: "https://other.example.com")!, network: other)
        ])

        let request = URLRequest(url: URL(string: "https://api.example.com/stops/nearby")!)
        let (data, _) = try await network.data(for: request)

        let stops = try JSONDecoder().decode([Stop].self, from: data)
        #expect(stops.count == 1)
        #expect(stops.first?.name == "Central Station")
        #expect(await probe.value() == false)
    }

    @Test func fallsBackWhenNoRouteMatches() async throws {
        let fallback = MockNearbyServer(
            baseURL: URL(string: "https://fallback.example.com")!,
            stops: [Stop(id: "9", name: "Fallback Stop", latitude: 1, longitude: 1)]
        )
        let network = CombinedNetwork(
            routes: [.init(baseURL: fallback.baseURL, network: fallback)],
            fallback: fallback
        )

        let request = URLRequest(url: URL(string: "https://unrouted.example.com/stops/nearby")!)
        let (data, _) = try await network.data(for: request)

        let stops = try JSONDecoder().decode([Stop].self, from: data)
        #expect(stops.first?.name == "Fallback Stop")
    }

    @Test func throwsWhenNoRouteOrFallback() async throws {
        let network = CombinedNetwork(routes: [
            .init(baseURL: URL(string: "https://api.example.com")!, network: MockNearbyServer())
        ])
        // The request URL carries a credential in its query, like the real
        // Trafiklab requests do.
        let request = URLRequest(url: URL(string: "https://unrouted.example.com/stops/nearby?key=SECRET")!)

        do {
            _ = try await network.data(for: request)
            Issue.record("Expected NoRouteConfigured")
        } catch let error as NoRouteConfigured {
            // Then: the error identifies the unmatched route without leaking
            // the credential from the request's query.
            #expect(error.host == "https://unrouted.example.com")
            #expect(error.path == "/stops/nearby")
        }
    }

    @Test func usesFirstMatchingRouteInOrder() async throws {
        let first = MockNearbyServer(
            baseURL: URL(string: "https://api.example.com")!,
            stops: [Stop(id: "a", name: "First", latitude: 0, longitude: 0)]
        )
        let second = MockNearbyServer(
            baseURL: URL(string: "https://api.example.com")!,
            stops: [Stop(id: "b", name: "Second", latitude: 0, longitude: 0)]
        )

        let network = CombinedNetwork(routes: [
            .init(baseURL: first.baseURL, network: first),
            .init(baseURL: second.baseURL, network: second)
        ])

        let request = URLRequest(url: URL(string: "https://api.example.com/stops/nearby")!)
        let (data, _) = try await network.data(for: request)

        let stops = try JSONDecoder().decode([Stop].self, from: data)
        #expect(stops.first?.name == "First")
    }
}
