import SwiftUI

/// The full-screen icon + headline + message layout shared by the app's
/// standalone message screens (location explanation, denied, failure),
/// matching the storyboard's `permission-screen`: a tinted icon, a centered
/// headline, a secondary body line, and the screen's content below.
struct MessageScreen<Content: View>: View {

    /// The SF Symbol shown above the headline, hidden from accessibility.
    let icon: String

    /// The headline under the icon.
    let title: LocalizedStringResource

    /// The secondary body line under the headline.
    let message: LocalizedStringResource

    private let content: () -> Content

    init(
        icon: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
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

#Preview("Message screen") {
    MessageScreen(
        icon: "location.slash",
        title: .locationDeniedTitle,
        message: .locationDeniedMessage
    ) {
        Button(.locationOpenSettings) {}
            .buttonStyle(.primary)
        Button(.locationSearchManually) {}
            .buttonStyle(.text)
    }
}
