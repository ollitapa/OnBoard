import Testing
import SwiftUI
@testable import OnBoard

@MainActor
struct SLTransportTests {

    // MARK: - Line colours model

    @Test func modelLoadsAndCachesLines() async throws {
        // Given: the mock SL Transport service, which matches the lines
        // endpoint by path.
        let network = MockSLTransportService()
        let model = LineColoursModel()

        // When
        await model.loadLines(network: network)
        let first = try #require(model.lines)

        // Then: a second load doesn't re-fetch (the response is cached for
        // the run), and the badge lookup resolves onto the design tokens.
        await model.loadLines(network: network)
        #expect(model.lines == first)
        #expect(model.badgeColour(designation: "3", transportMode: "BUS") == .lineBlue)
    }

    @Test func modelFallsBackToAccentOnFailure() async throws {
        // Given: a bare mock network serving invalid JSON for every request,
        // reaching for the handler-registered mock as in the invalid-JSON
        // tests (the feature-specific mock traps on a malformed fixture at
        // creation, so it can't serve one).
        var network = MockNetwork()
        network.registerHandler { request in
            MockNetwork.makeResponse(json: "<html>error</html>")
        }
        let model = LineColoursModel()

        // When
        await model.loadLines(network: network)

        // Then: the lookup falls back to the accent colour instead of
        // blocking the board.
        #expect(model.lines == nil)
        #expect(model.badgeColour(designation: "3", transportMode: "BUS") == .accent)
    }


    /// The lines decoded from ``MockSLTransportService/defaultLinesJSON``, so
    /// the mapping tests run against the exact bytes previews and UI tests
    /// serve, decoded through the same production `Codable` path.
    private static func lines() throws -> SLLinesResponse {
        try JSONDecoder().decode(
            SLLinesResponse.self,
            from: Data(MockSLTransportService.defaultLinesJSON.utf8)
        )
    }

    // MARK: - Client

    @Test func linesBuildsTheLinesRequestAndDecodes() async throws {
        // Given: the mock SL Transport service, which matches the endpoint by
        // URL path so the authority filter in the query is irrelevant.
        let network = MockSLTransportService()
        let client = SLTransport(network: network)

        // When
        let response = try await client.lines()

        // Then: the canned lines response decoded through the production
        // path into the mode-grouped lines.
        try #expect(response == Self.lines())
    }

    // MARK: - Colour mapping

    @Test func blueBusLinesMapToLineBlue() throws {
        // Blue buses 1–6 carry the Blåbuss group and render with the
        // lineBlue design token.
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "3", transportMode: "BUS") == .lineBlue)
        #expect(lines.badgeColour(designation: "5", transportMode: "BUS") == .lineBlue)
    }

    @Test func greenMetroLinesMapToLineGreen() throws {
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "17", transportMode: "METRO") == .lineGreen)
        #expect(lines.badgeColour(designation: "18", transportMode: "METRO") == .lineGreen)
        #expect(lines.badgeColour(designation: "19", transportMode: "METRO") == .lineGreen)
    }

    @Test func redAndBlueMetroLinesMapToTheirColours() throws {
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "13", transportMode: "METRO") == .lineRed)
        #expect(lines.badgeColour(designation: "10", transportMode: "METRO") == .lineBlue)
    }

    @Test func timetablesMetroPrefixIsDropped() throws {
        // The Timetables API prefixes metro designations with "T" (T17,
        // T19) where SL Transport reports the bare number; the lookup must
        // still find the line.
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "T17", transportMode: "METRO") == .lineGreen)
        #expect(lines.badgeColour(designation: "T13", transportMode: "METRO") == .lineRed)
    }

    @Test func timetablesPrefixIsKeptForOtherModes() throws {
        // A bus or tram designation must match exactly, so a hypothetical
        // bus "T3" doesn't accidentally match blue bus 3.
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "T3", transportMode: "BUS") == nil)
    }

    @Test func ungroupedLinesFallBackToAccent() throws {
        // Regular buses carry no group_of_lines; trams carry a group the
        // mapping doesn't colour-code. Both fall back to accent rather than
        // guessing a hue.
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "50", transportMode: "BUS") == .accent)
        #expect(lines.badgeColour(designation: "7", transportMode: "TRAM") == .accent)
        #expect(lines.badgeColour(designation: "40", transportMode: "TRAIN") == .accent)
    }

    @Test func unknownLineReturnsNil() throws {
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "999", transportMode: "BUS") == nil)
        #expect(lines.badgeColour(designation: nil, transportMode: "BUS") == nil)
        #expect(lines.badgeColour(designation: "3", transportMode: nil) == nil)
    }

    @Test func groupNamesMatchCaseInsensitively() {
        // The mapping lowercases before comparing, so a change in SL's
        // capitalisation ("BLÅBUSS") doesn't break the colour mapping.
        #expect(Self.line(groupOfLines: "BLÅBUSS").badgeColour == .lineBlue)
        #expect(Self.line(groupOfLines: "Tunnelbanans GRÖNA linje").badgeColour == .lineGreen)
        #expect(Self.line(groupOfLines: "TUNNELBANANS RÖDA LINJE").badgeColour == .lineRed)
        #expect(Self.line(groupOfLines: nil).badgeColour == .accent)
        #expect(Self.line(groupOfLines: "Pendeltåg").badgeColour == .accent)
    }

    // MARK: - Helpers

    /// Builds an `SLLine` carrying only the group name the colour mapping
    /// reads, mirroring the fixture's fields elsewhere.
    private static func line(groupOfLines: String?) -> SLLine {
        SLLine(
            id: 1,
            designation: "1",
            transport_mode: "BUS",
            group_of_lines: groupOfLines
        )
    }
}
