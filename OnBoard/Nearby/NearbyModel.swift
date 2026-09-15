import Observation

struct Stop: Codable, Identifiable {
    var id: String
}

@MainActor
@Observable
final class NearbyModel {

    var failure: String?

    var stops: [Stop] = []

    init() {}

    func loadStops(network: some NetworkProtocol) async {

        do {
            // Get the data from the network

        } catch {
            failure = String(describing: error)
        }
    }

}
