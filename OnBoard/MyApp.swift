import SwiftUI
import SwiftData

@main struct MyApp: App {
    @State var network: any NetworkProtocol = Self.makeNetwork()
    @State var locationModel: LocationAuthorization = Self.makeLocationAuthorization()
    @State var modelContainer = Self.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.network, network)
                .environment(locationModel)
                .modelContainer(modelContainer)
        }
    }

    private static func makeNetwork() -> any NetworkProtocol {
        if CommandLine.arguments.contains(mockNetworkLaunchArgument) {
            mockNetwork()
        } else {
            LiveNetwork()
        }
    }

    private static func makeLocationAuthorization() -> LocationAuthorization {
        if CommandLine.arguments.contains(skipLocationPermissionLaunchArgument) {
            return previewLocationAuthorization()
        } else {
            return LocationAuthorization()
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: StoredFavorites.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
