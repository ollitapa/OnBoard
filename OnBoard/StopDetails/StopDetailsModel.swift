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

    /// All physical platforms at the current stop.
    private(set) var platforms: [StopPlatform] = [] {
        didSet {
            // Reset selection if platforms changed
            if !platforms.contains(where: { $0.id == selectedPlatformId }) {
                selectedPlatformId = nil
            }
        }
    }

    /// The currently selected platform ID (nil = show all platforms).
    /// **Toggle behavior:** Setting to the same ID deselects it (sets to nil).
    var selectedPlatformId: String? = nil {
        didSet {
            // Reset to nil if the selected platform no longer exists
            if let id = selectedPlatformId, !platforms.contains(where: { $0.id == id }) {
                selectedPlatformId = nil
            }
        }
    }

    /// Departures filtered by the selected platform (or all if nil).
    var filteredDepartures: [CallAtLocation] {
        guard let selectedPlatformId else { return departures }
        return departures.filter { $0.stop?.id == selectedPlatformId }
    }

    /// When the most recent successful load completed, for the header's
    private(set) var lastUpdated: Date?

    /// "Updated …" meta line.
    var lastUpdatedText: LocalizedStringResource {
        if let lastUpdated {
            .stopBoardUpdated(
                time: lastUpdated.formatted(.relative(presentation: .named))
            )
        } else {
            .stopBoardUpdating
        }
    }

    init() {}

    /// Toggles the selected platform. If the same platform is passed, deselects it.
    func togglePlatform(_ platformId: String?) {
        if selectedPlatformId == platformId {
            selectedPlatformId = nil  // Deselect if tapping the same platform
        } else {
            selectedPlatformId = platformId
        }
    }

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
            // Only offer platforms that actually have departures in the
            // current window; platforms with no departures would show an
            // empty board when selected.
            platforms = response.stops
                .filter { stop in
                    response.departures.contains { $0.stop?.id == stop.id }
                }
                .map(StopPlatform.init)
            lastUpdated = Date()
            failure = nil
        } catch is CancellationError {
            // Task was cancelled, ignore.
        } catch {
            departures = []
            platforms = []
            selectedPlatformId = nil
            failure = String(describing: error)
        }
    }
}
