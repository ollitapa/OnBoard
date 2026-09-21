import SwiftUI

/// The full-screen icon + headline + message layout shared by the app's
/// standalone message screens (location explanation, denied, failure),
/// matching the storyboard's `permission-screen`: a tinted icon, a centered
/// headline, a secondary body line, and the screen's content below.
struct MessageScreen<Content: View>: View {

    /// The SF Symbol shown above the headline, hidden from accessibility.
    let icon: String

    /// The headline under the icon.
    let title: String

    /// The secondary body line under the headline.
    let message: String

    private let content: () -> Content

    init(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.content = content
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            content()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}

/// The styled placeholder shared by every screen's unavailable states — a
/// load failure or an empty list: an ink label with its SF Symbol and a
/// secondary description in ink-soft, per the storyboard's ink/ink-soft
/// token pairing.
struct UnavailableScreen: View {

    /// The label naming what couldn't load or what's missing, e.g.
    /// "Couldn't load departures".
    let title: String

    /// The SF Symbol beside the title, e.g. `wifi.exclamationmark` for
    /// failures or `tray` for an empty list.
    let systemImage: String

    /// The secondary description under the title, e.g. the model's failure
    /// message.
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.ink)
        } description: {
            Text(message)
                .foregroundStyle(.inkSoft)
        }
    }
}

/// The app's standard loading placeholder, an accent-tinted spinner shown
/// while a screen's first load is in flight.
struct LoadingIndicator: View {

    var body: some View {
        ProgressView()
            .tint(.accent)
    }
}

#Preview("Message screen") {
    MessageScreen(
        icon: "location.slash",
        title: "Location access is off",
        message: "We can't show stops near you. Search manually or turn on location access in Settings."
    ) {
        PrimaryButton("Open Settings")
        TextButton("Search manually instead")
    }
}

#Preview("Unavailable screen") {
    UnavailableScreen(
        title: "No departures",
        systemImage: "tray",
        message: "There are no departures in the next hour."
    )
}
