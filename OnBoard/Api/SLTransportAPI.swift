import Foundation
import SwiftUI

/// A client for SL's Transport API (`transport.integration.sl.se/v1`), the
/// keyless successor to SL Stops and lines v2 documented on Trafiklab.
///
/// The Trafiklab-hosted APIs don't carry line colour information — the GTFS
/// feeds they publish omit the standard `route_color`/`route_text_color`
/// attributes. SL Transport is the one source that classifies lines into
/// named groups ("Blåbuss", "Tunnelbanans gröna linje", …) which map directly
/// onto the colour-coding riders see on SL's own signage.
///
/// Like `Trafiklab`, the client depends only on a `NetworkProtocol` for
/// transport, so it runs against mocks in tests and previews. No API key is
/// required, so the client reads none from `Secrets`.
struct SLTransport {

    /// Base URL for SL's Transport API.
    private static let baseURL = URL(string: "https://transport.integration.sl.se/v1/")!

    /// The transport used to perform requests.
    private let network: NetworkProtocol

    /// Creates a client backed by the given network.
    /// - Parameter network: The `NetworkProtocol` used to perform requests.
    init(network: some NetworkProtocol) {
        self.network = network
    }

    // MARK: - Lines

    /// Lists every line operated by SL, grouped by transport mode.
    ///
    /// The response is large and slow-changing — fetch it once, cache it, and
    /// look lines up by `designation` (the number riders know, e.g. "3") plus
    /// `transport_mode` rather than by `id`, since SL-internal line ids don't
    /// match the ids used by the Trafiklab-hosted Realtime APIs.
    func lines() async throws -> SLLinesResponse {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("lines"),
            resolvingAgainstBaseURL: true
        ) else { throw TrafiklabInvalidURL() }
        components.queryItems = [URLQueryItem(name: "transport_authority_id", value: "1")]
        guard let url = components.url else { throw TrafiklabInvalidURL() }
        let request = URLRequest(url: url)
        let (data, _) = try await network.data(for: request)
        return try Self.decoder.decode(SLLinesResponse.self, from: data)
    }

    private static let decoder = JSONDecoder()
}

/// Top-level response for SL Transport `lines`: every SL line, keyed by its
/// transport mode.
struct SLLinesResponse: Codable, Equatable, Sendable {
    var metro: [SLLine]?
    var tram: [SLLine]?
    var train: [SLLine]?
    var bus: [SLLine]?
    var ship: [SLLine]?
    var ferry: [SLLine]?
    var taxi: [SLLine]?
}

/// A line operated by SL, grouped under a mode. Only `designation`,
/// `transport_mode`, and `group_of_lines` matter for colour-coding a line
/// badge; the ids are SL-internal and don't match Trafiklab's.
struct SLLine: Codable, Equatable, Sendable {
    /// SL-internal line id — do not match against Trafiklab data.
    var id: Int
    /// The line number riders know, e.g. "3" or "19".
    var designation: String?
    /// `BUS` / `METRO` / `TRAM` / `TRAIN` / `TAXI` / `SHIP` / `FERRY`.
    var transport_mode: TransportMode?
    /// The named colour/mode grouping, e.g. `Blåbuss` or `Tunnelbanans
    /// gröna linje`; absent on lines outside the colour-coded groups (regular
    /// red buses).
    var group_of_lines: String?
}

// MARK: - Line colour mapping

/// The badge colour a line should carry, mapped from SL's own colour-coding
/// of its network: blue buses and the blue metro line render with the
/// `lineBlue` design token, the green and red metro lines with `lineGreen`
/// and `lineRed`, and everything else with the accent colour (so a
/// cancelled/delayed status keeps its red).
enum LineBadgeColour: Equatable, Sendable {
    case blue
    case green
    case red
    case accent

    /// The asset-catalog colour a badge with this case renders with, via the
    /// symbols Xcode generates from the coloursets.
    var color: Color {
        switch self {
        case .blue: .lineBlue
        case .green: .lineGreen
        case .red: .lineRed
        case .accent: .accent
        }
    }

    /// Maps an SL Transport `group_of_lines` name onto a badge colour. Known
    /// groups match the spellings SL Transport returns today; a group the
    /// mapping doesn't recognize — including a line with no group at all —
    /// falls back to the accent colour rather than guessing a hue.
    init(groupOfLines: String?) {
        switch groupOfLines?.lowercased() {
        case "blåbuss":
            self = .blue
        case "tunnelbanans blå linje":
            self = .blue
        case "tunnelbanans gröna linje":
            self = .green
        case "tunnelbanans röda linje":
            self = .red
        default:
            self = .accent
        }
    }
}

extension SLLinesResponse {
    /// Every line in the response, across all transport modes.
    var allLines: [SLLine] {
        [metro, tram, train, bus, ship, ferry, taxi]
            .compactMap { $0 }
            .flatMap { $0 }
    }

    /// Looks up a line's badge colour by its designation and transport mode.
    ///
    /// `designation` is the line number as the Timetables response reports it
    /// (e.g. "17" or "T14"), matched against the SL Transport lines so a
    /// departure can be coloured without knowing SL's internal ids. The
    /// Timetables API prefixes metro designations with `T` ("T14") where SL
    /// Transport reports the bare number ("14"), so a leading `T` is dropped
    /// for metro lookups.
    ///
    /// - Returns: The line's colour, or `nil` when no line matches — callers
    ///   fall back to the accent colour.
    func badgeColour(
        designation: String?,
        transportMode: TransportMode?
    ) -> LineBadgeColour? {
        guard let designation, let transportMode else { return nil }
        let normalized = transportMode == "METRO" && designation.hasPrefix("T")
            ? String(designation.dropFirst())
            : designation
        let line = allLines.first { line in
            line.designation == normalized && line.transport_mode == transportMode
        }
        return line.map { LineBadgeColour(groupOfLines: $0.group_of_lines) }
    }
}
