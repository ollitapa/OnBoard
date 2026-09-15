import SwiftUI

/// Environment value extension for dependency injection.
/// Provides access to NetworkProtocol through the SwiftUI environment.
exension EnvironmentValues {
    /// A dependency that provides network functionality.
    /// Defaults to LiveNetwork for production use.
    @Entry var network: NetworkProtocol = LiveNetwork()
}
