import Testing
import Foundation
@testable import OnBoard

struct PrintingNetworkTests {

    @Test func forwardsRequestAndResponseUntouched() async throws {
        var mock = MockNetwork()
        mock.registerHandler { request in
            MockNetwork.makeResponse(
                json: #"{"name": "Central Station"}"#,
                statusCode: 200
            )
        }
        let network = mock.printing()
        let request = URLRequest(url: URL(string: "https://api.example.com/stops/nearby")!)

        let (data, response) = try await network.data(for: request)

        #expect(try JSONSerialization.jsonObject(with: data) as? [String: String] == ["name": "Central Station"])
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let sent = mock.testableRequests
        #expect(sent.first?.url == request.url)
    }

    @Test func prettyPrintsJSONResponseBodies() async throws {
        var mock = MockNetwork()
        mock.registerHandler { _ in
            MockNetwork.makeResponse(
                json: #"{"b": 2, "a": 1}"#,
                statusCode: 200
            )
        }
        let network = PrintingNetwork(wrapped: mock)
        let request = URLRequest(url: URL(string: "https://api.example.com")!)

        let (data, _) = try await network.data(for: request)

        #expect(try JSONSerialization.jsonObject(with: data) as? [String: Int] == ["a": 1, "b": 2])
    }

    @Test func passesNonJSONBodiesThrough() async throws {
        var mock = MockNetwork()
        mock.registerHandler { _ in
            (Data("not json".utf8), MockNetwork.makeResponse(json: "{}").1)
        }
        let network = mock.printing()
        let request = URLRequest(url: URL(string: "https://api.example.com")!)

        let (data, _) = try await network.data(for: request)

        #expect(String(data: data, encoding: .utf8) == "not json")
    }
}
