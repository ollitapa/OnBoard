import Observation
import Foundation

struct Stop: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    /// Distance from the query point in meters, as ResRobot reports it.
    var distance: Int?
}

@MainActor
@Observable
final class NearbyModel {

    /// The most recent transport error, if the last load failed.
    var failure: String?

    /// Whether a load is currently in progress.
    var isLoading: Bool = false

    /// The nearby stops from the most recent successful load. Kept (not cleared)
    /// when a refresh fails, so the view can show stale rows with a failure
    /// banner instead of an empty screen.
    var stops: [Stop] = []

    init() {}

    /// Loads nearby stops for the given coordinate via the Trafiklab API.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - latitude: WGS84 decimal degrees.
    ///   - longitude: WGS84 decimal degrees.
    func loadStops(network: some NetworkProtocol, latitude: Double, longitude: Double) async {
        isLoading = true
        // A cancellation always hands the loading flag to the task that
        // replaced us (`.task(id:)` starts the new task before cancelling the
        // old one), so bail out early and leave the flag alone: setting it
        // here would clobber the replacement's `true` with a stale `false`.
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.nearbyStops(latitude: latitude, longitude: longitude)
            stops = response.stops.compactMap(Stop.init)
            failure = nil

        } catch is CancellationError {
            // Task was cancelled, ignore.
        } catch {
            failure = String(describing: error)
        }
    }

}

extension Stop {
    /// Creates a `Stop` from a ResRobot `StopLocation`, using `extId` (the group id)
    /// as the stable identifier.
    init(_ location: StopLocation) {
        self.id = location.extId
        self.name = location.name
        self.latitude = location.lat
        self.longitude = location.lon
        self.distance = location.dist
    }

    /// The distance for the row subtitle: meters under 1 km, otherwise
    /// kilometers with at most one decimal. `nil` when the stop carries no
    /// distance (ResRobot always sends one for nearby results).
    var distanceLabel: String? {
        guard let distance else { return nil }
        if distance < 1000 {
            return String(localized: .stopMeters(distance: distance))
        }
        let kilometers = Double(distance) / 1000
        return String(
            localized: .stopKilometers(
                kilometers: kilometers.formatted(.number.precision(.fractionLength(0...1)))
            )
        )
    }

    /// Computed minutes to walk (for the green time chip)
    var minutesToWalk: Int? {
        // This would be calculated from user location in a real implementation
        // For now, return nil to hide the chip
        return nil
    }
}
