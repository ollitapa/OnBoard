import SwiftUI

extension EnvironmentValues {
    /// A dependency that provides network functionality.
    @Entry var network: NetworkProtocol = LiveNetwork()
}
