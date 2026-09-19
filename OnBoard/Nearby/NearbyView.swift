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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.panel, for: .navigationBar)
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
        }
        .listStyle(.plain)
        .listRowBackground(Color.panel)
        .scrollContentBackground(Color.paper)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                if let distance = stop.distanceLabel {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.inkSoft)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(Color.panel)
        .overlay(
            Rectangle()
                .fill(Color.accent)
                .frame(width: 3)
                .padding(.vertical, 4),
            alignment: .leading
        )
        .cornerRadius(10)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .listRowSeparator(.hidden)
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
