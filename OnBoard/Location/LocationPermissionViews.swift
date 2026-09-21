import SwiftUI
import CoreLocationUI

/// The "explanation view" shown before the system location prompt.
///
/// Matches the "SCREEN 0A" design in `Designs/storyboard.html`: a location
/// icon, the headline "Find stops near you", a body explaining why the
/// app wants location, and a single ``LocationButton`` that triggers the
/// system permission prompt.
///
/// Apple forbids offering a "no" option through anything but the system prompt
/// (see https://developer.apple.com/documentation/corelocationui/locationbutton),
/// so this view offers only the affirmative action; denial happens only in the
/// system sheet.
struct LocationExplanationView: View {

    /// Triggered when the user taps the location button, before the system
    /// prompt is shown. The view modifier uses this to start the authorization
    /// request via the injected ``LocationAuthorization`` model.
    var onTap: () -> Void = {}

    var body: some View {
        MessageScreen(
            icon: "location.circle",
            title: "Find stops near you",
            message: "OnBoard uses your location to show the nearest stops as soon as you open the app."
        ) {
            LocationButton(.currentLocation) {
                onTap()
            }
            .symbolVariant(.fill)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// The "permission denied" view shown when location access is turned off, per
/// "SCREEN 0B" in the storyboard. Offers a primary button to open the app's
/// Settings page (so the user can re-enable location) and a text button to
/// fall back to manual search.
struct LocationDeniedView: View {

    /// Triggered by the "Open Settings" button.
    var onOpenSettings: () -> Void = {}

    /// Triggered by the "Search manually instead" button.
    var onManualSearch: () -> Void = {}

    var body: some View {
        MessageScreen(
            icon: "location.slash",
            title: "Location access is off",
            message: "We can't show stops near you. Search manually or turn on location access in Settings."
        ) {
            PrimaryButton("Open Settings", action: onOpenSettings)
            TextButton("Search manually instead", action: onManualSearch)
        }
    }
}

#Preview("Explanation") {
    LocationExplanationView()
}

#Preview("Denied") {
    LocationDeniedView()
}
