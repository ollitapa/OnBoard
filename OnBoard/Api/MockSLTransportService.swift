import Foundation
import Observation

/// A mock `NetworkProtocol` that serves the SL Transport `lines` endpoint
/// with a canned response, for previews, unit tests, and the
/// `--mock-network` UI-test harness.
///
/// Mirrors `MockTrafiklabService`: the fixture is a JSON string in the
/// endpoint's wire shape — the same shape `SLTransport` decodes — served
/// verbatim as the full response body, so the model under test runs its real
/// production `Codable` decode on bytes written exactly like the fixture.
/// Matching is by URL path so the request's query parameters don't affect
/// the response; anything else throws `NoResponseConfigured`.
struct MockSLTransportService: NetworkProtocol {

    /// The base URL this server is responsible for (matched by
    /// `CombinedNetwork`).
    let baseURL: URL

    /// The body served from the lines endpoint, in the SL Transport wire
    /// shape (every SL line grouped under its transport mode, with the
    /// colour-named groups in `group_of_lines`). Defaults to
    /// ``defaultLinesJSON`` so previews, the `--mock-network` UI-test
    /// harness, and unit tests all share one canned dataset.
    let linesJSON: String

    /// Creates a mock SL Transport service.
    /// - Parameters:
    ///   - baseURL: The base URL this server responds for.
    ///   - linesJSON: The lines response body in the SL Transport wire
    ///     shape.
    init(
        baseURL: URL = URL(string: "https://transport.integration.sl.se")!,
        linesJSON: String = MockSLTransportService.defaultLinesJSON
    ) {
        self.baseURL = baseURL
        self.linesJSON = Self.validated(linesJSON)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw NoResponseConfigured() }

        if request.httpMethod == "GET", url.path.hasSuffix("/lines") {
            return Self.ok(Data(linesJSON.utf8), url: url)
        }

        throw NoResponseConfigured()
    }

    // MARK: - Fixture handling

    /// Validates the fixture's JSON syntax at creation, trapping with the
    /// fixture named when it doesn't parse: a broken fixture is a
    /// programming error in the test or preview that wired it, and a loud
    /// failure at creation beats a decoding error surfacing later as the
    /// model's failure string.
    private static func validated(_ json: String) -> String {
        guard (try? JSONSerialization.jsonObject(with: Data(json.utf8))) != nil else {
            fatalError("MockSLTransportService: invalid linesJSON")
        }
        return json
    }

    /// Wraps a JSON body in a `200` response with a JSON content type.
    private static func ok(_ body: Data, url: URL) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }

    // MARK: - Default fixture

    /// A stable set of SL lines served by default, matching the shape the
    /// SL Transport API returns: every line grouped under its transport
    /// mode, with the colour-named groups (`Blåbuss`, `Tunnelbanans gröna
    /// linje`, …) in `group_of_lines`. Distilled from a captured response,
    /// keeping the lines the app's canned departures and trips reference
    /// (blue buses 1–6, the green 17/18/19 and red 13/14 metro, tram 7) plus
    /// an ungrouped bus and the Pendeltåg lines so lookups that should fall
    /// back to the accent colour also find a line.
    static let defaultLinesJSON = """
    {
        "metro": [
            {
                "id": 10,
                "gid": 9011001001000000,
                "name": "Blå linjen",
                "designation": "10",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans blå linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 11,
                "gid": 9011001001100000,
                "name": "Blå linjen",
                "designation": "11",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans blå linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 13,
                "gid": 9011001001300000,
                "name": "Röda linjen",
                "designation": "13",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans röda linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 14,
                "gid": 9011001001400000,
                "name": "Röda linjen",
                "designation": "14",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans röda linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 17,
                "gid": 9011001001700000,
                "name": "Gröna linjen",
                "designation": "17",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans gröna linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 18,
                "gid": 9011001001800000,
                "name": "Gröna linjen",
                "designation": "18",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans gröna linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 19,
                "gid": 9011001001900000,
                "name": "Gröna linjen",
                "designation": "19",
                "transport_mode": "METRO",
                "group_of_lines": "Tunnelbanans gröna linje",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            }
        ],
        "tram": [
            {
                "id": 7,
                "gid": 9011001000700000,
                "name": "Spårväg city",
                "designation": "7",
                "transport_mode": "TRAM",
                "group_of_lines": "Spårväg City",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2010-07-27T00:00:00" }
            }
        ],
        "train": [
            {
                "id": 40,
                "gid": 9011001004000000,
                "name": "",
                "designation": "40",
                "transport_mode": "TRAIN",
                "group_of_lines": "Pendeltåg",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2017-08-23T00:00:00" }
            }
        ],
        "bus": [
            {
                "id": 1,
                "gid": 9011001000100000,
                "name": "",
                "designation": "1",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 2,
                "gid": 9011001000200000,
                "name": "",
                "designation": "2",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 3,
                "gid": 9011001000300000,
                "name": "",
                "designation": "3",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 4,
                "gid": 9011001000400000,
                "name": "",
                "designation": "4",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2007-08-24T00:00:00" }
            },
            {
                "id": 5,
                "gid": 9011001000500000,
                "name": "",
                "designation": "5",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2025-06-03T00:00:00" }
            },
            {
                "id": 6,
                "gid": 9011001000600000,
                "name": "",
                "designation": "6",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2017-12-10T00:00:00" }
            },
            {
                "id": 50,
                "gid": 9011001005000000,
                "name": "",
                "designation": "50",
                "transport_mode": "BUS",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2015-06-19T00:00:00" }
            },
            {
                "id": 54,
                "gid": 9011001005400000,
                "name": "",
                "designation": "54",
                "transport_mode": "BUS",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "valid": { "from": "2015-06-19T00:00:00" }
            }
        ]
    }
    """
}

/// Builds a `LineColoursModel` pre-loaded with the mock service's canned
/// lines, for previews and tests that need line badge colours without a
/// network round trip. Mirrors `previewLocationAuthorization()`: the
/// helper lives in the app target because previews call it directly, and
/// the fixture is decoded synchronously so the helper stays non-async.
@MainActor
func previewLineColours() -> LineColoursModel {
    let model = LineColoursModel()
    model.seedLines(
        (try? JSONDecoder().decode(
            SLLinesResponse.self,
            from: Data(MockSLTransportService.defaultLinesJSON.utf8)
        ))
            ?? SLLinesResponse()
    )
    return model
}
