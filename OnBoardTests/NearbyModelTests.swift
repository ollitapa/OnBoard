import Testing
import Foundation
@testable import OnBoard

struct NearbyModelTests {

    @Test func loadStopsSuccess() async throws {
        // Given
        let expectedStops = [
            Stop(id: "1", name: "Central Station", latitude: 60.1756, longitude: 24.9420),
            Stop(id: "2", name: "Market Square", latitude: 60.1699, longitude: 24.9384)
        ]
        
        var mockNetwork = MockNetwork()
        let expectedURL = URL(string: "https://api.example.com/stops/nearby")!
        let expectedRequest = MockNetwork.TestableRequest(url: expectedURL, httpMethod: "GET", httpBody: nil)
        
        mockNetwork.registerHandler { request in
            if request.url == expectedURL && request.httpMethod == "GET" {
                return MockNetwork.makeJSONResponse(expectedStops)
            }
            return nil
        }
        
        let model = NearbyModel()

        // When
        await model.loadStops(network: mockNetwork)

        // Then
        #expect(model.stops == expectedStops)
        #expect(model.failure == nil)
        
        #expect(mockNetwork.testableRequests.count == 1)
        #expect(mockNetwork.testableRequests[0] == expectedRequest)
    }

    @Test func loadStopsEmptyResponse() async throws {
        // Given
        var mockNetwork = MockNetwork()
        let expectedURL = URL(string: "https://api.example.com/stops/nearby")!
        
        mockNetwork.registerHandler { request in
            if request.url == expectedURL && request.httpMethod == "GET" {
                return MockNetwork.makeJSONResponse([Stop]())
            }
            return nil
        }
        
        let model = NearbyModel()

        // When
        await model.loadStops(network: mockNetwork)

        // Then
        #expect(model.stops == [])
        #expect(model.failure == nil)
    }

    @Test func loadStopsNetworkError() async throws {
        // Given
        var mockNetwork = MockNetwork()
        // No handlers registered, will throw NoResponseConfigured
        
        let model = NearbyModel()

        // When
        await model.loadStops(network: mockNetwork)

        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
    }

    @Test func loadStopsInvalidJSON() async throws {
        // Given
        var mockNetwork = MockNetwork()
        let expectedURL = URL(string: "https://api.example.com/stops/nearby")!
        
        mockNetwork.registerHandler { request in
            if request.url == expectedURL && request.httpMethod == "GET" {
                return MockNetwork.makeResponse(json: ["invalid": "json"])
            }
            return nil
        }
        
        let model = NearbyModel()

        // When
        await model.loadStops(network: mockNetwork)

        // Then
        #expect(model.stops == [])
        #expect(model.failure != nil)
    }

}
