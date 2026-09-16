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

    @State private var model: LocationAuthorization

    /// Called when the user taps "Sök manuellt istället" in the denied view,
    /// so the app can switch to the search tab.
    var onManualSearch: () -> Void

    /// Creates the modifier backed by a real `CLLocationManager`.
    /// - Parameter onManualSearch: Invoked when the user chooses manual search
    ///   from the denied view.
    init(onManualSearch: @escaping () -> Void = {}) {
        self._model = State(initialValue: LocationAuthorization())
        self.onManualSearch = onManualSearch
    }

    /// Creates the modifier backed by the given model, for previews and tests.
    init(model: LocationAuthorization, onManualSearch: @escaping () -> Void = {}) {
        self._model = State(initialValue: model)
        self.onManualSearch = onManualSearch
    }

    func body(content: Content) -> some View {
        content
            .environment(\.locationAuthorization, model)
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
    /// then the content once authorized — or the "Platstillgång är av" view if
    /// denied. The ``LocationAuthorization`` model is published into the
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

/// Environment entry for the location authorization model, mirroring
/// `.network`. Descendant views read `@Environment(\.locationAuthorization)` to
/// obtain the current coordinate and authorization status.
///
/// The default is `nil` because constructing a `@MainActor` model in the
/// `nonisolated` `EnvironmentKey.defaultValue` is not allowed; the
/// `.locationPermissions` modifier always injects a real model, so views used
/// within it receive a non-`nil` value.
extension EnvironmentValues {

    /// The location authorization model published by `.locationPermissions`,
    /// or `nil` when read outside a `.locationPermissions` hierarchy.
    @Entry var locationAuthorization: LocationAuthorization?
}

#Preview("Gated") {
    Color.clear
        .locationPermissions()
}
