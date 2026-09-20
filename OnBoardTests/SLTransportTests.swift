import Testing
import Foundation
@testable import OnBoard

struct SLTransportTests {

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
        #expect(response == Self.lines())
    }

    @Test func linesDecodeFailureThrows() async {
        // Given: a mock serving invalid JSON.
        let network = MockSLTransportService(linesJSON: "<html>error</html>")
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
        #expect(lines.badgeColour(designation: "3", transportMode: "BUS") == .blue)
        #expect(lines.badgeColour(designation: "5", transportMode: "BUS") == .blue)
    }

    @Test func greenMetroLinesMapToGreen() throws {
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "17", transportMode: "METRO") == .green)
        #expect(lines.badgeColour(designation: "18", transportMode: "METRO") == .green)
        #expect(lines.badgeColour(designation: "19", transportMode: "METRO") == .green)
    }

    @Test func redAndBlueMetroLinesMapToTheirColours() throws {
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "13", transportMode: "METRO") == .red)
        #expect(lines.badgeColour(designation: "10", transportMode: "METRO") == .blue)
    }

    @Test func timetablesMetroPrefixIsDropped() throws {
        // The Timetables API prefixes metro designations with "T" (T17,
        // T19) where SL Transport reports the bare number; the lookup must
        // still find the line.
        let lines = try Self.lines()
        #expect(lines.badgeColour(designation: "T17", transportMode: "METRO") == .green)
        #expect(lines.badgeColour(designation: "T13", transportMode: "METRO") == .red)
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
        #expect(LineBadgeColour(groupOfLines: "BLÅBUSS") == .blue)
        #expect(LineBadgeColour(groupOfLines: "Tunnelbanans GRÖNA linje") == .green)
        #expect(LineBadgeColour(groupOfLines: nil) == .accent)
        #expect(LineBadgeColour(groupOfLines: "Pendeltåg") == .accent)
    }

    @Test func colorExposesTheDesignToken() {
        // Each case renders with its asset-catalog colourset: the generated
        // symbol names are the design tokens, so a badge never falls back to
        // a hardcoded system colour.
        #expect(LineBadgeColour.blue.color == .lineBlue)
        #expect(LineBadgeColour.green.color == .lineGreen)
        #expect(LineBadgeColour.red.color == .lineRed)
        #expect(LineBadgeColour.accent.color == .accent)
    }
}
