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
                UnavailableScreen(
                    title: "Error loading stops",
                    systemImage: "wifi.exclamationmark",
                    message: failure
                )
            } else if model.stops.isEmpty {
                if location.coordinate == nil {
                    UnavailableScreen(
                        title: "Waiting for your location",
                        systemImage: "location",
                        message: "Stops appear here as soon as a location is available."
                    )
                } else if model.isLoading {
                    LoadingIndicator()
                } else {
                    UnavailableScreen(
                        title: "No stops nearby",
                        systemImage: "mappin.and.ellipse",
                        message: "There are no stops within 1 km of you."
                    )
                }
            } else {
                NearbyStopsList(stops: model.stops, failure: model.failure)
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
    /// The most recent refresh failure, if any. While non-nil the rows shown
    /// are from the last successful load, surfaced as a banner.
    let failure: String?

    var body: some View {
        List(stops) { stop in
            NavigationLink(value: stop) {
                NearbyStopRow(stop: stop)
            }
            .listRowBackground(Color.panel)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if failure != nil {
                Text("Couldn't refresh — showing stops from the last update")
                    .font(.caption)
                    .foregroundStyle(.inkSoft)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: failure)
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

#Preview("Default") {
    @Previewable @State var network: NetworkProtocol = mockNetwork()
    @Previewable @State var locationModel: LocationAuthorization = previewLocationAuthorization()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, network)
    .environment(locationModel)
}

#Preview("Failure") {
    @Previewable @State var locationModel: LocationAuthorization = previewLocationAuthorization()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, DisconnectedNetwork())
    .environment(locationModel)
}

#Preview("Always loading location") {
    NavigationStack {
        NearbyView()
    }
    .environment(\.network, DisconnectedNetwork())
    .environment(LocationAuthorization(manager: AlwaysLoadingLocationManager()))
}
