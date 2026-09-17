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
    @State private var favoritesModelState: FavoritesModel = Self.makeFavoritesModel()

    /// The network dependency injected into the environment. Built from the
    /// launch arguments by default so the `--mock-network` UI-test harness is
    /// served canned data; previews/tests pass an explicit value.
    private let network: any NetworkProtocol

    /// The location-authorization model backing the Nearby tab's permission
    /// gate. `nil` by default, in which case the `.locationPermissions` modifier
    /// builds its own model from the launch arguments; previews/tests pass a
    /// pre-authorized model so the nearby list renders without a real prompt.
    private let locationModel: LocationAuthorization?

    /// The favourites model shared across the Favourites tab and the Stop
    /// board's star toggle. `nil` by default, in which case the view uses the
    /// `@State`-owned ``favoritesModelState``; previews/tests pass a
    /// pre-populated model so the two screens share one list without the app's
    /// file-backed store.
    private let favoritesModel: FavoritesModel?

    init() {
        self.network = Self.makeNetwork()
        self.locationModel = nil
        self.favoritesModel = nil
    }

    /// Creates a `MainView` with explicit dependencies, for previews and tests.
    /// - Parameters:
    ///   - network: The network injected into the environment.
    ///   - locationModel: The location-authorization model backing the
    ///     Nearby tab's permission gate.
    init(network: any NetworkProtocol, locationModel: LocationAuthorization) {
        self.network = network
        self.locationModel = locationModel
        self.favoritesModel = nil
    }

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
                .modifier(nearbyPermissions)
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
        .tabViewSearchActivation(.searchTabSelection)
        .environment(\.network, network)
        .environment(\.favoritesModel, favoritesModel ?? favoritesModelState)
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

    /// Builds the shared `FavoritesModel` for the default init, backed by a
    /// file-backed live store, and loads its persisted list once at launch so
    /// the Favourites tab and the star toggle start in sync. The store built
    /// by the default init isn't available here (the init assigns it directly
    /// to the `let`), so this uses the live store directly; previews/tests pass
    /// an explicit `favoritesModel` and skip this path.
    @MainActor
    private static func makeFavoritesModel() -> FavoritesModel {
        let model = FavoritesModel(fileStorage: liveFavoritesStorage())
        Task { await model.loadFavorites() }
        return model
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
