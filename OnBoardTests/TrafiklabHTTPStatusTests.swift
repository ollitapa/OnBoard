import Testing
import Foundation
@testable import OnBoard

/// Tests the HTTP status check in `Trafiklab.decode`: a non-2xx response
/// throws `TrafiklabHTTPError` before the body reaches the JSON decoder, so
/// a 401, a 429, a 5xx, or an HTML error page never surfaces as a raw
/// `SwiftDecodingError` dump.
struct TrafiklabHTTPStatusTests {
    /// A client with keys, so tests exercise the request-building path without
    /// depending on the host bundle's `Secrets.env`.
    private func makeAPI(_ network: some NetworkProtocol) -> Trafiklab {
        Trafiklab(
            network: network,
            secrets: Secrets(parsing: """
                TRAFIKLAB_REALTIME_KEY=test-realtime-key
                TRAFIKLAB_RESROBOT_KEY=test-resrobot-key
                """)
        )
    }

    @Test func decodesTwoHundredResponses() async throws {
        // Given: a mock serving the Timetables departures envelope.
        let network = MockTrafiklabService(departuresByAreaId: ["740000001": "[]"])
        let api = makeAPI(network)

        // When/Then: a 200 body decodes into the response model.
        let response = try await api.departures(at: "740000001")
        #expect(response.departures == [])
    }

    @Test func throwsHTTPErrorForNonTwoHundredStatus() async throws {
        // Given: a mock answering 429 (quota exceeded) with an error body.
        var network = MockNetwork()
        network.registerHandler { _ in
            MockNetwork.makeResponse(json: #"{"error": "Too many requests"}"#, statusCode: 429)
        }
        let api = makeAPI(network)

        // When: the departures load is attempted.
        // Then: the status is surfaced as a TrafiklabHTTPError, not a
        // decoding error from the error body.
        await #expect(throws: TrafiklabHTTPError.self) {
            _ = try await api.departures(at: "740000001")
        }
    }

    @Test func httpErrorCarriesStatusAndPathWithoutCredentials() async throws {
        // Given: a mock answering 401 (bad key) with an HTML error page, the
        // shape a misconfigured key produces in practice. The response carries
        // the request URL so the error's path can be asserted.
        var network = MockNetwork()
        network.registerHandler { request in
            guard let url = request.url else { throw NoResponseConfigured() }
            return (
                Data("<html>Unauthorized</html>".utf8),
                HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            )
        }
        let api = makeAPI(network)

        // When: the departures load is attempted.
        var thrown: TrafiklabHTTPError?
        do {
            _ = try await api.departures(at: "740000001")
        } catch let error as TrafiklabHTTPError {
            thrown = error
        } catch {
            Issue.record("Expected TrafiklabHTTPError, got \(error)")
        }

        // Then: the error carries the status code and the request's path —
        // never the query, which holds the API key.
        let error = try #require(thrown)
        #expect(error.statusCode == 401)
        #expect(error.path == "/v1/departures/740000001")
        #expect(!String(describing: error).contains("test-realtime-key"))
    }

    @Test func throwsHTTPErrorForServerErrors() async throws {
        // Given: a mock answering 503, the shape of a Trafiklab outage.
        var network = MockNetwork()
        network.registerHandler { _ in
            MockNetwork.makeResponse(json: "{}", statusCode: 503)
        }
        let api = makeAPI(network)

        // When/Then: the outage surfaces as a TrafiklabHTTPError.
        await #expect(throws: TrafiklabHTTPError.self) {
            _ = try await api.nearbyStops(latitude: 59.31, longitude: 18.07)
        }
    }
}
