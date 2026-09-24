import SwiftUI

/// The app's primary action button style, matching the storyboard's
/// `btn-primary`: white bold text on the accent colour, in a capsule with
/// 28/11 pt padding. Pressing deepens the fill to ``Color/accentDeep``.
///
/// Used as `Button(.locationOpenSettings, action: ...).buttonStyle(.primary)`.
struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 11)
            .background(
                configuration.isPressed ? Color.accentDeep : Color.accent,
                in: Capsule()
            )
            .animation(.default, value: configuration.isPressed)
    }
}

/// The app's secondary text button style, matching the storyboard's
/// `btn-text`: ink-soft semibold text with no background. Pressing dims the
/// text. Always paired below a primary button.
///
/// Used as `Button(.locationSearchManually, action: ...).buttonStyle(.text)`.
struct TextButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.inkSoft)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.default, value: configuration.isPressed)
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
        Button(.locationOpenSettings) {}
            .buttonStyle(.primary)
        Button(.locationSearchManually) {}
            .buttonStyle(.text)
    }
    .padding(32)
    .background(Color.paper)
}
