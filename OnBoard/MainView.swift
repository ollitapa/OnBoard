import SwiftUI
import SwiftData

enum Tabs: String, Hashable {
    case nearby
    case favorites
    case search
}

struct MainView: View {

    @SceneStorage("SelectedTab") private var selectedTab: Tabs = .nearby

    @Environment(\.modelContext) private var modelContext

    @State var favoritesModel: FavoritesModel = FavoritesModel()

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
                NavigationStack {
                    SearchView()
                }
            }
        }
        .onAppear {
            favoritesModel.loadFavorites(context: modelContext)
        }
        .tabViewSearchActivation(.searchTabSelection)
        .environment(favoritesModel)
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
