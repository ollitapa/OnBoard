import Foundation

/// A stop saved to the Favourites tab ("Step 4 — Save a stop → skip the
/// search next time" in `Designs/storyboard.html`).
///
/// Captures just enough to render a favourites row and re-open the stop's
/// live departure board: the stop's group id (used for `Trafiklab.departures`
/// and as the row identity), its name, and the line labels seen when it was
/// saved (shown as the row subtitle). Equality and hashing are by `id` only,
/// so a favourite is uniquely identified by its stop regardless of the lines
/// captured at save time, which lets the star toggle and `contains` check by
/// stop id.
struct Favorite: Codable, Identifiable, Sendable, Hashable {
    /// The stop group id (Trafiklab `extId`), used to open the departure board.
    var id: String
    /// The stop name shown in the row and the board header.
    var name: String
    /// The line labels captured when the stop was saved, for the row subtitle.
    var lines: [String]

    init(id: String, name: String = "", lines: [String] = []) {
        self.id = id
        self.name = name
        self.lines = lines
    }
}

extension Favorite {
    /// The lines subtitle for a favourites row: "Lines 2, 3, 55" (English, per
    /// the app's English-only chrome), or empty when no lines were captured.
    var lineSummary: String {
        guard !lines.isEmpty else { return "" }
        return "Lines " + lines.joined(separator: ", ")
    }
}
