import Observation
import Foundation

struct Stop: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    
    /// Computed distance text for display (e.g., "180 m")
    var distanceText: String {
        // This would be calculated from user location in a real implementation
        // For now, return a placeholder
        return ""
    }
    
    /// Computed minutes to walk (for the green time chip)
    var minutesToWalk: Int? {
        // This would be calculated from user location in a real implementation
        // For now, return nil to hide the chip
        return nil
    }
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
    }
}
