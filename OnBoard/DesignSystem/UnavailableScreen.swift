import SwiftUI

/// The styled placeholder shared by every screen's unavailable states — a
/// load failure or an empty list: an ink label with its SF Symbol and a
/// secondary description in ink-soft, per the storyboard's ink/ink-soft
/// token pairing.
struct UnavailableScreen: View {

    /// The label naming what couldn't load or what's missing, e.g.
    /// "Couldn't load departures".
    let title: LocalizedStringResource

    /// The SF Symbol beside the title, e.g. `wifi.exclamationmark` for
    /// failures or `tray` for an empty list.
    let systemImage: String

    /// The secondary description under the title, e.g. the model's failure
    /// message. A `Text` so callers can pass either a localized resource
    /// (`Text(.stopBoardEmptyMessage)`) or a runtime string
    /// (`Text(verbatim: failure)`).
    let message: Text

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.ink)
        } description: {
            message
                .foregroundStyle(.inkSoft)
        }
    }
}

#Preview("Unavailable screen") {
    UnavailableScreen(
        title: .stopBoardEmptyTitle,
        systemImage: "tray",
        message: Text(.stopBoardEmptyMessage)
    )
}
