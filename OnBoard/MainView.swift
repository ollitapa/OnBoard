import SwiftUI

enum Tabs: String, Hashable {
    case nearby
    case favorites
    case search
}

struct MainView: View {

    @SceneStorage("SelectedTab") private var selectedTab: Tabs = .nearby

    /// The favourites model shared across the Favourites tab and the Stop
    /// board's star toggle. Owned in `@State` so it is constructed once per
    /// session and survives re-renders; the launched `loadFavorites` keeps the
    /// Favourites tab and the star toggle in sync. `nil` when an explicit
    /// `favoritesModel` is passed, in which case the injected model wins.
    @State var favoritesModel: FavoritesModel = Self.makeFavoritesModel()

    /// The network dependency injected into the environment. Built from the
    /// launch arguments by default so the `--mock-network` UI-test harness is
    /// served canned data; previews/tests pass an explicit value.
    @State var network: any NetworkProtocol = Self.makeNetwork()

    /// The location-authorization model backing the Nearby tab's permission
    /// gate. `nil` by default, in which case the `.locationPermissions` modifier
    /// builds its own model from the launch arguments; previews/tests pass a
    /// pre-authorized model so the nearby list renders without a real prompt.
    @State var locationModel: LocationAuthorization = Self.makeLocationAuthorization()


    init() { }

    /// Creates a `MainView` with explicit favourites dependencies, for
    /// previews and tests that need a pre-populated model so the star toggle
    /// and the Favourites tab share one list.
    /// - Parameters:
    ///   - network: The network injected into the environment.
    ///   - locationModel: The location-authorization model backing the
    ///     Nearby tab's permission gate.
    ///   - favoritesModel: The shared favourites model.
    init(
        network: any NetworkProtocol,
        locationModel: LocationAuthorization,
        favoritesModel: FavoritesModel
    ) {
        self.network = network
        self.locationModel = locationModel
        self.favoritesModel = favoritesModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Nearby", systemImage: "location.fill", value: .nearby) {
                NavigationStack {
                    NearbyView()
                }
            }
            Tab("Favorites", systemImage: "star.fill", value: .favorites) {
                NavigationStack {
                    FavoritesView()
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView()
            }
        }
        .task {
            await favoritesModel.loadFavorites()
        }
        .tabViewSearchActivation(.searchTabSelection)
        .environment(\.network, network)
        .environment(locationModel)
        .environment(favoritesModel)
    }

    private static func makeNetwork() -> any NetworkProtocol {
        if CommandLine.arguments.contains(mockNetworkLaunchArgument) {
            mockNetwork()
        } else {
            LiveNetwork()
        }
    }

    @MainActor
    private static func makeFavoritesModel() -> FavoritesModel {
        let model = FavoritesModel(fileStorage: liveFavoritesStorage())
        return model
    }

    private static func makeLocationAuthorization() -> LocationAuthorization {
        if CommandLine.arguments.contains(skipLocationPermissionLaunchArgument) {
            return previewLocationAuthorization()
        } else {
            return LocationAuthorization()
        }
    }
}

#Preview {
    MainView(
        network: mockNetwork(),
        locationModel: previewLocationAuthorization(),
        favoritesModel: mockFavoritesModel()
    )
}
