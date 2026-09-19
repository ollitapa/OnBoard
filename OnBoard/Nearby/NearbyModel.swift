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

    var failure: String?

    var stops: [Stop] = []

    init() {}

    /// Loads nearby stops for the given coordinate via the Trafiklab API.
    /// - Parameters:
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    ///   - latitude: WGS84 decimal degrees.
    ///   - longitude: WGS84 decimal degrees.
    func loadStops(network: some NetworkProtocol, latitude: Double, longitude: Double) async {

        do {
            let api = Trafiklab(network: network)
            let response = try await api.nearbyStops(latitude: latitude, longitude: longitude)
            stops = response.StopLocation.map(Stop.init)
            failure = nil

        } catch {
            failure = String(describing: error)
        }
    }

}

extension Stop {
    /// Creates a `Stop` from a ResRobot `StopLocation`, using `extId` (the group id)
    /// as the stable identifier and parsing the string coordinates ResRobot returns.
    init(_ location: StopLocation) {
        self.id = location.extId
        self.name = location.name
        self.latitude = Double(location.lat) ?? 0
        self.longitude = Double(location.lon) ?? 0
        self.distance = location.dist
    }

    /// The distance for the row subtitle: meters under 1 km, otherwise
    /// kilometers with at most one decimal. `nil` when the stop carries no
    /// distance (ResRobot always sends one for nearby results).
    var distanceLabel: String? {
        guard let distance else { return nil }
        if distance < 1000 {
            return "\(distance) m"
        }
        let kilometers = Double(distance) / 1000
        return kilometers.formatted(.number.precision(.fractionLength(0...1))) + " km"
    }

    /// Computed minutes to walk (for the green time chip)
    var minutesToWalk: Int? {
        // This would be calculated from user location in a real implementation
        // For now, return nil to hide the chip
        return nil
    }
}
