import SwiftUI

struct NearbyView: View {

    // Dependencies
    @Environment(\.network) var network

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
        .task {
            await model.loadStops(network: network)
        }
    }
}
