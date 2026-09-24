import SwiftUI
import SwiftData

enum Tabs: String, Hashable {
    case nearby
    case favorites
    case search
    case about
}

struct MainView: View {

    @SceneStorage("SelectedTab") private var selectedTab: Tabs = .nearby

    @Environment(\.modelContext) private var modelContext
    @Environment(\.network) private var network

    @State var favoritesModel: FavoritesModel = FavoritesModel()
    @State var tripFavoritesModel: TripFavoritesModel = TripFavoritesModel()
    @State var lineColoursModel: LineColoursModel = LineColoursModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(.tabNearby, systemImage: "location.fill", value: .nearby) {
                NavigationStack {
                    NearbyView()
                }
                .locationPermissions(onManualSearch: {
                    selectedTab = .search
                })
            }

            Tab(.tabFavorites, systemImage: "star.fill", value: .favorites) {
                NavigationStack {
                    FavoritesView()
                }
            }

            Tab(.tabSearch, systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack {
                    SearchView()
                }
            }

            Tab(.tabAbout, systemImage: "info.circle", value: .about) {
                NavigationStack {
                    AboutView()
                }
            }
        }
        .onAppear {
            favoritesModel.loadFavorites(context: modelContext)
            tripFavoritesModel.loadTripFavorites(context: modelContext)
        }
        .task {
            await lineColoursModel.loadLines(network: network)
        }
        .tabViewSearchActivation(.searchTabSelection)
        .environment(favoritesModel)
        .environment(tripFavoritesModel)
        .environment(lineColoursModel)
        .tint(.accent)
        .accentColor(.accent)
    }
}

#Preview {
    @Previewable @State var network: NetworkProtocol = mockNetwork()
    @Previewable @State var locationModel: LocationAuthorization = previewLocationAuthorization()
    @Previewable @State var modelContainer: ModelContainer = mockModelContainer()

    MainView()
        .environment(\.network, network)
        .environment(locationModel)
        .modelContainer(modelContainer)
}
