import SwiftUI
import CoreLocation

struct NearbyView: View {

    // Dependencies
    @Environment(\.network) var network
    @Environment(\.locationAuthorization) private var location

    // Model
    @State var model = NearbyModel()

    var body: some View {
        Group {
            if let failure = model.failure {
                Text("Error: \(failure)")
                    .foregroundStyle(.red)
            } else if model.stops.isEmpty {
                ProgressView()
            } else {
                List(model.stops) { stop in
                    VStack(alignment: .leading) {
                        Text(stop.name)
                            .font(.headline)
                        Text("ID: \(stop.id)")
                            .font(.subheadline)
                        Text("Lat: \(stop.latitude), Lon: \(stop.longitude)")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Nearby Stops")
        .padding()
        .onChange(of: location?.coordinate) { _, newCoordinate in
            guard let coordinate = newCoordinate else { return }
            Task { await loadStops(at: coordinate) }
        }
        .task {
            if let coordinate = location?.coordinate {
                await loadStops(at: coordinate)
            }
        }
    }

    /// Loads nearby stops for the current device coordinate via the Trafiklab API.
    private func loadStops(at coordinate: CLLocationCoordinate2D) async {
        await model.loadStops(
            network: network,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}
