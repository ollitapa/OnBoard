import Foundation

/// Presentation helpers for `StopGroup` rows used by the Search screen,
/// modeled as computed properties so call sites read naturally
/// (`stopGroup.modeIcons`) instead of a static "pass-the-value" function.
extension StopGroup {

    /// The SF Symbols for the stop's transport modes, normalized and de-duped.
    /// Empty when the API reports no current traffic.
    var modeIcons: [String] {
        transport_modes
            .map { $0.uppercased() }
            .reduce(into: [String]()) { acc, mode in
                let icon = SearchTransport.icon(for: mode)
                if !acc.contains(icon) { acc.append(icon) }
            }
    }

    /// A short label for the stop's transport modes, e.g. "BUS · METRO".
    /// Empty when the API reports no current traffic.
    var modeSummary: String {
        transport_modes
            .map { $0.uppercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Maps a Trafiklab `transport_mode` to a SF Symbol. Shared with the Stop
/// board's blip so the Search rows and the board agree on icons.
enum SearchTransport {
    /// Maps a Trafiklab `transport_mode` to a SF Symbol.
    static func icon(for mode: String) -> String {
        switch mode.uppercased() {
        case "BUS":
            return "bus.fill"
        case "TRAM":
            return "tram.fill"
        case "METRO":
            return "tram.fill"
        case "TRAIN":
            return "train.side.front.car"
        case "BOAT":
            return "ferry.fill"
        case "TAXI":
            return "car.fill"
        default:
            return "questionmark"
        }
    }
}
