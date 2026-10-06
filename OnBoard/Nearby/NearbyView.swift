import SwiftUI
import CoreLocation

struct NearbyView: View {

    // Dependencies
    @Environment(\.network) var network
    @Environment(LocationAuthorization.self) private var location
    @Environment(FavoritesModel.self) private var favoritesModel

    // Model
    @State var model = NearbyModel()

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(
                    title: .nearbyErrorTitle,
                    systemImage: "wifi.exclamationmark",
                    message: Text(verbatim: failure)
                )
            } else if model.stops.isEmpty {
                if location.coordinate == nil {
                    UnavailableScreen(
                        title: .nearbyWaitingTitle,
                        systemImage: "location",
                        message: Text(.nearbyWaitingMessage)
                    )
                } else if model.isLoading {
                    LoadingIndicator()
                } else {
                    UnavailableScreen(
                        title: .nearbyEmptyTitle,
                        systemImage: "mappin.and.ellipse",
                        message: Text(.nearbyEmptyMessage)
                    )
                }
            } else {
                NearbyStopsList(
                    stops: model.stops,
                    failure: model.failure,
                    closestFavorite: favoritesModel.closestFavourite(
                        coordinate: location.coordinate,
                        stops: model.stops
                    )
                )
            }
        }
        .navigationTitle(.nearbyTitle)
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
    /// The saved favourite nearest to the user, surfaced as the first
    /// section. `nil` hides the section without leaving an empty gap.
    let closestFavorite: ClosestFavorite?

    var body: some View {
        List {
            if let closestFavorite {
                Section(.nearbyClosestFavorite) {
                    NavigationLink(value: closestFavorite.stop) {
                        ClosestFavoriteRow(closest: closestFavorite)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ForEach(stops) { stop in
                    NavigationLink(value: stop) {
                        NearbyStopRow(stop: stop)
                    }
                    .listRowBackground(Color.panel)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if failure != nil {
                Text(.nearbyRefreshFailed)
                    .font(.caption)
                    .foregroundStyle(.inkSoft)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: failure)
        .animation(.default, value: closestFavorite)
    }
}

/// The Home Screen's first section: the saved favourite nearest to the user,
/// rendered as a highlight card with a bright accent glow — a star, the stop
/// name, and its distance from the user.
private struct ClosestFavoriteRow: View {
    let closest: ClosestFavorite

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.star)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(closest.favorite.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(closest.stop.distanceLabel ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 13)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accent, lineWidth: 1.5)
        )
        .shadow(color: .accent.opacity(0.55), radius: 14, y: 6)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
    @Previewable @State var favoritesModel = FavoritesModel()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, network)
    .environment(locationModel)
    .environment(favoritesModel)
    .modelContainer(mockModelContainer())
}

#Preview("Failure") {
    @Previewable @State var locationModel: LocationAuthorization = previewLocationAuthorization()
    @Previewable @State var favoritesModel = FavoritesModel()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, DisconnectedNetwork())
    .environment(locationModel)
    .environment(favoritesModel)
    .modelContainer(mockModelContainer())
}

#Preview("Always loading location") {
    @Previewable @State var favoritesModel = FavoritesModel()

    NavigationStack {
        NearbyView()
    }
    .environment(\.network, DisconnectedNetwork())
    .environment(LocationAuthorization(manager: AlwaysLoadingLocationManager()))
    .environment(favoritesModel)
    .modelContainer(mockModelContainer())
}
