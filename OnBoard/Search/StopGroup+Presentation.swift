import Foundation

/// Presentation helpers for `StopGroup` rows used by the Search screen,
/// modeled as computed properties so call sites read naturally
/// (`stopGroup.modeIcons`) instead of a static "pass-the-value" function.
extension StopGroup {

    /// The SF Symbols for the stop's transport modes, normalized and de-duped.
    /// Empty when the API reports no current traffic.
    var modeIcons: [String] {
        transport_modes
            .map { $0.icon}
            .reduce(into: [String]()) { acc, icon in
                if !acc.contains(icon) { acc.append(icon) }
            }
    }

    /// A short label for the stop's transport modes, e.g. "BUS · METRO".
    /// Empty when the API reports no current traffic.
    var modeSummary: String {
        transport_modes
            .map { $0.rawMode }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
