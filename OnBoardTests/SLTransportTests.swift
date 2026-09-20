import Testing
import Foundation
@testable import OnBoard

struct SLTransportTests {

    /// The SL Transport `lines` wire shape, as captured from
    /// `https://transport.integration.sl.se/v1/lines?transport_authority_id=1`:
    /// every line grouped under its transport mode, with the colour-named
    /// groups (`Blåbuss`, `Tunnelbanans gröna linje`, …) in `group_of_lines`.
    private static let linesJSON = """
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
                "contractor": { "id": 27, "name": "Connecting Stockholm" },
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
                "contractor": { "id": 27, "name": "Connecting Stockholm" },
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
                "contractor": { "id": 27, "name": "Connecting Stockholm" },
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
                "contractor": { "id": 27, "name": "Connecting Stockholm" },
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
                "contractor": { "id": 27, "name": "Connecting Stockholm" },
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
                "contractor": { "id": 70, "name": "AB Stockholms Spårvägar" },
                "valid": { "from": "2010-07-27T00:00:00" }
            }
        ],
        "bus": [
            {
                "id": 3,
                "gid": 9011001000300000,
                "name": "",
                "designation": "3",
                "transport_mode": "BUS",
                "group_of_lines": "Blåbuss",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "contractor": { "id": 10, "name": "Keolis" },
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
                "contractor": { "id": 10, "name": "Keolis" },
                "valid": { "from": "2025-06-03T00:00:00" }
            },
            {
                "id": 50,
                "gid": 9011001005000000,
                "name": "",
                "designation": "50",
                "transport_mode": "BUS",
                "transport_authority": { "id": 1, "name": "Storstockholms Lokaltrafik" },
                "contractor": { "id": 10, "name": "Keolis" },
                "valid": { "from": "2015-06-19T00:00:00" }
            }
        ]
    }
    """

    /// The lines decoded from ``linesJSON``, built once and shared by the
    /// lookup tests.
    private static func lines() throws -> SLLinesResponse {
        try JSONDecoder().decode(SLLinesResponse.self, from: Data(linesJSON.utf8))
    }

    // MARK: - Client

    @Test func linesBuildsTheLinesRequestAndDecodes() async throws {
        // Given: a mock serving the SL Transport lines response.
        var network = MockNetwork()
        let expectedURL = URL(string: "https://transport.integration.sl.se/v1/lines?transport_authority_id=1")!
        network.registerHandler { request in
            guard request.url == expectedURL else { return nil }
            return MockNetwork.makeResponse(json: Self.linesJSON)
        }
        let client = SLTransport(network: network)

        // When
        let response = try await client.lines()

        // Then: the request hit the keyless lines endpoint scoped to SL, and
        // the response decoded into the mode-grouped lines.
        #expect(network.testableRequests == [
            MockNetwork.TestableRequest(url: expectedURL, httpMethod: "GET", httpBody: nil)
        ])
        #expect(response == Self.lines())
    }

    @Test func linesDecodeFailureThrows() async {
        // Given: a mock serving invalid JSON.
        var network = MockNetwork()
        network.registerHandler { _ in
            MockNetwork.makeResponse(json: "<html>error</html>")
        }
        let client = SLTransport(network: network)

        // Then: the client throws the decoding error rather than swallowing it.
        await #expect(throws: (any Error).self) {
            _ = try await client.lines()
        }
    }

    // MARK: - Colour mapping

    @Test func blueBusLinesMapToBlue() throws {
        // Blue buses 1–6 carry the Blåbuss group.
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "3", transportMode: "BUS", in: lines) == .blue)
        #expect(LineBadgeColour.lookup(designation: "5", transportMode: "BUS", in: lines) == .blue)
    }

    @Test func greenMetroLinesMapToGreen() throws {
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "17", transportMode: "METRO", in: lines) == .green)
        #expect(LineBadgeColour.lookup(designation: "18", transportMode: "METRO", in: lines) == .green)
        #expect(LineBadgeColour.lookup(designation: "19", transportMode: "METRO", in: lines) == .green)
    }

    @Test func redAndBlueMetroLinesMapToTheirColours() throws {
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "13", transportMode: "METRO", in: lines) == .red)
        #expect(LineBadgeColour.lookup(designation: "10", transportMode: "METRO", in: lines) == .blue)
    }

    @Test func timetablesMetroPrefixIsDropped() throws {
        // The Timetables API prefixes metro designations with "T" (T17,
        // T19) where SL Transport reports the bare number; the lookup must
        // still find the line.
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "T17", transportMode: "METRO", in: lines) == .green)
        #expect(LineBadgeColour.lookup(designation: "T13", transportMode: "METRO", in: lines) == .red)
    }

    @Test func timetablesPrefixIsKeptForOtherModes() throws {
        // A bus or tram designation must match exactly, so a hypothetical
        // bus "T3" doesn't accidentally match blue bus 3.
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "T3", transportMode: "BUS", in: lines) == nil)
    }

    @Test func ungroupedLinesFallBackToAccent() throws {
        // Regular buses carry no group_of_lines; trams carry a group the
        // mapping doesn't colour-code. Both fall back to accent rather than
        // guessing a hue.
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "50", transportMode: "BUS", in: lines) == .accent)
        #expect(LineBadgeColour.lookup(designation: "7", transportMode: "TRAM", in: lines) == .accent)
    }

    @Test func unknownLineReturnsNil() throws {
        let lines = try Self.lines()
        #expect(LineBadgeColour.lookup(designation: "999", transportMode: "BUS", in: lines) == nil)
        #expect(LineBadgeColour.lookup(designation: nil, transportMode: "BUS", in: lines) == nil)
        #expect(LineBadgeColour.lookup(designation: "3", transportMode: nil, in: lines) == nil)
    }

    @Test func groupNamesMatchCaseInsensitively() {
        // The mapping lowercases before comparing, so a change in SL's
        // capitalisation ("BLÅBUSS") doesn't break the colour mapping.
        #expect(LineBadgeColour(groupOfLines: "BLÅBUSS") == .blue)
        #expect(LineBadgeColour(groupOfLines: "Tunnelbanans GRÖNA linje") == .green)
        #expect(LineBadgeColour(groupOfLines: nil) == .accent)
        #expect(LineBadgeColour(groupOfLines: "Pendeltåg") == .accent)
    }
}
