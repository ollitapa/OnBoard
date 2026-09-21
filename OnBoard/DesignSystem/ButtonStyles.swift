import SwiftUI

/// The app's primary action button style, matching the storyboard's
/// `btn-primary`: a large, prominent button for a screen's single main
/// action (e.g. "Open Settings", "Try Again"). Delegates to the system
/// bordered-prominent style so the button keeps native platform behaviour
/// and theming.
///
/// Used as `Button("Open Settings", action: ...).buttonStyle(.primary)`.
struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        BorderedProminentButtonStyle()
            .makeBody(configuration)
            .controlSize(.large)
    }
}

/// The app's secondary text button style, matching the storyboard's
/// `btn-text`: a large borderless button for a screen's fallback action
/// (e.g. "Search manually instead"). Always paired below a primary button.
///
/// Used as `Button("Search manually instead", action: ...).buttonStyle(.text)`.
struct TextButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        BorderlessButtonStyle()
            .makeBody(configuration)
            .controlSize(.large)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {

    /// The primary action button style; see ``PrimaryButtonStyle``.
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == TextButtonStyle {

    /// The secondary text button style; see ``TextButtonStyle``.
    static var text: TextButtonStyle { TextButtonStyle() }
}

#Preview("Buttons") {
    VStack(spacing: 24) {
        Button("Open Settings") {}
            .buttonStyle(.primary)
        Button("Search manually instead") {}
            .buttonStyle(.text)
    }
    .padding(32)
}
