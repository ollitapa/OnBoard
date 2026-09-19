import Foundation
import Observation

/// The view model for the Stop board screen (`Designs/storyboard.html`,
/// "Step 2 — Stop board").
///
/// Loads realtime departures for a stop group id via `Trafiklab.departures`
/// and stores the raw `CallAtLocation` rows for the view to render. Mirrors
/// ``NearbyModel``: `@MainActor @Observable`, builds a `Trafiklab` client from
/// the injected network so tests can substitute a mock service, and surfaces
/// transport errors as a `failure` string rather than throwing.
@MainActor
@Observable
final class StopDetailsModel {

    /// The most recent transport error, if the last load failed.
    var failure: String?

    /// Whether a load is currently in progress.
    var isLoading: Bool = false

    /// The departures returned for the loaded stop, in API order (soonest first).
    var departures: [CallAtLocation] = []

    /// When the most recent successful load completed, for the header's
    private(set) var lastUpdated: Date?

    /// "Updated …" meta line.
    var lastUpdatedText: String {
        if let lastUpdated {
            "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
        } else {
            "Updating…"
        }
    }

    init() {}

    /// Loads departures for the given stop group id via the Trafiklab Timetables API.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - areaId: The rikshållplats/meta-stop id (group id, never a child stop id).
    func loadDepartures(network: some NetworkProtocol, areaId: String) async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.departures(at: areaId)

            // No need to do any updates if task is cancelled.
            try Task.checkCancellation()

            departures = response.departures
            lastUpdated = Date()
            failure = nil
        } catch is CancellationError {
            // Task was cancelled, ignore.
        } catch {
            departures = []
            failure = String(describing: error)
        }
    }
}
