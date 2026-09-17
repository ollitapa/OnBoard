import Foundation

/// Presentation helpers for `[CallAtLocation]` used by the Favourites feature
/// to capture the line labels seen on a stop's board when a stop is saved.
/// Modeled as a computed property on the receiver so call sites read naturally
/// (`departures.lineLabels`) instead of a Java-style static "pass-the-value"
/// function, per the repo's presentation-helper convention.
extension Array where Element == CallAtLocation {
    /// The distinct, order-preserved line labels (`departure.lineLabel`) for a
    /// board, dropping the placeholder "?". Empty when no departures have a
    /// usable label, which leaves a favourites row's lines subtitle blank.
    var lineLabels: [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for departure in self {
            let label = departure.lineLabel
            guard label != "?", !seen.contains(label) else { continue }
            seen.insert(label)
            labels.append(label)
        }
        return labels
    }
}
