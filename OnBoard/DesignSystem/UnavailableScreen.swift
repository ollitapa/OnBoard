import SwiftUI

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

#Preview("Unavailable screen") {
    UnavailableScreen(
        title: "No departures",
        systemImage: "tray",
        message: "There are no departures in the next hour."
    )
}
