import SwiftUI

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
        return NearbyPermissionModifier(model: nil) { selectedTab = .search }
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

    init(model: LocationAuthorization? = nil, onManualSearch: @escaping () -> Void) {
        self.model = model
        self.onManualSearch = onManualSearch
    }

    func body(content: Content) -> some View {
        if let model {
            content.locationPermissions(model: model, onManualSearch: onManualSearch)
        } else {
            content.locationPermissions(onManualSearch: onManualSearch)
        }
    }
}

#Preview {
    MainView(
        network: mockNetwork(),
        locationModel: previewLocationAuthorization()
    )
}
