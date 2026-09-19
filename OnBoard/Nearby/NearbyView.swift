import SwiftUI
import CoreLocation

struct NearbyView: View {

    // Dependencies
    @Environment(\.network) var network
    @Environment(LocationAuthorization.self) private var location

    // Model
    @State var model = NearbyModel()

    var body: some View {
        Group {
            if let failure = model.failure {
                Text("Error: \(failure)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if model.stops.isEmpty {
                ProgressView()
            } else {
                List(model.stops) { stop in
                    NavigationLink(value: stop) {
                        VStack(alignment: .leading) {
                            Text(stop.name)
                                .font(.headline)
                            if let distance = stop.distanceLabel {
                                Text(distance)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nearby Stops")
        .navigationDestination(for: Stop.self) { stop in
            StopDetailsView(stopId: stop.id, stopName: stop.name)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: location.coordinate) {
            guard let coordinate = location.coordinate else { return }
            await model.loadStops(
                network: network,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}
