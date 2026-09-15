import Observation
import Foundation

struct Stop: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
}

@MainActor
@Observable
final class NearbyModel {

    var failure: String?

    var stops: [Stop] = []

    private let nearbyURL = URL(string: "https://api.example.com/stops/nearby")!

    init() {}

    func loadStops(network: some NetworkProtocol) async {

        do {
            var request = URLRequest(url: nearbyURL)
            request.httpMethod = "GET"
            
            let (data, _) = try await network.data(for: request)
            stops = try JSONDecoder().decode([Stop].self, from: data)
            failure = nil

        } catch {
            failure = String(describing: error)
        }
    }

}
