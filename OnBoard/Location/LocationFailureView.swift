import SwiftUI

/// The "location failure" view shown when the location manager reports an
/// error after permission was granted and no coordinate is available.
///
/// Distinct from ``LocationDeniedView``: that view covers a *permission*
/// refusal (fix: Settings), while this covers a *runtime* error such as the
/// system being unable to get a fix (fix: retry). Mirrors the denied view's
/// layout — icon, headline, body, primary action, text action — with a
/// primary button that restarts location updates and a text button to fall
/// back to manual search.
struct LocationFailureView: View {

    /// The raw error reported by the location manager, shown small for
    /// diagnostics, or `nil` when no message is available.
    var failure: String?

    /// Triggered by the "Try Again" button, to restart location updates.
    var onRetry: () -> Void = {}

    /// Triggered by the "Search manually instead" button.
    var onManualSearch: () -> Void = {}

    var body: some View {
        MessageScreen(
            icon: "location.badge.exclamationmark",
            title: "Couldn't find your location",
            message: "Something went wrong while locating you. Try again, or search for a stop manually."
        ) {
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Button("Try Again", action: onRetry)
                .buttonStyle(.primary)
            Button("Search manually instead", action: onManualSearch)
                .buttonStyle(.text)
        }
    }
}

#Preview("Failure") {
    LocationFailureView(
        failure: "Location unavailable",
        onRetry: {},
        onManualSearch: {}
    )
}

#Preview("Failure without message") {
    LocationFailureView(
        failure: nil,
        onRetry: {},
        onManualSearch: {}
    )
}
