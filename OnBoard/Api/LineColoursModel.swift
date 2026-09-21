import Foundation
import Observation
import SwiftUI

/// The shared line-colour lookup for every line badge the app renders,
/// backed by SL's keyless Transport `lines` endpoint.
///
/// The Trafiklab-hosted APIs don't carry line colours, so SL's own
/// classification (`Blåbuss`, `Tunnelbanans gröna linje`, …) is fetched once
/// per run and cached: the data is slow-changing, and the endpoint is
/// unauthenticated, so a badge lookup costs nothing after the first load.
/// Mirrors ``FavoritesModel``: a shared `@MainActor @Observable` model owned
/// by ``MainView``, published into the environment, and injected into the
/// screens that need it — never a singleton.
@MainActor
@Observable
final class LineColoursModel {

    /// The lines loaded from the SL Transport API, keyed by transport mode
    /// as the endpoint groups them.
    private(set) var lines: SLLinesResponse?

    /// Creates an empty model; call ``loadLines(network:)`` from the owning
    /// view's `.task`.
    init() {}

    /// Loads SL's line classifications once per run. A successful load is
    /// cached and never re-fetched; a failed load is retried on the next
    /// call (a badge falls back to the accent colour meanwhile, so a colour
    /// outage never blocks the board).
    /// - Parameter network: The transport used to perform the request.
    func loadLines(network: some NetworkProtocol) async {
        guard lines == nil else { return }
        let api = SLTransport(network: network)
        lines = try? await api.lines()
    }

    /// Directly installs a decoded lines response, for previews and tests
    /// that need badge colours without a network round trip. See
    /// `previewLineColours()`.
    func seedLines(_ response: SLLinesResponse) {
        lines = response
    }

    /// The badge colour for a departure's route, resolving SL's colour
    /// classification onto the app's line design tokens. Falls back to the
    /// accent colour when the lines haven't loaded or the line isn't known.
    /// - Parameters:
    ///   - designation: The route's `designation`, e.g. "3" or "T17".
    ///   - transportMode: The route's transport mode.
    func badgeColour(designation: String?, transportMode: TransportMode?) -> Color {
        lines?.badgeColour(designation: designation, transportMode: transportMode)
            ?? .accent
    }
}
