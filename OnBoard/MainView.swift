import SwiftUI
import CoreLocation

enum Tabs: String, Hashable {
    case nearby
    case favorites
    case search
}

struct MainView: View {

    @SceneStorage("SelectedTab") private var selectedTab: Tabs = .nearby

    /// The network dependency injected into the environment. Built from the
    /// launch arguments by default so the `--mock-network` UI-test harness is
    /// served canned data; previews/tests pass an explicit value.
    private let network: any NetworkProtocol

    /// The location-authorization model backing the Nearby tab's permission
    /// gate. `nil` by default, in which case the `.locationPermissions` modifier
    /// builds its own model from the launch arguments; previews/tests pass a
    /// pre-authorized model so the nearby list renders without a real prompt.
    private let locationModel: LocationAuthorization?

    init() {
        self.network = Self.makeNetwork()
        self.locationModel = nil
    }

    /// Creates a `MainView` with explicit dependencies, for previews and tests.
    /// - Parameters:
    ///   - network: The network injected into the environment.
    ///   - locationModel: The location-authorization model backing the
    ///     Nearby tab's permission gate.
    init(network: any NetworkProtocol, locationModel: LocationAuthorization) {
        self.network = network
        self.locationModel = locationModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Nearby", systemImage: "location.fill", value: .nearby) {
                NavigationStack {
                    NearbyView()
                }
                .modifier(nearbyPermissions)
            }
            Tab("Favorites", systemImage: "star.fill", value: .favorites) {
                FavoritesView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView()
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .environment(\.network, network)
    }

    /// The permission modifier for the Nearby tab: uses the injected
    /// `locationModel` when provided (previews/tests), otherwise falls back to
    /// the default `--skip-location-permission`-aware modifier.
    private var nearbyPermissions: some ViewModifier {
        if let locationModel {
            return NearbyPermissionModifier(model: locationModel) { selectedTab = .search }
        }
        return NearbyPermissionModifier { selectedTab = .search }
    }

    private static func makeNetwork() -> any NetworkProtocol {
        if CommandLine.arguments.contains(mockNetworkLaunchArgument) {
            mockNetwork()
        } else {
            LiveNetwork()
        }
    }
}

/// Bridges `MainView`'s optional injected `LocationAuthorization` to the
/// `.locationPermissions` modifier, choosing the model-backed or default init.
private struct NearbyPermissionModifier: ViewModifier {
    let model: LocationAuthorization?
    let onManualSearch: () -> Void

    func body(content: Content) -> some View {
        if let model {
            content.locationPermissions(model: model, onManualSearch: onManualSearch)
        } else {
            content.locationPermissions(onManualSearch: onManualSearch)
        }
    }
}

// MARK: - Preview

extension MainView {

    /// A mock network serving the default nearby stops plus per-stop
    /// departures keyed by their area ids, so the Stop board screen renders
    /// real rows in the preview. `Folkungagatan` has no departures configured,
    /// so its board shows the empty state.
    private static func previewNetwork() -> some NetworkProtocol {
        MockTrafiklabService(
            departuresByAreaId: [
                "740000001": previewDepartures,
                "740000002": previewDepartures
            ]
        )
    }

    /// A pre-authorized location model delivering a fixed Stockholm coordinate,
    /// so the Nearby tab renders its stops in the preview without a permission
    /// prompt.
    @MainActor
    private static func previewLocationModel() -> LocationAuthorization {
        let manager = FixedLocationManager(
            authorizationStatus: .authorizedWhenInUse,
            coordinate: CLLocationCoordinate2D(latitude: 59.31, longitude: 18.07)
        )
        let model = LocationAuthorization(manager: manager)
        model.startUpdating()
        return model
    }

    /// A handful of departures exercising the row variants: an on-time bus, a
    /// delayed tram, and a cancelled metro.
    private static var previewDepartures: [CallAtLocation] {
        [
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 2),
                realtime: Self.futureTimestamp(minutesFromNow: 2),
                delay: 0,
                canceled: false,
                is_realtime: true,
                route: Route(designation: "3", transport_mode: "BUS", direction: "Karolinska sjukhuset", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            ),
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 5),
                realtime: Self.futureTimestamp(minutesFromNow: 8),
                delay: 180,
                canceled: false,
                is_realtime: true,
                route: Route(designation: "7", transport_mode: "TRAM", direction: "Ropsten", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            ),
            CallAtLocation(
                scheduled: Self.futureTimestamp(minutesFromNow: 9),
                realtime: nil,
                delay: nil,
                canceled: true,
                is_realtime: false,
                route: Route(designation: "T14", transport_mode: "METRO", direction: "Fruängen", name: nil),
                agency: nil,
                trip: nil,
                stop: nil,
                scheduled_platform: nil,
                realtime_platform: nil,
                alerts: nil
            )
        ]
    }

    /// Formats a timestamp `minutesFromNow` minutes ahead as the Trafiklab
    /// realtime format `YYYY-MM-DDTHH:mm:ss` in the current time zone.
    private static func futureTimestamp(minutesFromNow: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutesFromNow) * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

#Preview {
    MainView(
        network: MainView.previewNetwork(),
        locationModel: MainView.previewLocationModel()
    )
}
