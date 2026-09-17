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
        /// Launch argument used by UI tests to substitute a mock network for the
        /// production `LiveNetwork`. See `mockNetwork()`.
        if CommandLine.arguments.contains("--mock-network") {
            mockNetwork()
        } else {
            LiveNetwork()
        }
    }

    private static func makeLocationAuthorization() -> LocationAuthorization {
        /// Launch argument that makes `.locationPermissions` skip the system
        /// permission flow and pre-authorize a fixed coordinate, so the Nearby tab
        /// renders stops in UI tests where the simulator can't grant real location
        /// permission. Mirrors the `--mock-network` harness.
        if CommandLine.arguments.contains("--skip-location-permission") {
            return previewLocationAuthorization()
        } else {
            return LocationAuthorization()
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        /// Launch argument used by UI tests to substitute a mock storage for the
        /// production `ModelContainer`. See `mockModelContainer()`.
        if CommandLine.arguments.contains("--mock-storage") {
            return mockModelContainer()
        }
        do {
            return try ModelContainer(for: StoredFavorites.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
