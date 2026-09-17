import SwiftUI
import CoreLocation

/// A view modifier that gates its content behind the location permission flow.
///
/// While authorization is ``LocationAuthorizationState/notDetermined`` it shows
/// ``LocationExplanationView`` over the content; once the user denies it shows
/// ``LocationDeniedView``. While authorized the content is shown normally and
/// the ``LocationAuthorization`` model is published into the environment so
/// descendant views can read `@Environment(\.locationAuthorization)` to obtain
/// the current coordinate.
///
/// Apple forbids offering "no" through any UI other than the system prompt, so
/// the explanation view offers only a `LocationButton` that triggers the system
/// sheet. See
/// https://developer.apple.com/documentation/corelocationui/locationbutton.
struct LocationPermissionsModifier: ViewModifier {

    @Environment(LocationAuthorization.self) var model

    /// Called when the user taps "Search manually instead" in the denied
    /// view, so the app can switch to the search tab.
    var onManualSearch: () -> Void

    /// Creates the modifier backed by a real `CLLocationManager`, or — when
    /// the `--skip-location-permission` launch argument is present — a mock
    /// manager that is pre-authorized with a fixed coordinate. The latter
    /// keeps the Nearby tab usable in UI tests where the simulator can't
    /// grant real location permission, mirroring the `--mock-network` harness.
    /// - Parameter onManualSearch: Invoked when the user chooses manual search
    ///   from the denied view.
    init(onManualSearch: @escaping () -> Void = {}) {
        self.onManualSearch = onManualSearch
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                switch model.status {
                case .notDetermined:
                    LocationExplanationView(onTap: model.requestAuthorization)
                        .transition(.opacity)
                case .denied:
                    LocationDeniedView(
                        onOpenSettings: Self.openSettings,
                        onManualSearch: onManualSearch
                    )
                    .transition(.opacity)
                case .authorizedWhenInUse, .authorizedAlways:
                    EmptyView()
                }
            }
            .animation(.default, value: model.status)
    }

    /// Opens the app's settings page, where the user can re-enable location.
    private static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {

    /// Gates this view behind the location permission flow.
    ///
    /// Shows the explanation view until the user responds to the system prompt,
    /// then the content once authorized — or the "Location access is off" view
    /// if denied. The ``LocationAuthorization`` model is published into the
    /// environment so descendants can read the current coordinate via
    /// `@Environment(\.locationAuthorization)`.
    /// - Parameter onManualSearch: Invoked when the user chooses manual search
    ///   from the denied view.
    func locationPermissions(
        onManualSearch: @escaping () -> Void = {}
    ) -> some View {
        modifier(LocationPermissionsModifier(onManualSearch: onManualSearch))
    }
}

#Preview("Gated") {
    Color.clear
        .locationPermissions()
        .environment(previewLocationAuthorization())
}
