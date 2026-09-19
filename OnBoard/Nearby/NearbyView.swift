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
                ContentUnavailableView {
                    Label("Error loading stops", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.ink)
                } description: {
                    Text(failure)
                        .foregroundStyle(.inkSoft)
                }
            } else if model.stops.isEmpty {
                ProgressView()
                    .tint(.accent)
            } else {
                NearbyStopsList(stops: model.stops)
            }
        }
        .navigationTitle("Nearby Stops")
        .navigationDestination(for: Stop.self) { stop in
            StopDetailsView(stopId: stop.id, stopName: stop.name)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
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

/// The list of nearby stops with the storyboard's stop-row styling:
/// white background, magenta left border, stop name, and distance.
private struct NearbyStopsList: View {
    let stops: [Stop]

    var body: some View {
        List(stops) { stop in
            NavigationLink(value: stop) {
                NearbyStopRow(stop: stop)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listRowBackground(Color.panel)
        .background(Color.paper)
    }
}

/// One stop row matching the storyboard's `stop-row`:
/// white background, magenta left border, stop name in Ink, distance in InkSoft.
private struct NearbyStopRow: View {
    let stop: Stop

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(stop.distanceLabel ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.inkSoft)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
    }
}

#Preview {
    @Previewable @State var network: NetworkProtocol = mockNetwork()
    @Previewable @State var locationModel: LocationAuthorization = previewLocationAuthorization()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, network)
    .environment(locationModel)
}
